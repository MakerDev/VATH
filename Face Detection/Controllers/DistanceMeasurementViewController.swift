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
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Retrieve the synchronized depth and sample buffer container objects.
        guard let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
        
        guard let pixelBuffer = syncedVideoData.sampleBuffer.imageBuffer,
              let cameraCalibrationData = syncedDepthData.depthData.cameraCalibrationData else { return }
        let accuracy = syncedDepthData.depthData.depthDataAccuracy
        
        //TODO: 계산하는 기능 추가하고, gpu, cpu활용해서 성능체크해보기.
        let averageDepthValueInCenter = calculateAverageDepthValue(of: syncedDepthData.depthData.depthDataMap,
                                                                   regionWidth: Int(rectSize.width),
                                                                   regionHeight: Int(rectSize.height))
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
