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
    let eaglContext = EAGLContext(API: .OpenGLES2)
    let captureSession = AVCaptureSession()
    
    let imageView = GLKView()

    var cameraImage: CIImage?
    
    lazy var ciContext: CIContext =
    {
        [unowned self] in
        
        return  CIContext(EAGLContext: self.eaglContext)
    }()
    
    lazy var detector: CIDetector =
    {
        [unowned self] in
        
        CIDetector(ofType: CIDetectorTypeFace,
            context: self.ciContext,
            options: [
                CIDetectorAccuracy: CIDetectorAccuracyHigh,
                CIDetectorTracking: true])
    }()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        initialiseCaptureSession()
        
        view.addSubview(imageView)
        imageView.context = eaglContext
        imageView.delegate = self
    }

    func initialiseCaptureSession()
    {
        captureSession.sessionPreset = AVCaptureSessionPresetPhoto
        
        guard let frontCamera = (AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice])
            .filter({ $0.position == .Front })
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
        
        videoOutput.setSampleBufferDelegate(self, queue: dispatch_queue_create("sample buffer delegate", DISPATCH_QUEUE_SERIAL))
        if captureSession.canAddOutput(videoOutput)
        {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.startRunning()
    }
    
    func eyeImage(cameraImage: CIImage) -> CIImage
    {
        
        if let features = detector.featuresInImage(cameraImage).first as? CIFaceFeature
            where features.hasLeftEyePosition && features.hasRightEyePosition
        {
            let eyeDistance = features.leftEyePosition.distanceTo(features.rightEyePosition)
            
            return cameraImage
                .imageByApplyingFilter("CIBumpDistortion",
                    withInputParameters: [
                        kCIInputRadiusKey: eyeDistance / 1.25,
                        kCIInputScaleKey: 0.5,
                        kCIInputCenterKey: features.leftEyePosition.toCIVector()])
                .imageByCroppingToRect(cameraImage.extent)
                .imageByApplyingFilter("CIBumpDistortion",
                    withInputParameters: [
                        kCIInputRadiusKey: eyeDistance / 1.25,
                        kCIInputScaleKey: 0.5,
                        kCIInputCenterKey: features.rightEyePosition.toCIVector()])
                .imageByCroppingToRect(cameraImage.extent)
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
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!)
    {
        connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIApplication.sharedApplication().statusBarOrientation.rawValue)!
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        cameraImage = CIImage(CVPixelBuffer: pixelBuffer!)
        
        dispatch_async(dispatch_get_main_queue())
        {
            self.imageView.setNeedsDisplay()
        }
    }
}

extension ViewController: GLKViewDelegate
{
    func glkView(view: GLKView, drawInRect rect: CGRect)
    {
        guard let cameraImage = cameraImage else
        {
            return
        }
        
        let outputImage = eyeImage(cameraImage)

        let aspect = cameraImage.extent.width / cameraImage.extent.height

        let targetWidth = aspect < 1 ?
            Int(CGFloat(imageView.drawableHeight) * aspect) :
            imageView.drawableWidth
        
        let targetHeight = aspect < 1 ?
            imageView.drawableHeight :
            Int(CGFloat(imageView.drawableWidth) / aspect)
        
        ciContext.drawImage(outputImage,
            inRect: CGRect(x: 0, y: 0,
                width: targetWidth,
                height: targetHeight),
            fromRect: outputImage.extent)
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
