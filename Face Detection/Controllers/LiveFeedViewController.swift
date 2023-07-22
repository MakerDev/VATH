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
import MultipeerConnectivity
import os


class LiveFeedViewController: UIViewController {
    private final let DETECTION_INTERVAL_MS = 100
    private final let EYE_DETECTION_INTERVAL_MS = 100
    private final let EYE_AVERAGE_INTERVAL_MS = 1000
    
    private var lastDetection = Int64(Date().timeIntervalSince1970 * 1000)
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var faceLayers: [CAShapeLayer] = []
    private var score = 0
    private var buttonsEnabled = true // Buttons are disabled when clicked until the result response will come from the server.
    
    private let precisionLabel = UILabel()
    private let eyeDetectionLabel = UILabel()
    private let messageLabel = UILabel()
    
    private let buttonTitles = ["2", "3", "5"]
    private var buttons: [UIButton] = []
    private var currentImage: CIImage? = nil
    
    private let leftImageView: UIImageView = UIImageView()
    private let rightImageView: UIImageView = UIImageView()
    private let dialogView: UIView = UIView()
    
    let log = Logger()
    private let serviceType = "eis-eyesight"
    private let myPeerId = MCPeerID(displayName: "EISiPhone")
    private var serviceBrowser: MCNearbyServiceBrowser!
    var session: MCSession!
    
    private var isTargetLeftEye = false
    private var isTestRunning = false
    
    private var eyeDetectionResultList: [Int] = []
    private var lastEyeDetection: Int64 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        
        captureSession.startRunning()

        setupButtons()
        setupMCService()
        setupLabels()
        
        DispatchQueue.main.async {
            self.promptTargetEyeSelection()
        }
    }
    
    deinit {
        serviceBrowser.stopBrowsingForPeers()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.frame
    }
    
    func promptTargetEyeSelection() {
        let alertController = UIAlertController(title: "검사 타겟", message: "어느 쪽 눈의 시력 검사를 진행하시나요?", preferredStyle: .alert)
        
        let option1Action = UIAlertAction(title: "왼쪽", style: .default) { _ in
            self.isTargetLeftEye = true
            self.isTestRunning = true
        }
        
        let option2Action = UIAlertAction(title: "오른쪽", style: .default) { _ in
            self.isTargetLeftEye = false
            self.isTestRunning = true
        }
        
        alertController.addAction(option1Action)
        alertController.addAction(option2Action)
        
        // Present the alert controller
        present(alertController, animated: true, completion: nil)
    }
    
    func setupMCService() {
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        serviceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)

        session.delegate = self
        serviceBrowser.delegate = self

        serviceBrowser.startBrowsingForPeers()
    }
    
    func setupLabels() {
        eyeDetectionLabel.frame = CGRect(x: 16, y: 30, width: 600, height: 60)
        eyeDetectionLabel.textColor = UIColor.black
        eyeDetectionLabel.font = UIFont.boldSystemFont(ofSize: 16)
        view.addSubview(eyeDetectionLabel)
    }
    
    func setupButtons() {
        for (_, number) in buttonTitles.enumerated() {
            // let button = UIButton(frame: CGRect(x: CGFloat(index) * buttonWidth, y: buttonYPosition, width: buttonWidth, height: buttonHeight))
            let button = UIButton(type: .system)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 24)
            button.setTitleColor(.white, for: .normal)
            button.setTitle(number, for: .normal)
            button.backgroundColor = #colorLiteral(red: 0, green: 0.7947641015, blue: 0.8564413786, alpha: 1)
            button.tag = Int(number)!
            button.addTarget(self, action: #selector(answerButtonTapped(_:)), for: .touchUpInside)
            buttons.append(button)
        }
        
        let stackView = UIStackView(arrangedSubviews: buttons)
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = 16
        
        view.addSubview(stackView)
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    func showAnswerEffect(imageName: String, labelText: String, soundName: String, keepAlive:Bool = false) {
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
        
        // Create the dialog view
        dialogView.backgroundColor = UIColor.white
        dialogView.layer.cornerRadius = 12
        dialogView.layer.shadowColor = UIColor.gray.cgColor
        dialogView.layer.shadowOffset = CGSize(width: 0, height: 2)
        dialogView.layer.shadowOpacity = 0.8
        dialogView.layer.shadowRadius = 4
        
        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        dialogView.addSubview(imageView)
        
        let label = UILabel()
        label.numberOfLines = 2
        label.text = labelText
        AudioController.playSound(soundName: soundName)
        
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
        
        self.dialogView.alpha = 1
        overlayView.alpha = 1
        
        if keepAlive {
            return
        }
        
        // Fade out the dialog after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 0.5, animations: {
                self.dialogView.alpha = 0
                overlayView.alpha = 0
            }) { _ in
                self.dialogView.removeFromSuperview()
                overlayView.removeFromSuperview()
                label.removeFromSuperview()
            }
        }
    }
    
    func endTest(result: Double) {
        let resultString = String(format: "%.1f", result)
        showAnswerEffect(imageName: "congraturation",
                         labelText: "수고하셨습니다! 검사결과는 \(resultString)입니다!",
                         soundName: "congraturation",
                         keepAlive: true)
    }
    
    func displayAnswerResult(isCorrect: Bool) {
        //TODO: Display the result whether the last answering was correct.
        log.info("The answering result: \(isCorrect)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.buttonsEnabled = true
        }

        if (isCorrect) {
            score += 10
            showAnswerEffect(imageName: "gift_box", labelText: "축하합니다~!! \(score)점 획득!", soundName: "ta-da")
        } else {
            showAnswerEffect(imageName: "fail", labelText: "아쉽게 틀렸어요. 다른 문양을 맞춰봐요!", soundName: "fail")
        }
    }

    func onConnectionStateChanged(peerID: MCPeerID, state: MCSessionState) {
        if (state == .connected) {
            log.info("Peer \(peerID) joined this sessions")
        } else if(state == .connecting) {
            log.info("Peer \(peerID) is connecting..")
        } else {
            log.info("Peer \(peerID) disconnected")
        }
        
        //TODO: Display current connection state.
    }
    
    @objc func answerButtonTapped(_ sender: UIButton) {
        if !buttonsEnabled {
            return
        }
        
        if !session.connectedPeers.isEmpty {
            do {
                try session.send(("Answer " + String(sender.tag)).data(using: .utf8)!, toPeers: session.connectedPeers, with: .reliable)
                buttonsEnabled = false
            } catch {
                log.error("Error for sending: \(String(describing: error))")
            }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
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
//        self.view.addSubview(self.leftImageView)
//        self.view.addSubview(self.rightImageView)
    }
    
    private func setupVideoDataOutput(showPreview: Bool = false) {
        if showPreview {
            self.previewLayer.videoGravity = .resizeAspectFill
            // self.view.layer.addSublayer(self.previewLayer)
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
        let currentTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        if currentTimestamp - lastDetection <= DETECTION_INTERVAL_MS {
            return
        }
        
        //TODO: 눈 detection만 framerate 줄이게 수정하기.
        for observation in observations {
            let faceRectConverted = self.previewLayer.layerRectConverted(fromMetadataOutputRect: observation.boundingBox)
            let faceRectanglePath = CGPath(rect: faceRectConverted, transform: nil)
            
            let faceLayer = CAShapeLayer()
            faceLayer.path = faceRectanglePath
            faceLayer.fillColor = UIColor.clear.cgColor
            faceLayer.strokeColor = UIColor.yellow.cgColor
            
            self.faceLayers.append(faceLayer)
            // self.view.layer.addSublayer(faceLayer)
            
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
                }
                
                if let rightPupil = landmarks.rightPupil {
                    self.handleLandmark(rightPupil, faceBoundingBox: faceRectConverted)
                }
            }
            
            checkIfEyeClosed(isLeftEyeDetected: isRightEyeDetected, isRightDetected: isLeftEyeDetected)
            DispatchQueue.main.async {
                // As the captured image is mirrored, left and right detection results should be reversly displayed.
                self.eyeDetectionLabel.text = "Left: \(isRightEyeDetected)   Right: \(isLeftEyeDetected)"
            }
        }
        
        lastDetection = currentTimestamp
    }
    
    private func checkIfEyeClosed(isLeftEyeDetected:Bool, isRightDetected: Bool, threshold: Double = 0.7) {
        let currentTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        if currentTimestamp - lastEyeDetection > EYE_DETECTION_INTERVAL_MS {
            let detectionResult = isTargetLeftEye ? isLeftEyeDetected : isRightDetected
            let isEyeProperlyCovered = detectionResult ? 0 : 1 // 0 point for unconvered, 1 point for covered
            let maxCount = EYE_AVERAGE_INTERVAL_MS / EYE_DETECTION_INTERVAL_MS
            
            eyeDetectionResultList.append(isEyeProperlyCovered)

            if eyeDetectionResultList.count > maxCount {
                eyeDetectionResultList.removeFirst()
            }
            
            if eyeDetectionResultList.count < maxCount {
                lastEyeDetection = currentTimestamp
                return
            }
            
            let scoreSum = eyeDetectionResultList.reduce(0, +)
            
            // 만약 한 번 경고 했으면 최소 3초 이후에 안내하기 위해서 리스트를 리셋하고, 마지막 디텍션 값을 2초 후로 옮기기.
            if Double(scoreSum) < Double(maxCount) * threshold {
                //TODO: Warn
                let soundName = isTargetLeftEye ? "left-eye-voice" : "right-eye-voice"
                AudioController.playSound(soundName: soundName)
                eyeDetectionResultList.removeAll()
                lastEyeDetection = currentTimestamp + 3000
                
                return
            }
            
            lastEyeDetection = currentTimestamp
        }
        
    }
    
    private func getFacialRect(image:CIImage, faceBoundingBox: CGRect, isLeft:Bool) -> CGRect {
        let scale = UIScreen.main.scale + 2
        let scaleX = image.extent.size.width / UIScreen.main.bounds.width
        let scaleY = image.extent.size.height / UIScreen.main.bounds.height
        let offsetScaleFactor = 0.1
        let xOffsetScaleFactor = 0.1
        let sizeScaleFactor = 0.2
        
        if isLeft {
            return CGRect(x: (UIScreen.main.bounds.width - faceBoundingBox.origin.x  - faceBoundingBox.size.width + faceBoundingBox.size.width*xOffsetScaleFactor) * scaleX,
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
