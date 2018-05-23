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
        let provisioningTask = Process()
        provisioningTask.launchPath = "/bin/cp"
        provisioningTask.arguments = [provisioningFilePath, targetPath]
        
        provisioningTask.launch()
        provisioningTask.waitUntilExit()
        
        verifyProvisioningSucceeded()
    }
    
    private func verifyProvisioningSucceeded() {
        let embeddedPath = SSResigner.appPath.appendingPathComponent("embedded.mobileprovision")
        if FileManager.default.fileExists(atPath: embeddedPath) {
            if bundleIdIsValid() {
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
    
    private func bundleIdIsValid() -> Bool {
        var identifierIsValid = false
        let identifierComponents = embeddedIdentifierComponents()
        
        if isWildCard(identifierComponents) {
            identifierIsValid = true
        }
        
        let identifierInProvisioning = getBundleIdFromComponents(identifierComponents)
        
        print("Mobile provision identifier \(identifierInProvisioning)")
        let infoPlist = NSDictionary(contentsOfFile: SSResigner.appPath.appendingPathComponent(kInfoPlistFilename))!
        if identifierInProvisioning == infoPlist[kKeyBundleIDPlistApp] as! String{
            print("Identifiers match")
            identifierIsValid = true
        }
        
        return identifierIsValid
    }
    
    private func getBundleIdFromComponents(_ components: [String]) -> String {
        var identifierComponents = components
        identifierComponents.removeFirst()
        return identifierComponents.joined(separator: ".")
    }
    
    private func isWildCard(_ components: [String]) -> Bool {
        guard components.count > 0 else {
            return false
        }
        
        return components.last! == "*"
    }
    
    private func embeddedIdentifierComponents() -> [String] {
        let embeddedProvisioning = try! NSString(contentsOfFile: SSResigner.appPath.appendingPathComponent("embedded.mobileprovision"), encoding: String.Encoding.ascii.rawValue)
        let embeddedProvisioningLines = embeddedProvisioning.components(separatedBy: CharacterSet.newlines)
        
        for i in 0...embeddedProvisioningLines.count {
            let line = embeddedProvisioningLines[i]
            if line.contains("application-identifier") {
                let nextLine = embeddedProvisioningLines[i+1]
                let matches = matchesForRegexInText("<string>.*<\\/string>", text: nextLine)
                
                let fullIdentifier = matches.first!.replacingOccurrences(of: "<string>", with: "").replacingOccurrences(of: "</string>", with: "")
                let identifierComponents = fullIdentifier.components(separatedBy: ".")
                
                return identifierComponents
            }
        }
        
        return []
    }
}
