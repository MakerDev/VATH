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
        
        setBackgroundImage(UIImage(named: "button_idle"), for: .normal)
        setBackgroundImage(UIImage(named: "button_pressed"), for: .highlighted)
        
        imageView?.contentMode = .center
    }
    
    private func updateButtonImages() {
        let scale = 0.4
        if let numberImage = UIImage(named: "img\(buttonNumber)") {
            let scaledImage = numberImage.scaled(by: scale)
            setImage(scaledImage, for: .normal)
            setImage(scaledImage, for: .highlighted)
        }
    }
}

extension UIImage {
    func scaled(by scale: CGFloat) -> UIImage? {
        let newWidth = size.width * scale
        let newHeight = size.height * scale
        let newSize = CGSize(width: newWidth, height: newHeight)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}
