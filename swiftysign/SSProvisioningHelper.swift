//
//  SSProvisioningHelper.swift
//  swiftysign
//
//  Created by Michael Specht on 5/21/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

protocol SSProvisioningHelperDelegate: class {
    func updateProgress(animate: Bool, message: String)
    func provisioningCompleted()
}

class SSProvisioningHelper: NSObject {
    
    private var provisioningTask: Process?
    private weak var delegate: SSProvisioningHelperDelegate?
    
    init(delegate: SSProvisioningHelperDelegate) {
        super.init()
        self.delegate = delegate
    }
    
    func doProvisioning(provisioningFilePath: String) {
        
        let embeddedPath = SSResigner.appPath.appendingPathComponent("embedded.mobileprovision")
        if FileManager.default.fileExists(atPath: embeddedPath) {
            print("Found embedded.mobileprovision, deleting...")
            try! FileManager.default.removeItem(atPath: embeddedPath)
        }
        
        let targetPath = SSResigner.appPath.appendingPathComponent("embedded.mobileprovision")
        provisioningTask = Process()
        provisioningTask!.launchPath = "/bin/cp"
        provisioningTask!.arguments = [provisioningFilePath, targetPath]
        
        provisioningTask!.launch()
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkProvisioning(timer:)), userInfo: nil, repeats: true)
    }
    
    @objc private func checkProvisioning(timer: Timer) {
        guard provisioningTask != nil else {
            return
        }
        
        if !provisioningTask!.isRunning {
            timer.invalidate()
            provisioningTask = nil
            
            let embeddedPath = SSResigner.appPath.appendingPathComponent("embedded.mobileprovision")
            if FileManager.default.fileExists(atPath: embeddedPath) {
                var identifierOK = false
                var identifierInProvisioning = ""
                let embeddedProvisioning = try! NSString(contentsOfFile: SSResigner.appPath.appendingPathComponent("embedded.mobileprovision"), encoding: String.Encoding.ascii.rawValue)
                let embeddedProvisioningLines = embeddedProvisioning.components(separatedBy: CharacterSet.newlines)
                
                for i in 0...embeddedProvisioningLines.count {
                    let line = embeddedProvisioningLines[i]
                    if line.contains("application-identifier") {
                        let nextLine = embeddedProvisioningLines[i+1]
                        let matches = matchesForRegexInText("<string>.*<\\/string>", text: nextLine)
                        
                        let fullIdentifier = matches.first!.replacingOccurrences(of: "<string>", with: "").replacingOccurrences(of: "</string>", with: "")
                        let identifierComponents = fullIdentifier.components(separatedBy: ".")
                        
                        if identifierComponents.last! == "*" {
                            identifierOK = true
                        }
                        
                        for i in 1..<identifierComponents.count {
                            identifierInProvisioning.append(identifierComponents[i])
                            if i < identifierComponents.count - 1 {
                                identifierInProvisioning.append(".")
                            }
                        }
                        break
                    }
                }
                
                print("Mobile provision identifier \(identifierInProvisioning)")
                let infoPlist = NSDictionary(contentsOfFile: SSResigner.appPath.appendingPathComponent(kInfoPlistFilename))!
                if identifierInProvisioning == infoPlist[kKeyBundleIDPlistApp] as! String{
                    print("Identifiers match")
                    identifierOK = true
                }
                
                if identifierOK {
                    print("Provisioning Complete")
                    delegate?.updateProgress(animate: true, message: NSLocalizedString("Provisioning complete", comment: ""))
                    delegate?.provisioningCompleted()
                } else {
                    print("Provisioning failed -- bad identifier")
                    delegate?.updateProgress(animate: false, message: NSLocalizedString("Provisioning Failed: The bundle ids do not match", comment: ""))
                }
            } else {
                print("Provisioning failed")
                delegate?.updateProgress(animate: false, message: NSLocalizedString("Provisioning Failed", comment: ""))
            }
        }
    }
}
