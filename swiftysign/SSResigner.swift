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

class SSResigner: NSObject, SSEntitlementUpdaterDelegate, SSCodeSignerDelegate, SSZipperDelegate, SSProvisioningHelperDelegate, SSAppCopierDelegate {
    
    var settings = SSResignSettings()
    weak var delegate: SSResignerDelegate?
    
    var certificateRetriver: SSCertificateRetriever!
    var entitlementsUpdater: SSEntitlementUpdater!
    var codesigner: SSCodeSigner!
    
    static var workingPath: NSString!
    private static var _appPath = "" as NSString
    
    init(delegate: SSResignerDelegate?, certificateDelegate: SSCertificateRetrieverDelegate?) {
        super.init()
        
        self.delegate = delegate
        
        codesigner = SSCodeSigner(delegate: self)

        certificateRetriver = SSCertificateRetriever(delegate: certificateDelegate)
        certificateRetriver.getCertificates()
        
        checkForRequiredUtilities()
    }
    
    func resign(resignerSettings: SSResignSettings) {
        
        updateSavedPaths()
        
        self.settings = resignerSettings
        SSResigner.workingPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("swiftysign") as NSString
        
        entitlementsUpdater = SSEntitlementUpdater(path: SSResigner.workingPath as String, delegate: self)
        
        if isArchive(path: settings.archiveFilePath)  {
            setupFileDirectories()
            
            let copier = SSAppCopier(delegate: self)
            copier.copyArchive(settings: settings)
        } else {
            delegate?.updateProgress(animate: false, message: NSLocalizedString("Only XCArchive files are supported", comment: ""))
        }
    }
    
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
    
    var certificates: [SSCertificate] {
        return certificateRetriver.certificates
    }
    
    
    private func isArchive(path: NSString) -> Bool {
        return path.pathExtension.lowercased() == "xcarchive"
    }
    
    private func isValidExtension(path: NSString) -> Bool {
        return path.pathExtension.lowercased() == "ipa" || path.pathExtension.lowercased() == "xcarchive"
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
        defaults.set(certificateRetriver.indexOfCertificate(certificateName: settings.certificateName as String), forKey: "CERT_INDEX")
        defaults.set(settings.entitlementPath, forKey: "ENTITLEMENT_PATH")
        defaults.set(settings.provisioningFilePath, forKey: "MOBILEPROVISION_PATH")
        defaults.set(settings.newBundleId, forKey: kKeyPrefsBundleIDChange)
        defaults.synchronize()
    }
    
    static func defaultEntitlementPath() -> String {
        if UserDefaults.standard.value(forKey: "ENTITLEMENT_PATH") != nil {
            return UserDefaults.standard.string(forKey: "ENTITLEMENT_PATH")!
        }
        return ""
    }
    
    static func defaultProvisioningPath() -> String {
        if UserDefaults.standard.value(forKey: "MOBILEPROVISION_PATH") != nil {
            return UserDefaults.standard.string(forKey: "MOBILEPROVISION_PATH")!
        }
        return ""
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
            settings.entitlementPath = entitlementFilePath! as NSString
        }
        codesigner.codeSignApp(settings: settings)
    }
    
    func updateProgress(animate: Bool, message: String) {
        delegate?.updateProgress(animate: animate, message: message)
    }
    
    func signingComplete() {
        let zipper = SSZipper(delegate: self)
        zipper.doZip(archivePath: settings.archiveFilePath)
    }
    
    func provisioningCompleted() {
        entitlementsUpdater.fixEntitlements(premadeEntitlementsFilePath: settings.entitlementPath as String,
                                            provisioningFilePath: settings.provisioningFilePath as String)
    }
    
    func doneCopying() {
        if settings.provisioningFilePath.length == 0 {
            codesigner.codeSignApp(settings: settings)
        } else {
            let provisioner = SSProvisioningHelper(delegate: self)
            provisioner.doProvisioning(provisioningFilePath: settings.provisioningFilePath as String)
        }
    }
}
