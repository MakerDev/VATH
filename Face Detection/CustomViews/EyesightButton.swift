//
//  EyesightButton.swift
//  Face Detection
//
//  Created by 신유진 on 2023/08/02.
//  Copyright © 2023 Tomasz Baranowicz. All rights reserved.
//
import UIKit

class EyesightButton: UIButton {
    var buttonNumber: Int = 3 {
        didSet {
            updateButtonImages()
        }
    }
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupButton()
    }
    
    // MARK: - Setup
    private func setupButton() {
        setTitleColor(.white, for: .normal)
        layer.cornerRadius = 8.0
        titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        
        updateButtonImages()
    }
    
    private func updateButtonImages() {
        setBackgroundImage(UIImage(named: "button_idle\(buttonNumber)"), for: .normal)
        setBackgroundImage(UIImage(named: "button_pressed\(buttonNumber)"), for: .highlighted)
            
        imageView?.contentMode = .scaleAspectFit
    }
}
