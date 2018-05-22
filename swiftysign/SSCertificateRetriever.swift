//
//  SSCertificateRetriever.swift
//  swiftysign
//
//  Created by Michael Specht on 5/21/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

struct SSCertificate {
    var name = ""
    var id = ""
}

protocol SSCertificateRetrieverDelegate: class {
    func certificatesUpdated()
}

class SSCertificateRetriever: NSObject {
    
    var certificates = [SSCertificate]()
    private weak var delegate: SSCertificateRetrieverDelegate?
    private var getCertificateTask: Process?
    
    init(delegate: SSCertificateRetrieverDelegate?) {
        super.init()
        self.delegate = delegate
    }
    
    func getCertificates() {
        
        getCertificateTask = Process()
        let pipe = Pipe()
        
        getCertificateTask!.launchPath = "/usr/bin/security"
        getCertificateTask!.arguments = ["find-identity", "-v", "-p", "codesigning"]
        getCertificateTask!.standardOutput = pipe
        getCertificateTask!.standardError = pipe
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkCerts(timer:)), userInfo: nil, repeats: true)
        
        getCertificateTask!.launch()
        
        let handle = pipe.fileHandleForReading
        Thread.detachNewThreadSelector(#selector(watchCertificates(handle:)), toTarget: self, with: handle)
    }
    
    @objc private func checkCerts(timer: Timer) {
        guard getCertificateTask != nil else {
            return
        }
        
        if !getCertificateTask!.isRunning {
            timer.invalidate()
            getCertificateTask = nil
            
            if certificates.count > 0 {
                print("Retrieved the certificates...")
                if UserDefaults.standard.value(forKey: "CERT_INDEX") != nil {
                    let selectedIndex = UserDefaults.standard.integer(forKey: "CERT_INDEX")
                    if selectedIndex != -1 {
                        delegate?.certificatesUpdated()
                    }
                }
            } else {
                print("No certificates")
            }
        }
        
    }
    
    func indexOfCertificate(certificateName: String) -> Int {
        return certificates.index(where: { (cert) -> Bool in
            return cert.name == certificateName
        }) ?? -1
    }
    
    @objc private func watchCertificates(handle: FileHandle) {
        
        let data = handle.readDataToEndOfFile()
        let securityResult = NSString(data: data, encoding: String.Encoding.utf8.rawValue)
        
        if securityResult == nil || securityResult!.length == 0 {
            return
        }
        
        print(securityResult!)
        let rawResult = matchesForRegexInText("\\) (.[A-Z,0-9]*).*\n", text: securityResult! as String)
        
        OperationQueue.main.addOperation {
            self.certificates.removeAll()
            
            for str in rawResult {
                let fullCertInfo = str.replacingOccurrences(of: ") ", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\"", with: "")
                let certificateId = fullCertInfo[..<fullCertInfo.index(fullCertInfo.startIndex, offsetBy: 40)]
                let certificateName = fullCertInfo[fullCertInfo.index(fullCertInfo.startIndex, offsetBy: 41)...]
                let newCert = SSCertificate(name: String(certificateName), id: String(certificateId))
                self.certificates.append(newCert)
            }
            
            self.delegate?.certificatesUpdated()
        }
    }
    
}
