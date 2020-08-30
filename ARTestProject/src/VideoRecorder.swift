//
//  VideoRecorder.swift
//  ARTestProject
//
//  Created by Yuri on 30.08.2020.
//

import Foundation
import ARKit
import Photos

class VideoRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {

    //MARK: - Public Properties

    var sceneView: ARSCNView!
    var isRecording: Bool = false

    //MARK: Private Properties

    private var videoStartTime: CMTime?
    private var lastTime: TimeInterval = 0

    private var tmpURL: URL
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var assetWriter: AVAssetWriter?

    private var captureSession: AVCaptureSession?
    private var micInput: AVCaptureDeviceInput?
    private var audioOutput: AVCaptureAudioDataOutput?

    override init() {
        tmpURL =  URL.init(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    //MARK: Public Methods

    func setup(completionHandler:@escaping(Error?)->()) {
        self.captureSession = AVCaptureSession()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
        }
        self.createURLForVideo(withName: "test") { (videoURL) in
            self.prepareWriterAndInput(size:self.sceneView.frame.size, videoURL: videoURL, completionHandler: { (error) in
                completionHandler(error)
            })
        }
    }

    func startRecording() {
        setup { (error) in
            guard error == nil else {
                return
            }
            self.startAudioRecording { (result) in

                guard result == true else {
                    print("FAILED TO START AUDIO SESSION")
                    return
                }
                self.lastTime = 0
                self.isRecording = true
            }
        }
    }

    func stopRecording() {
        self.isRecording = false
        self.endAudioRecording()
        self.finishVideoRecordingAndSave()
    }

    public func didUpdateAtTime(time: TimeInterval) {

        if self.isRecording {
            if self.lastTime == 0 || (self.lastTime + 1/25) < time {
                DispatchQueue.main.async { [weak self] () -> Void in

                    let scale = CMTimeScale(NSEC_PER_SEC)
                    var currentFrameTime:CMTime = CMTime(value: CMTimeValue((self?.sceneView.session.currentFrame!.timestamp)! * Double(scale)), timescale: scale)

                    if self?.lastTime == 0 {
                        self?.videoStartTime = currentFrameTime
                    }

                    guard self != nil else { return }
                    self!.lastTime = time

                    // VIDEO
                    let snapshot = (self?.sceneView.snapshot())!
                    self?.createPixelBufferFromUIImage(image: snapshot, completionHandler: { (error, pixelBuffer) in

                        guard error == nil else {
                            print("failed to get pixelBuffer")
                            return
                        }

                        currentFrameTime = currentFrameTime - self!.videoStartTime!

                        self!.pixelBufferAdaptor!.append(pixelBuffer!, withPresentationTime: currentFrameTime)

                    })
                }
            }
        }
    }

    // MARK: SAVE VIDEO FUNCTIONALITY

    private func createURLForVideo(withName:String, completionHandler:@escaping (URL)->()) {
        let targetURL:URL = self.tmpURL.appendingPathComponent("\(withName).mp4")
        // Delete the file, incase it exists.
        do {
            try FileManager.default.removeItem(at: targetURL)
        } catch let error {
            NSLog("Unable to delete file, with error: \(error)")
        }
        DispatchQueue.main.async { () -> Void in
            completionHandler(targetURL)
        }
    }

    private func prepareWriterAndInput(size:CGSize, videoURL:URL, completionHandler:@escaping(Error?)->()) {

        do {
            self.assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: AVFileType.mp4)

            // Input is the mic audio of the AVAudioEngine
            let audioOutputSettings = [
                AVFormatIDKey : kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey : 2,
                AVSampleRateKey : 44100.0,
                AVEncoderBitRateKey: 192000
            ] as [String : Any]

            self.audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings)
            self.audioInput!.expectsMediaDataInRealTime = true
            self.assetWriter?.add(self.audioInput!)

            // Video Input Creator

            let videoOutputSettings: Dictionary<String, Any> = [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoWidthKey : size.width,
                AVVideoHeightKey : size.height
            ]

            self.videoInput  = AVAssetWriterInput (mediaType: AVMediaType.video, outputSettings: videoOutputSettings)
            self.videoInput!.expectsMediaDataInRealTime = true
            self.assetWriter!.add(self.videoInput!)

            // Create Pixel buffer Adaptor

            let sourceBufferAttributes:[String : Any] = [
                (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32ARGB),
                (kCVPixelBufferWidthKey as String): Float(size.width),
                (kCVPixelBufferHeightKey as String): Float(size.height)] as [String : Any]

            self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.videoInput!, sourcePixelBufferAttributes: sourceBufferAttributes)

            self.assetWriter?.startWriting()
            self.assetWriter?.startSession(atSourceTime: CMTime.zero)
            completionHandler(nil)
        }
        catch {
            print("Failed to create assetWritter with error : \(error)")
            completionHandler(error)
        }
    }

    private func createVideo(imageArray:[[String:Any]], fps:Int, size:CGSize, completionHandler:@escaping(String?)->()) {

        var currentframeTime:CMTime = CMTime.zero
        var currentFrame:Int = 0

        let startTime:CMTime = (imageArray[0])["time"] as! CMTime

        while (currentFrame < imageArray.count) {

            if (self.videoInput?.isReadyForMoreMediaData)!  {
                let currentImage:UIImage = (imageArray[currentFrame])["image"] as! UIImage
                let currentCGImage:CGImage? = currentImage.cgImage

                guard currentCGImage != nil else {
                    completionHandler("failed to get current cg image")
                    return
                }

                self.createPixelBufferFromUIImage(image: currentImage) { (error, pixelBuffer) in

                    guard error == nil else {
                        completionHandler("failed to get pixelBuffer")
                        return
                    }

                    currentframeTime = (imageArray[currentFrame])["time"] as! CMTime - startTime
                    self.pixelBufferAdaptor!.append(pixelBuffer!, withPresentationTime: currentframeTime)

                    currentFrame += 1
                }
            }
        }

        completionHandler(nil)
    }


    private func createPixelBufferFromUIImage(image:UIImage, completionHandler:@escaping(String?, CVPixelBuffer?) -> ()) {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {
            completionHandler("Failed to create pixel buffer", nil)
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.translateBy(x: 0, y: image.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context!)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        completionHandler(nil, pixelBuffer)
    }


    private func finishVideoRecordingAndSave() {
        self.videoInput!.markAsFinished()
        self.assetWriter?.finishWriting(completionHandler: {
            print("output url : \(String(describing: self.assetWriter?.outputURL))")

            PHPhotoLibrary.requestAuthorization({ (status) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: (self.assetWriter?.outputURL)!)
                }) { saved, error in
                    guard error == nil else {
                        print("failed to save video: \(String(describing: error?.localizedDescription))")
                        return
                    }
                }
            })
        })
    }
    
    // MARK:  AUDIO FUNCTIONALITY

    private func startAudioRecording(completionHandler:@escaping(Bool) -> ()) {

        let microphone = AVCaptureDevice.default(.builtInMicrophone, for: AVMediaType.audio, position: .unspecified)

        do {
            try self.micInput = AVCaptureDeviceInput(device: microphone!)



            if (self.captureSession?.canAddInput(self.micInput!))! {
                self.captureSession?.addInput(self.micInput!)

                self.audioOutput = AVCaptureAudioDataOutput()

                if self.captureSession!.canAddOutput(self.audioOutput!){
                    self.captureSession!.addOutput(self.audioOutput!)
                    self.audioOutput?.setSampleBufferDelegate(self, queue: DispatchQueue.global())

                    self.captureSession?.startRunning()
                    completionHandler(true)
                }

            }
        }
        catch {
            completionHandler(false)
        }
    }

    private func endAudioRecording() {
        self.captureSession!.stopRunning()
    }

    //MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: CMTimeMake(value: 0, timescale: 0), presentationTimeStamp: CMTimeMake(value: 0, timescale: 0), decodeTimeStamp: CMTimeMake(value: 0, timescale: 0)), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &info, entriesNeededOut: &count)

        let scale = CMTimeScale(NSEC_PER_SEC)
        var currentFrameTime:CMTime = CMTime(value: CMTimeValue((self.sceneView.session.currentFrame!.timestamp) * Double(scale)), timescale: scale)

        currentFrameTime = currentFrameTime-self.videoStartTime!

        for i in 0..<count {
            info[i].decodeTimeStamp = currentFrameTime
            info[i].presentationTimeStamp = currentFrameTime
        }

        var soundbuffer:CMSampleBuffer?

        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: count, sampleTimingArray: &info, sampleBufferOut: &soundbuffer)

        self.audioInput?.append(soundbuffer!)
    }

}
