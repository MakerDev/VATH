//
//  LiveFeedViewController+Extensions.swift
//  Face Detection
//
//  Created by 신유진 on 2023/05/22.
//  Copyright © 2023 Tomasz Baranowicz. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import os

extension LiveFeedViewController: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        log.info("ServiceBrowser found peer: \(peerID)")
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 5)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        log.info("ServiceBrowser lost peer: \(peerID)")
    }
}

extension LiveFeedViewController: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        self.onConnectionStateChanged(peerID: peerID, state: state)
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let receivedString = String(data: data, encoding: .utf8) {
            log.info("didReceive \(receivedString)")
            
            if receivedString.lowercased().starts(with: "end") {
                let testResult = Double(receivedString.split(separator: " ")[1])
                
            }
            
            DispatchQueue.main.async {
                self.displayAnswerResult(isCorrect: Bool(receivedString.lowercased())!)
            }
        } else {
            log.info("didReceive invalid value \(data.count) bytes")
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        
    }
}
