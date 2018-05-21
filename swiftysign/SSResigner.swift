//
//  SSResigner.swift
//  swiftysign
//
//  Created by Michael Specht on 5/21/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

protocol SSResignerDelegate: class {
    func updateProgress(animate: Bool, message: String)
}

class SSResigner: NSObject, SSEntitlementUpdaterDelegate, SSCodeSignerDelegate, SSZipperDelegate, SSProvisioningHelperDelegate {
    
    var archiveFilePath = "" as NSString
    var entitlementPath = "" as NSString
    var provisioningFilePath = "" as NSString
    var certificateName = "" as NSString
    var newBundleId = ""
    var newAppName = ""
    var changeBundleId = false
    
    weak var delegate: SSResignerDelegate?
    
    let certificateRetriver = SSCertificateRetriever()
    var entitlementsUpdater: SSEntitlementUpdater!
    let provisioner = SSProvisioningHelper()
    let zipper = SSZipper()
    let codesigner = SSCodeSigner()
    
    static var workingPath: NSString!
    
    private static var _appPath = "" as NSString
    static var appPath: NSString {
        if _appPath.length > 0 {
            return _appPath
        }
        for case let file as NSString in directoryContents {
            if file.pathExtension.lowercased() == "app" {
                _appPath = (workingPath.appendingPathComponent(kPayloadDirName) as NSString).appendingPathComponent(file as String) as NSString
                return _appPath
            }
        }
        return (workingPath.appendingPathComponent(kPayloadDirName) as NSString)
    }
    
    var entitlementsFilePath = ""
    
    var certificates: [SSCertificate] {
        return certificateRetriver.certificates
    }
    
    func setup(viewDelegate: ViewController?) {
        
        delegate = viewDelegate
        zipper.delegate = self
        provisioner.delegate = self
        codesigner.delegate = self
        certificateRetriver.delegate = viewDelegate
        certificateRetriver.getCertificates()
        
        let defaults = UserDefaults.standard
        if defaults.value(forKey: "ENTITLEMENT_PATH") != nil {
            entitlementsFilePath = defaults.string(forKey: "ENTITLEMENT_PATH")!
        }
        if defaults.value(forKey: "MOBILEPROVISION_PATH") != nil {
            provisioningFilePath = defaults.string(forKey: "MOBILEPROVISION_PATH")! as NSString
        }
        
        checkForRequiredUtilities()
    }
    
    
    
    func resign(archivePath: String, entitlementPath: String, provisioningFilePath: String, certificateName: String, newBundleId: String, newAppName: String) {
        
        updateSavedPaths()
        
        archiveFilePath = archivePath as NSString
        SSResigner.workingPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("swiftysign") as NSString
        
        entitlementsUpdater = SSEntitlementUpdater(path: SSResigner.workingPath as String, delegate: self)
        
        self.newAppName = newAppName
        self.newBundleId = newBundleId
        self.certificateName = certificateName as NSString
        self.provisioningFilePath = provisioningFilePath as NSString
        
        if archiveFilePath.pathExtension.lowercased() == "ipa" || archiveFilePath.pathExtension.lowercased() == "xcarchive" {
            setupFileDirectories()
            
            if archiveFilePath.pathExtension.lowercased() == "ipa" {
                
                
            } else if archiveFilePath.pathExtension.lowercased() == "xcarchive" {
                let payloadPath = SSResigner.workingPath.appendingPathComponent(kPayloadDirName)
                print("Setting up \(kPayloadDirName) path in \(payloadPath)")
                
                delegate?.updateProgress(animate: true, message: NSLocalizedString("Setting up \(kPayloadDirName) path", comment: ""))
                
                try! FileManager.default.createDirectory(atPath: payloadPath, withIntermediateDirectories: true, attributes: nil)
                
                print("Retrieving \(kInfoPlistFilename)")
                delegate?.updateProgress(animate: true, message: NSLocalizedString("Retreiving \(kInfoPlistFilename)", comment: ""))
                
                let infoPlistPath = archiveFilePath.appendingPathComponent(kInfoPlistFilename)
                let infoPlistDictionary = NSDictionary(contentsOfFile: infoPlistPath)
                
                if infoPlistDictionary != nil {
                    var applicationPath: String?
                    
                    let applicationPropertiesDict = infoPlistDictionary!.object(forKey: kKeyInfoPlistApplicationProperties)
                    
                    if applicationPropertiesDict != nil {
                        applicationPath = (applicationPropertiesDict as! NSDictionary).object(forKey: kKeyInfoPlistApplicationPath) as? String
                    }
                    
                    if applicationPath != nil {
                        applicationPath = (archiveFilePath.appendingPathComponent(kProductsDirName) as NSString).appendingPathComponent(applicationPath!)
                        
                        delegate?.updateProgress(animate: true, message: NSLocalizedString("Copying .xcarchive app to \(kPayloadDirName) path", comment: ""))
                        
                        copyTask = Process()
                        copyTask!.launchPath = "/bin/cp"
                        copyTask!.arguments = ["-r", applicationPath!, payloadPath]
                        
                        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkCopy(timer:)), userInfo: nil, repeats: true)
                        copyTask!.launch()
                    } else {
                        print("Unable to parse \(kInfoPlistFilename)")
                    }
                } else {
                    print("Error opening plist...")
                }
            }
        } else {
            print("only IPA and XCArchive supported")
        }
    }
    
    private func checkForRequiredUtilities() {
        if !FileManager.default.fileExists(atPath: "/usr/bin/zip") {
            print("/usr/bin/zip required")
            exit(0)
        }
        if !FileManager.default.fileExists(atPath: "/usr/bin/unzip") {
            print("/usr/bin/unzip required")
            exit(0)
        }
        if !FileManager.default.fileExists(atPath: "/usr/bin/codesign") {
            print("/usr/bin/codesign required")
            exit(0)
        }
    }
    
    private func updateSavedPaths() {
        let defaults = UserDefaults.standard
        defaults.set(certificateRetriver.indexOfCertificate(certificateName: certificateName as String), forKey: "CERT_INDEX")
        defaults.set(entitlementPath, forKey: "ENTITLEMENT_PATH")
        defaults.set(provisioningFilePath, forKey: "MOBILEPROVISION_PATH")
        defaults.set(newBundleId, forKey: kKeyPrefsBundleIDChange)
        defaults.synchronize()
    }
    
    var copyTask: Process?
    @objc private func checkCopy(timer: Timer) {
        guard copyTask != nil else {
            timer.invalidate()
            return
        }
        
        if !copyTask!.isRunning {
            timer.invalidate()
            copyTask = nil
            
            print("Copy done")
            delegate?.updateProgress(animate: true, message: NSLocalizedString("xcarchive copied", comment: ""))
            
            if newBundleId.length() > 0 {
                changeAppBundleID()
                changeMetaDataBundleID()
            }
            
            if newAppName.length() > 0 {
                changeDisplayName()
            }
            
            if provisioningFilePath.length == 0 {
                codesigner.codeSignApp(resigner: self)
            } else {
                provisioner.doProvisioning(provisioningFilePath: provisioningFilePath as String)
            }
        }
    }
    
    private func changeAppBundleID() {
        
        let infoPlistPath = SSResigner.appPath.appending("/\(kInfoPlistFilename)")
        
        updatePlist(filePath: infoPlistPath, key: kFileSharingEnabledName, value: true)
        updatePlist(filePath: infoPlistPath, key: kKeyBundleIDPlistApp, value: newBundleId)
    }
    
    private func updatePlist(filePath: String, key: String, value: Any) {
        if FileManager.default.fileExists(atPath: filePath) {
            let plist = NSMutableDictionary(contentsOfFile: filePath)!
            plist.setObject(value, forKey: key as NSCopying)
            
            try! FileManager.default.removeItem(atPath: filePath)
            
            let xmlData = try! PropertyListSerialization.data(fromPropertyList: plist, format: PropertyListSerialization.PropertyListFormat.xml, options: 0)
            let success = FileManager.default.createFile(atPath: filePath, contents: xmlData, attributes: nil)
            print("\(filePath) updated \(success)")
        }
    }
    
    private func changeMetaDataBundleID() {
        
        var infoPlistPath = ""
        
        for file in SSResigner.directoryContents {
            if (file as NSString).pathExtension.lowercased() == "plist" {
                infoPlistPath = SSResigner.workingPath.appendingPathComponent(file)
                break
            }
        }
        
        updatePlist(filePath: infoPlistPath, key: kKeyBundleIDPlistiTunesArtwork, value: newBundleId)
    }
    
    private func changeDisplayName() {
        
        let appFolder = SSResigner.workingPath.appendingPathComponent(kPayloadDirName)
        let dirEnumerator = FileManager.default.enumerator(atPath: appFolder)!
        
        var stringsFiles = [String]()
        
        for case let file as NSString in dirEnumerator {
            if file.hasSuffix(".lproj/InfoPlist.strings") {
                stringsFiles.append("\(appFolder)/\(file)")
            }
        }
        
        for filePath in stringsFiles {
            if FileManager.default.fileExists(atPath: filePath) {
                updatePlist(filePath: filePath, key: kKeyBundleDisplayNameApp, value: newAppName)
            }
        }
        
        for case let file as NSString in SSResigner.directoryContents {
            if file.pathExtension.lowercased() == "app" {
                let infoPlistPath = "\(SSResigner.workingPath!)/\(kPayloadDirName)/\(file)/\(kInfoPlistFilename)"
                updatePlist(filePath: infoPlistPath, key: kKeyBundleDisplayNameApp, value: newAppName)
                break
            }
        }
        
        for case let file as NSString in SSResigner.directoryContents {
            if file.pathExtension.lowercased() == "plist" {
                let infoPlistPath = SSResigner.workingPath.appendingPathComponent(file as String)
                updatePlist(filePath: infoPlistPath, key: kKeyBundleDisplayNamePlistiTunesArtwork, value: newAppName)
                break
            }
        }
    }
    
    static var directoryContents: [String] {
        get {
            return try! FileManager.default.contentsOfDirectory(atPath: workingPath.appendingPathComponent(kPayloadDirName))
        }
    }
    
    private func setupFileDirectories() {
        do {
            try FileManager.default.removeItem(atPath: String(SSResigner.workingPath))
        } catch {
            print("file not removed")
        }
        
        try! FileManager.default.createDirectory(atPath: String(SSResigner.workingPath), withIntermediateDirectories: true, attributes: nil)
    }
    
    
    func readyForCodeSign(_ entitlementFilePath: String?) {
        if entitlementFilePath != nil {
            entitlementPath = entitlementFilePath! as NSString
        }
        codesigner.codeSignApp(resigner: self)
    }
    
    func updateProgress(animate: Bool, message: String) {
        delegate?.updateProgress(animate: animate, message: message)
    }
    
    func signingComplete() {
        zipper.doZip(archivePath: archiveFilePath)
    }
    
    func provisioningCompleted() {
        entitlementsUpdater.fixEntitlements(premadeEntitlementsFilePath: entitlementsFilePath, provisioningFilePath: provisioningFilePath as String)
    }
}
