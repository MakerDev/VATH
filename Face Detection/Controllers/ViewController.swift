//
//  ViewController.swift
//  Face Detection
//
//  Created by Tomasz Baranowicz on 15/07/2020.
//  Copyright © 2020 Tomasz Baranowicz. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        checkCameraPermission()
    }

    func checkCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: {
            (granted: Bool) in
            if granted {
                print("카메라 권한이 허용됨")
            } else {
                print("카메라 권한이 허용되지 않음.")
            }
        })
    }
}

