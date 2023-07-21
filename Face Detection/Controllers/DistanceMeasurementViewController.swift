//
//  StillImages.swift
//  Face Detection
//
//  Created by Tomasz Baranowicz on 15/07/2020.
//  Copyright © 2020 Tomasz Baranowicz. All rights reserved.
//

import UIKit
import Vision
import AVFoundation
import CoreImage
import Foundation

protocol CaptureDataReceiver: AnyObject {
    func onNewData(capturedData: CameraCapturedData)
    func onNewPhotoData(capturedData: CameraCapturedData)
}

class DistanceMeasurementViewController: UIViewController {
    enum ConfigurationError: Error {
        case lidarDeviceUnavailable
        case requiredFormatUnavailable
    }
    
    //TODO: Overlay a small rect region to calculate the average depth value.
    @IBOutlet var imageView: UIImageView! = UIImageView()
    var scaledImageRect: CGRect?
    private let averageDepthLabel = UILabel()
    private let rectangleLayer = CAShapeLayer()
    private let preferredWidthResolution = 1920
    private let rectSize = CGSize(width: 32, height: 32)
    private let rectangleView = UIView()
    private let videoQueue = DispatchQueue(label: "com.example.facedetection.VideoQueue", qos: .userInteractive)
    
    private let errorMarginMeter:Float = 0.1
    private let stabilizationLatencyMs = 3000
    private var lastRecordTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
    private var lastCaptureTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
    
    private let captureIntervalMs = 10
    private let distanceRecordIntervalMs = 250
    private var distanceQueue: [Float] = []
    private let targetDistanceMeter:Float = 5.0
    private var isDoneMeasuring = false
    
    private(set) var captureSession: AVCaptureSession!
    
    private var photoOutput: AVCapturePhotoOutput!
    private var depthDataOutput: AVCaptureDepthDataOutput!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var outputVideoSync: AVCaptureDataOutputSynchronizer!
    private var cameraManager: CameraManager!
    private var textureCache: CVMetalTextureCache!
    
    weak var delegate: CaptureDataReceiver?
    
    var isFilteringEnabled = true
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Create a texture cache to hold sample buffer textures.
        CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                  nil,
                                  MetalEnvironment.shared.metalDevice,
                                  nil,
                                  &textureCache)
        
        do {
            try setupSession()
        } catch {
            fatalError("Unable to configure the capture session.")
        }
        
        imageView.contentMode = .scaleAspectFit
        imageView.frame = view.bounds
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        
        let screenSize = view.bounds.size
        let rectangleSize = rectSize
        let rectangleOrigin = CGPoint(
            x: (screenSize.width - rectangleSize.width) / 2,
            y: (screenSize.height - rectangleSize.height) / 2
        )
        
        rectangleLayer.strokeColor = UIColor.red.cgColor
        rectangleLayer.lineWidth = 2.0
        rectangleLayer.fillColor = UIColor.clear.cgColor
        rectangleLayer.path = UIBezierPath(rect: CGRect(origin: rectangleOrigin, size: rectangleSize)).cgPath
        imageView.layer.addSublayer(rectangleLayer)
        
        rectangleView.backgroundColor = UIColor.clear
        rectangleView.layer.borderColor = UIColor.blue.cgColor
        rectangleView.layer.borderWidth = 2.0
        rectangleView.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(rectangleView)
        
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            rectangleView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            rectangleView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            rectangleView.widthAnchor.constraint(equalToConstant: rectSize.width),
            rectangleView.heightAnchor.constraint(equalTo: rectangleView.widthAnchor),
        ])
        
        averageDepthLabel.text = "Top-Left Label"
        averageDepthLabel.textColor = UIColor.black
        averageDepthLabel.font = UIFont.systemFont(ofSize: 18)
        averageDepthLabel.sizeToFit()
        averageDepthLabel.frame.origin = CGPoint(x: 16, y: 80)
        view.addSubview(averageDepthLabel)
        
        let informationLabel = UILabel()
        informationLabel.numberOfLines = 2
        informationLabel.textColor = .white
        informationLabel.frame.origin = CGPoint(x: UIScreen.main.bounds.size.width / 2, y: 10)
        informationLabel.text = "모니터 정중앙에 표시를 맞춰주시고\n5m가 되었을때 3초이상 유지해주세요."
        informationLabel.font =  UIFont.boldSystemFont(ofSize: 20)
        view.addSubview(informationLabel)
        
        cameraManager = CameraManager(controller: self)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update the position and size of the red rectangle based on the current screen size
        let screenSize = view.bounds.size
        let rectangleSize = rectSize
        let rectangleOrigin = CGPoint(x: (screenSize.width - rectangleSize.width) / 2, y: (screenSize.height - rectangleSize.height) / 2)
        
        rectangleLayer.path = UIBezierPath(rect: CGRect(origin: rectangleOrigin, size: rectangleSize)).cgPath
        
        rectangleView.layer.cornerRadius = rectangleView.frame.width / 2.0
    }
    
    
    private func setupSession() throws {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .inputPriority

        // Configure the capture session.
        captureSession.beginConfiguration()
        
        try setupCaptureInput()
        setupCaptureOutputs()
        
        // Finalize the capture session configuration.
        captureSession.commitConfiguration()
    }
    
    private func setupCaptureInput() throws {
        // Look up the LiDAR camera.
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            throw ConfigurationError.lidarDeviceUnavailable
        }
        
        // Find a match that outputs video data in the format the app's custom Metal views require.
        guard let format = (device.formats.last { format in
            format.formatDescription.dimensions.width == preferredWidthResolution &&
            format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
            !format.isVideoBinned &&
            !format.supportedDepthDataFormats.isEmpty
        }) else {
            throw ConfigurationError.requiredFormatUnavailable
        }
        
        // Find a match that outputs depth data in the format the app's custom Metal views require.
        guard let depthFormat = (format.supportedDepthDataFormats.last { depthFormat in
            depthFormat.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
        }) else {
            throw ConfigurationError.requiredFormatUnavailable
        }
        
        // Begin the device configuration.
        try device.lockForConfiguration()

        // Configure the device and depth formats.
        device.activeFormat = format
        device.activeDepthDataFormat = depthFormat

        // Finish the device configuration.
        device.unlockForConfiguration()
        
        print("Selected video format: \(device.activeFormat)")
        print("Selected depth format: \(String(describing: device.activeDepthDataFormat))")
        
        // Add a device input to the capture session.
        let deviceInput = try AVCaptureDeviceInput(device: device)
        captureSession.addInput(deviceInput)
    }
    
    private func setupCaptureOutputs() {
        // Create an object to output video sample buffers.
        videoDataOutput = AVCaptureVideoDataOutput()
        captureSession.addOutput(videoDataOutput)
        
        // Create an object to output depth data.
        depthDataOutput = AVCaptureDepthDataOutput()
        depthDataOutput.isFilteringEnabled = isFilteringEnabled
        captureSession.addOutput(depthDataOutput)

        // Create an object to synchronize the delivery of depth and video data.
        outputVideoSync = AVCaptureDataOutputSynchronizer(dataOutputs: [depthDataOutput, videoDataOutput])
        outputVideoSync.setDelegate(self, queue: videoQueue)

        // Enable camera intrinsics matrix delivery.
        guard let outputConnection = videoDataOutput.connection(with: .video) else { return }
        if outputConnection.isCameraIntrinsicMatrixDeliverySupported {
            outputConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        
        // Create an object to output photos.
        photoOutput = AVCapturePhotoOutput()
        photoOutput.maxPhotoQualityPrioritization = .quality
        captureSession.addOutput(photoOutput)

        // Enable delivery of depth data after adding the output to the capture session.
        photoOutput.isDepthDataDeliveryEnabled = true
    }
    
    func startStream() {
        captureSession.startRunning()
    }
    
    func stopStream() {
        captureSession.stopRunning()
    }
}


extension DistanceMeasurementViewController: AVCaptureDataOutputSynchronizerDelegate {
    func showDoneEffect() {
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(overlayView)
        
        // Set up auto layout constraints for the overlay view
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let dialogView = UIView()
        // Create the dialog view
        dialogView.backgroundColor = UIColor.white
        dialogView.layer.cornerRadius = 12
        dialogView.layer.shadowColor = UIColor.gray.cgColor
        dialogView.layer.shadowOffset = CGSize(width: 0, height: 2)
        dialogView.layer.shadowOpacity = 0.8
        dialogView.layer.shadowRadius = 4
        
        let imageName = "great"
        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        dialogView.addSubview(imageView)
        
        let label = UILabel()
        label.numberOfLines = 2
        label.text = "거리 설정이 완료되었습니다!"
        
        label.font = UIFont.boldSystemFont(ofSize: 24)
        label.textColor = UIColor.black
        label.textAlignment = .center
        dialogView.addSubview(label)
        
        // Add the dialog view to the main view
//        view.addSubview(dialogView)
        overlayView.addSubview(dialogView)
        
        let screenHeight = UIScreen.main.bounds.size.height
        let screenWidth = UIScreen.main.bounds.size.width
        
        // Set up auto layout constraints for the dialog view
        dialogView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dialogView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dialogView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dialogView.widthAnchor.constraint(equalToConstant: screenWidth*0.9),
            dialogView.heightAnchor.constraint(equalToConstant: screenHeight*0.75)
        ])
        
        // Set up auto layout constraints for the image view
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: dialogView.topAnchor, constant: 40),
            imageView.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor, constant: -20),
            imageView.heightAnchor.constraint(equalToConstant: screenHeight*0.75*0.5)
        ])
        
        // Set up auto layout constraints for the label
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: dialogView.bottomAnchor, constant: -20)
        ])
        
        dialogView.alpha = 1
        overlayView.alpha = 1
        // Fade out the dialog after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            UIView.animate(withDuration: 0.5, animations: {
                dialogView.alpha = 0
                overlayView.alpha = 0
            }) { _ in
                dialogView.removeFromSuperview()
                overlayView.removeFromSuperview()
                label.removeFromSuperview()
            }
        }
    }
    
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        let currentTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
//        if currentTimestamp - lastCaptureTimestamp <= captureIntervalMs {
//            return
//        }
//        lastCaptureTimestamp = currentTimestamp
        
        // Retrieve the synchronized depth and sample buffer container objects.
        guard let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
        
        guard let pixelBuffer = syncedVideoData.sampleBuffer.imageBuffer,
              let cameraCalibrationData = syncedDepthData.depthData.cameraCalibrationData else { return }
        let accuracy = syncedDepthData.depthData.depthDataAccuracy
        
        //gpu, cpu활용해서 성능체크해보기.
        let averageDepthValueInCenter = calculateAverageDepthValue(of: syncedDepthData.depthData.depthDataMap,
                                                                   regionWidth: Int(rectSize.width),
                                                                   regionHeight: Int(rectSize.height))
        
        if currentTimestamp - lastRecordTimestamp > distanceRecordIntervalMs {
            let maxCount = stabilizationLatencyMs / distanceRecordIntervalMs
            if distanceQueue.count > maxCount {
                distanceQueue.removeFirst()
            }
            
            distanceQueue.append(averageDepthValueInCenter)
            lastRecordTimestamp = currentTimestamp
            if distanceQueue.count >= maxCount {
                let averageDistance = Float(distanceQueue.reduce(0, +)) / Float(distanceQueue.count)
                
                if (targetDistanceMeter + errorMarginMeter > averageDistance) &&
                    (averageDistance > targetDistanceMeter - errorMarginMeter) && !isDoneMeasuring {
                    //TODO: 확인 프롬프트 띄워주기
                    DispatchQueue.main.async {
                        self.showDoneEffect()
                    }
                    
                    AudioController.playSound(soundName: "ok-to-go", extensionType: "wav")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        AudioController.playSound(soundName: "distance-ok-voice")
                    }
                    isDoneMeasuring = true
                }
            }
        }
        
        DispatchQueue.main.async {
            if let depthImage = self.convertPixelBufferToUIImage(pixelBuffer) {
                self.imageView.image = self.fixOrientation(for: depthImage)
            }
            
            let formattedAverage = String(format: "%.2f", averageDepthValueInCenter)
            
            if accuracy == .absolute {
                self.averageDepthLabel.text = "Absolute: \(formattedAverage)"
            } else {
                self.averageDepthLabel.text = "Relative: \(formattedAverage)"
            }
        }
        
        // Package the captured data.
        let data = CameraCapturedData(depth: syncedDepthData.depthData.depthDataMap.texture(withFormat: .r16Float, planeIndex: 0, addToCache: textureCache),
                                      colorY: pixelBuffer.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache),
                                      colorCbCr: pixelBuffer.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache),
                                      cameraIntrinsics: cameraCalibrationData.intrinsicMatrix,
                                      cameraReferenceDimensions: cameraCalibrationData.intrinsicMatrixReferenceDimensions)
        
        delegate?.onNewData(capturedData: data)
    }
    
    private func convertPixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage
        }
        return nil
    }
    
    func fixOrientation(for image: UIImage) -> UIImage {
        if image.imageOrientation == .left {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let fixedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return fixedImage ?? image
    }
    
    func calculateAverageDepthValue(of pixelBuffer: CVPixelBuffer, regionWidth: Int, regionHeight: Int) -> Float {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard pixelFormat == kCVPixelFormatType_DepthFloat16 || pixelFormat == kCVPixelFormatType_DisparityFloat16 else {
            return -1 // Unsupported pixel format
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let regionWidth = min(width, regionWidth)
            let regionHeight = min(height, regionHeight)
            
            let regionStartX = (width - regionWidth) / 2
            let regionStartY = (height - regionHeight) / 2
            
            var sum: Float = 0.0
            
            for y in 0..<regionHeight {
                let row = baseAddress.advanced(by: (regionStartY + y) * bytesPerRow).assumingMemoryBound(to: Float16.self)
                
                for x in 0..<regionWidth {
                    let depthValue = row[regionStartX + x]
                    sum += Float(depthValue)
                }
            }
            
            let numPixels = regionWidth * regionHeight
            let averageDepthValue = sum / Float(numPixels)
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            
            return averageDepthValue
        } else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return -1
        }
    }
}
