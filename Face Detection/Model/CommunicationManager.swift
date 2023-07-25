//
//  CommunicationManager.swift
//  Face Detection
//
//  Created by 신유진 on 2023/05/14.
//  Copyright © 2023 Tomasz Baranowicz. All rights reserved.
//

import Foundation
import Network

class CommunicationManager {
    private var connection: NWConnection?
    
    var onDataReceived: ((String) -> Void)?
    
    init(host: String, port: NWEndpoint.Port=9099) {
        let params = NWParameters.tcp
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        connection = NWConnection(to: endpoint, using: params)
        
        connection?.stateUpdateHandler = { newState in
            if newState == .ready {
                // Ready to send/receive data
                self.receiveData()
            } else if newState == .cancelled {
                print("Connection cancelled")
            }
        }
        
        connection?.start(queue: .main)
    }
    
    deinit {
        // Inform the connection is closing.
        sendData("close")
    }
    
    func sendData(_ message: String) {
        let message = "\(message)\n"
        if let data = message.data(using: .utf8) {
            connection?.send(content: data, completion: .idempotent)
        }
    }
    
    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { (data, _, isComplete, error) in
            if let data = data {
                // process received data
                if let str = String(data: data, encoding: .utf8) {
                    print("Received data: \(str)")
                    let message = str.trimmingCharacters(in: .newlines)
                    self.onDataReceived?(message)
                }
            }
            
            if let error = error {
                // handle errors
                print("Error: \(error)")
            }
            
            if isComplete {
                print("Message received completely.")
            } else {
                // if the message is not complete, call receiveData again to receive the rest of the data
                self.receiveData()
            }
            
        }
    }
}
