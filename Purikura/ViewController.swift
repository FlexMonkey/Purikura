//
//  ViewController.swift
//  Purikura
//
//  Created by Simon Gladman on 16/03/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//


import UIKit
import GLKit
import AVFoundation
import CoreMedia

class ViewController: UIViewController
{
    let eaglContext = EAGLContext(api: .openGLES2)
    let captureSession = AVCaptureSession()
    let serialQueue = DispatchQueue(label: "Purikura", attributes: .serial)
    let imageView = GLKView()

    var cameraImage: CIImage?
    
    lazy var ciContext: CIContext =
    {
        [unowned self] in
        
        return  CIContext(eaglContext: self.eaglContext!)
    }()
    
    lazy var detector: CIDetector =
    {
        [unowned self] in
        
        CIDetector(ofType: CIDetectorTypeFace,
            context: self.ciContext,
            options: [
                CIDetectorAccuracy: CIDetectorAccuracyHigh,
                CIDetectorTracking: true])
    }()!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        initialiseCaptureSession()
        
        view.addSubview(imageView)
        imageView.context = eaglContext!
        imageView.delegate = self
    }

    func initialiseCaptureSession()
    {
        captureSession.sessionPreset = AVCaptureSessionPresetPhoto
        
        guard let frontCamera = (AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) as! [AVCaptureDevice])
            .filter({ $0.position == .front })
            .first else
        {
            fatalError("Unable to access front camera")
        }
        
        do
        {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            
            captureSession.addInput(input)
        }
        catch
        {
            fatalError("Unable to add input")
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.setSampleBufferDelegate(self, queue: serialQueue)
        if captureSession.canAddOutput(videoOutput)
        {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.startRunning()
    }
    
    func eyeImage(cameraImage: CIImage) -> CIImage
    {
        
        if let features = detector.features(in: cameraImage).first as? CIFaceFeature
            where features.hasLeftEyePosition && features.hasRightEyePosition
        {
            let eyeDistance = features.leftEyePosition.distanceTo(point: features.rightEyePosition)
            
            return cameraImage
                .applyingFilter("CIBumpDistortion",
                    withInputParameters: [
                        kCIInputRadiusKey: eyeDistance / 1.25,
                        kCIInputScaleKey: 0.5,
                        kCIInputCenterKey: features.leftEyePosition.toCIVector()])
                .cropping(to: cameraImage.extent)
                .applyingFilter("CIBumpDistortion",
                    withInputParameters: [
                        kCIInputRadiusKey: eyeDistance / 1.25,
                        kCIInputScaleKey: 0.5,
                        kCIInputCenterKey: features.rightEyePosition.toCIVector()])
                .cropping(to: cameraImage.extent)
        }
        else
        {
            return cameraImage
        }
    }
    
    override func viewDidLayoutSubviews()
    {
        imageView.frame = view.bounds
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate
{
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!)
    {
        connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIApplication.shared().statusBarOrientation.rawValue)!
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        cameraImage = CIImage(cvPixelBuffer: pixelBuffer!)
        
        DispatchQueue.main.async
        {
            self.imageView.setNeedsDisplay()
        }
    }
}

extension ViewController: GLKViewDelegate
{
    func glkView(_ view: GLKView, drawIn rect: CGRect)
    {
        guard let cameraImage = cameraImage else
        {
            return
        }
        
        let outputImage = eyeImage(cameraImage: cameraImage)

        let aspect = cameraImage.extent.width / cameraImage.extent.height

        let targetWidth = aspect < 1 ?
            Int(CGFloat(imageView.drawableHeight) * aspect) :
            imageView.drawableWidth
        
        let targetHeight = aspect < 1 ?
            imageView.drawableHeight :
            Int(CGFloat(imageView.drawableWidth) / aspect)
        
        ciContext.draw(outputImage,
                       in: CGRect(x: 0, y: 0,
                                  width: targetWidth,
                                  height: targetHeight),
                       from: outputImage.extent)
    }
}

extension CGPoint
{
    func toCIVector() -> CIVector
    {
        return CIVector(x: self.x, y: self.y)
    }
}

extension CGPoint
{
    func distanceTo(point: CGPoint) -> CGFloat
    {
        return hypot(self.x - point.x, self.y - point.y)
    }
}
