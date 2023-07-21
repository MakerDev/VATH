//
//  AudioController.swift
//  Face Detection
//
//  Created by 신유진 on 2023/07/21.
//  Copyright © 2023 Tomasz Baranowicz. All rights reserved.
//

import Foundation
import AVFoundation

class AudioController {
    private static var audioPlayer: AVAudioPlayer?
    public static func playSound(soundName: String, extensionType:String = "mp3") {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: extensionType) else {
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            audioPlayer?.play()
        } catch let error {
            print(error.localizedDescription)
        }
    }
}
