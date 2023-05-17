//
//  LiveFeedViewController.swift
//  Face Detection
//
//  Created by Tomasz Baranowicz on 15/07/2020.
//  Copyright © 2020 Tomasz Baranowicz. All rights reserved.
//

import AVFoundation
import UIKit
import Vision
import CoreGraphics
import CoreVideo

class LiveFeedViewController: UIViewController {
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var faceLayers: [CAShapeLayer] = []
    
    private let precisionLabel = UILabel()
    private let eyeDetectionLabel = UILabel()
    private let messageLabel = UILabel()
    
    private let buttonTitles = ["2", "3", "5", "6", "9"]
    private var buttons: [UIButton] = []
    private let calibrationButton = UIButton()
    private var isCalibrated = false
    private var currentImage: CIImage? = nil
    
    private var isCalibrating = false
    private var leftCalibrationConfidenceAverage = 0.0
    private var rightCalibrationConfidenceAverage = 0.0
    private var leftCalibrationConfidenceList: [Double] = []
    private var rightCalibrationConfidenceList: [Double] = []
    private let maxCalibrationCount = 500
    private let leftImageView: UIImageView = UIImageView()
    private let rightImageView: UIImageView = UIImageView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        captureSession.startRunning()
        // Add precision label to the view
        
        setupLabels()
        setupButtons()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.frame
    }
    
    func setupLabels() {
        precisionLabel.frame = CGRect(x: 16, y: 16, width: 600, height: 60)
        precisionLabel.textColor = UIColor.black
        precisionLabel.font = UIFont.boldSystemFont(ofSize: 16)
        view.addSubview(precisionLabel)
        
        messageLabel.frame = CGRect(x: 16, y: 100, width: 600, height: 60)
        messageLabel.textColor = UIColor.black
        messageLabel.font = UIFont.boldSystemFont(ofSize: 16)
        view.addSubview(messageLabel)
        
        eyeDetectionLabel.frame = CGRect(x: 16, y: 200, width: 600, height: 60)
        eyeDetectionLabel.textColor = UIColor.black
        eyeDetectionLabel.font = UIFont.boldSystemFont(ofSize: 16)
        view.addSubview(eyeDetectionLabel)
    }
    
    func setupButtons() {
        let buttonWidth: CGFloat = self.view.frame.width / CGFloat(buttonTitles.count)
        let buttonHeight: CGFloat = 50.0
        let buttonYPosition: CGFloat = self.view.frame.height / 2.0 - buttonHeight / 2.0
        for (index, title) in buttonTitles.enumerated() {
            let button = UIButton(frame: CGRect(x: CGFloat(index) * buttonWidth, y: buttonYPosition, width: buttonWidth, height: buttonHeight))
            button.setTitle(title, for: .normal)
            button.backgroundColor = .blue
            view.addSubview(button)
            buttons.append(button)
        }
        
        setupCalibrationButton()
    }
    
    func setupCalibrationButton() {
        let buttonHeight: CGFloat = 50.0
        let buttonYPosition: CGFloat = self.view.frame.height / 2.0 + buttonHeight / 2.0
        calibrationButton.frame = CGRect(x: 0, y: buttonYPosition, width: self.view.frame.width, height: buttonHeight)
        calibrationButton.setTitle("Calibration", for: .normal)
        calibrationButton.backgroundColor = .green
        calibrationButton.addTarget(self, action: #selector(calibrationButtonTapped), for: .touchUpInside)
        view.addSubview(calibrationButton)
    }

    @objc func calibrationButtonTapped() {
        // Handle the calibration button tap here
        if isCalibrating {
            self.isCalibrating = false
            self.isCalibrated = true
            calibrationButton.setTitle("Calibration", for: .normal)
            calibrationButton.backgroundColor = .green
            
            self.calibrationButton.setTitle("Calibration", for: .normal)
            self.leftCalibrationConfidenceAverage = Double(leftCalibrationConfidenceList.reduce(0, +))
            self.leftCalibrationConfidenceAverage = Double(leftCalibrationConfidenceAverage) / Double(leftCalibrationConfidenceList.count)
            self.rightCalibrationConfidenceAverage = Double(rightCalibrationConfidenceList.reduce(0, +))
            self.rightCalibrationConfidenceAverage = Double(rightCalibrationConfidenceAverage) / Double(rightCalibrationConfidenceList.count)
            
            DispatchQueue.main.async {
                let leftAverageString = String(format: "%.4f", self.leftCalibrationConfidenceAverage)
                let rightAverageString = String(format: "%.4f", self.rightCalibrationConfidenceAverage)
                
                self.messageLabel.text = "Left Avg: \(leftAverageString), Right Avg: \(rightAverageString)"
            }
        } else {
            isCalibrating = true
            calibrationButton.setTitle("Calibrating", for: .normal)
            calibrationButton.backgroundColor = .red
        }
    }

    private func setupCamera() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                    setupVideoDataOutput(showPreview: true)
                }
            }
        }
        
        let screenSize = UIScreen.main.bounds
        let imageWidth: CGFloat = 100.0
        let imageHeight: CGFloat = 100.0
        self.leftImageView.frame = CGRect(x: 0,
                                          y: screenSize.height - imageHeight * 2,
                                          width: imageWidth,
                                          height: imageHeight)
        self.rightImageView.frame = CGRect(x: imageWidth + 20,
                                           y: screenSize.height - imageHeight * 2,
                                           width: imageWidth,
                                           height: imageHeight)
        self.view.addSubview(self.leftImageView)
        self.view.addSubview(self.rightImageView)
    }
    
    private func setupVideoDataOutput(showPreview: Bool = false) {
        if showPreview {
            self.previewLayer.videoGravity = .resizeAspectFill
            self.view.layer.addSublayer(self.previewLayer)
            self.previewLayer.frame = self.view.frame
        }
        
        self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera queue"))
        self.captureSession.addOutput(self.videoDataOutput)
        
        let videoConnection = self.videoDataOutput.connection(with: .video)
        videoConnection?.videoOrientation = .portrait
    }
}

extension LiveFeedViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
          return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        self.currentImage = ciImage
        
        let faceDetectionRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                self.faceLayers.forEach({ drawing in drawing.removeFromSuperlayer() })
                self.faceLayers = []
                
                if let observations = request.results as? [VNFaceObservation] {
                    self.handleFaceDetectionObservations(observations: observations, on: ciImage)
                }
            }
        })

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .leftMirrored, options: [:])

        do {
            try imageRequestHandler.perform([faceDetectionRequest])
        } catch {
            print(error.localizedDescription)
        }
    }
    
    
    private func handleFaceDetectionObservations(observations: [VNFaceObservation], on image: CIImage) {
        for observation in observations {
            let faceRectConverted = self.previewLayer.layerRectConverted(fromMetadataOutputRect: observation.boundingBox)
            let faceRectanglePath = CGPath(rect: faceRectConverted, transform: nil)
            
            let faceLayer = CAShapeLayer()
            faceLayer.path = faceRectanglePath
            faceLayer.fillColor = UIColor.clear.cgColor
            faceLayer.strokeColor = UIColor.yellow.cgColor
            
            self.faceLayers.append(faceLayer)
            self.view.layer.addSublayer(faceLayer)
            
            var leftPupilPrecision = 0.0
            var rightPupilPrecision = 0.0
            var isLeftEyeDetected = false
            var isRightEyeDetected = false
            
            //FACE LANDMARKS
            if let landmarks = observation.landmarks {
                if let leftEye = landmarks.leftEye {
                    self.handleLandmark(leftEye, faceBoundingBox: faceRectConverted)
                    if let image = currentImage {
                        let boundingBox = getFacialRect(image: image, faceBoundingBox: faceRectConverted, isLeft: true)
                        if let croppedImage = cropImage(image: image, boundingBox: boundingBox) {
                            self.leftImageView.image = croppedImage
                            isLeftEyeDetected = MyOpenCV.detectIfExistEyes(in: croppedImage)
                        }
                    }
                }
                
                if let rightEye = landmarks.rightEye {
                    self.handleLandmark(rightEye, faceBoundingBox: faceRectConverted)
                    if let image = currentImage {
                        let boundingBox = getFacialRect(image: image, faceBoundingBox: faceRectConverted, isLeft: false)
                        if let croppedImage = cropImage(image: image, boundingBox: boundingBox) {
                            self.rightImageView.image = croppedImage
                            isRightEyeDetected = MyOpenCV.detectIfExistEyes(in: croppedImage)
                        }
                    }
                }
                
                if let leftPupil = landmarks.leftPupil {
                    self.handleLandmark(leftPupil, faceBoundingBox: faceRectConverted)
                    leftPupilPrecision = Double(leftPupil.precisionEstimatesPerPoint![0]) * 100
                }
                
                if let rightPupil = landmarks.rightPupil {
                    self.handleLandmark(rightPupil, faceBoundingBox: faceRectConverted)
                    // The number of elements in precisionEstimatesPerPoint for a pupil is one.
                    rightPupilPrecision = Double(rightPupil.precisionEstimatesPerPoint![0]) * 100
                }
            }
            
            if self.isCalibrating {
                truncatedAppend(targetList: &self.leftCalibrationConfidenceList, value: leftPupilPrecision, maxCount: self.maxCalibrationCount)
                truncatedAppend(targetList: &self.rightCalibrationConfidenceList, value: rightPupilPrecision, maxCount: self.maxCalibrationCount)
            }
            
            let leftPrecisionText = String(format: "%.4f", leftPupilPrecision)
            let rightPrecisionText = String(format: "%.4f", rightPupilPrecision)
            let precisionLabelText = "Left precision: \(leftPrecisionText), Right precision: \(rightPrecisionText)"
            DispatchQueue.main.async {
                self.precisionLabel.text = precisionLabelText
                self.eyeDetectionLabel.text = "Left: \(isLeftEyeDetected)   Right: \(isRightEyeDetected)"
            }
        }
    }
    
    private func getFacialRect(image:CIImage, faceBoundingBox: CGRect, isLeft:Bool) -> CGRect {
        let scale = UIScreen.main.scale + 2
        let scaleX = image.extent.size.width / UIScreen.main.bounds.width
        let scaleY = image.extent.size.height / UIScreen.main.bounds.height
        let offsetScaleFactor = 0.15
        let sizeScaleFactor = 0.2
        
        if isLeft {
            return CGRect(x: (UIScreen.main.bounds.width - faceBoundingBox.origin.x  - faceBoundingBox.size.width) * scaleX,
                        y: (faceBoundingBox.origin.y + faceBoundingBox.size.height * offsetScaleFactor)*scaleY,
                        width: faceBoundingBox.size.width * scale * sizeScaleFactor,
                        height: faceBoundingBox.size.height * scale * sizeScaleFactor)
        } else {
            return CGRect(x: (UIScreen.main.bounds.width - faceBoundingBox.origin.x -
                              faceBoundingBox.size.width * 0.5) * scaleX,
                         y: (faceBoundingBox.origin.y + faceBoundingBox.size.height * offsetScaleFactor)*scaleY,
                         width: faceBoundingBox.size.width * scale * sizeScaleFactor,
                         height: faceBoundingBox.size.height * scale * sizeScaleFactor)
        }
    }
    
    private func handleLandmark(_ eye: VNFaceLandmarkRegion2D, faceBoundingBox: CGRect) {
        let landmarkPath = CGMutablePath()
        let landmarkPathPoints = eye.normalizedPoints
            .map({ eyePoint in
                CGPoint(
                    x: eyePoint.y * faceBoundingBox.height + faceBoundingBox.origin.x,
                    y: eyePoint.x * faceBoundingBox.width + faceBoundingBox.origin.y)
            })
        landmarkPath.addLines(between: landmarkPathPoints)
        landmarkPath.closeSubpath()
        
        let landmarkLayer = CAShapeLayer()
        landmarkLayer.path = landmarkPath
        landmarkLayer.fillColor = UIColor.clear.cgColor
        landmarkLayer.strokeColor = UIColor.green.cgColor
//
//        self.faceLayers.append(landmarkLayer)
//        self.view.layer.addSublayer(landmarkLayer)
    }
    
    func cropImage(image: CIImage, boundingBox:CGRect) -> UIImage? {
        let ciBoundingBox = CGRect(x: boundingBox.origin.x, y: image.extent.height - boundingBox.origin.y - boundingBox.height, width: boundingBox.width, height: boundingBox.height)
        let croppedImage = image.cropped(to: ciBoundingBox)
        let context = CIContext()
        guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
    
    private func truncatedAppend(targetList: inout [Double], value:Double, maxCount: Int) {
        targetList.append(value)
        
        if targetList.count >= maxCount {
            targetList.remove(at: 0)
        }
    }
}

extension UIImage {
    func convertToRGB() -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(data: nil, width: Int(self.size.width), height: Int(self.size.height), bitsPerComponent: self.cgImage!.bitsPerComponent, bytesPerRow: self.cgImage!.bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        
        context?.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        
        if let cgImage = context?.makeImage() {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
}
