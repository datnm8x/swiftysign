//
//  SSCodeSigner.swift
//  swiftysign
//
//  Created by Michael Specht on 5/21/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

protocol SSCodeSignerDelegate: class {
    func updateProgress(animate: Bool, message: String)
    func signingComplete()
}

class SSCodeSigner: NSObject {
    
    private var entitlementsFilePath = ""
    private var certificateName: String!
    private var newBundleId: String!
    private var additionalResourcesToSign = [String]()
    private var additionalToSign = false
    private var verificationResult = ""
    
    private weak var delegate: SSCodeSignerDelegate?
    
    init(delegate: SSCodeSignerDelegate) {
        super.init()
        self.delegate = delegate
    }
    
    func codeSignApp(settings: SSResignSettings) {
        
        self.entitlementsFilePath = settings.entitlementPath as String
        self.certificateName = settings.certificateName as String!
        self.newBundleId = settings.newBundleId
        
        additionalToSign = false
        additionalResourcesToSign.removeAll()
        
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Codesigning \(SSResigner.appPath.lastPathComponent)", comment: ""))
        updateFrameworksToSign()
        
        if additionalToSign {
            self.signFile(filePath: additionalResourcesToSign.popLast()! as NSString)
        } else {
            self.signFile(filePath: SSResigner.appPath)
        }
    }
    
    private func updateFrameworksToSign() {
        let dir = SSResigner.appPath
        let dirEnumerator = FileManager.default.enumerator(atPath: dir as String)!
        
        for case let file as NSString in dirEnumerator {
            if file.lastPathComponent == kInfoPlistFilename
                && file.deletingLastPathComponent.trimmingCharacters(in: CharacterSet.whitespaces).length() > 0 {
                let infoPlistPath = SSResigner.appPath.appendingPathComponent(file as String)
                let infoDict = NSDictionary.init(contentsOfFile: infoPlistPath)
                if infoDict?.object(forKey: "CFBundleExecutable") != nil {
                    additionalToSign = true
                    let dirToSign = (infoPlistPath as NSString).deletingLastPathComponent
                    print("Found \(dirToSign)")
                    additionalResourcesToSign.append(dirToSign)
                    
                    let _ = self.changeExtensionBundleIdPrefix(filePath: infoPlistPath,
                                                               bundleIdKey: kKeyBundleIDPlistApp,
                                                               newBundleIdPrefix: newBundleId)
                }
            }
        }
    }
    
    @available(*, deprecated)
    private func determineFrameworksToSign() {
        let frameworksDirPath = SSResigner.appPath.appendingPathComponent(kFrameworksDirName)
        print("Checking for frameworks and plugins to sign")
        
        if FileManager.default.fileExists(atPath: frameworksDirPath) {
            print("Found \(frameworksDirPath)")
            additionalToSign = true
            let frameworkContents = try! FileManager.default.contentsOfDirectory(atPath: frameworksDirPath)
            for frameworkFile in frameworkContents {
                let ext = (frameworkFile as NSString).pathExtension.lowercased()
                if ext == "framework" || ext == "dylib" {
                    let frameworkPath = (frameworksDirPath as NSString).appendingPathComponent(frameworkFile)
                    print("Found framework: \(frameworkPath)")
                    additionalResourcesToSign.append(frameworkPath)
                }
            }
        }
    }
    
    fileprivate func updateWatchKitExtensionWithNewBundleId(_ plist: NSMutableDictionary!, _ newBundleIdPrefix: String) {
        if plist["NSExtension"] != nil && (plist["NSExtension"] as! NSDictionary)["NSExtensionAttributes"] != nil {
            let extensionAttributes = ((plist["NSExtension"] as! NSDictionary)["NSExtensionAttributes"] as! NSDictionary).mutableCopy() as! NSMutableDictionary
            let wkAppBundleIdentifier = extensionAttributes["WKAppBundleIdentifier"] as! NSString
            let newWkAppBundleIdentifier = "\(newBundleIdPrefix).\(wkAppBundleIdentifier.components(separatedBy: ".").last!)"
            
            print(
                """
                ==============
                old: \(wkAppBundleIdentifier as String)
                new: \(newWkAppBundleIdentifier)
                """
            )
            
            extensionAttributes["WKAppBundleIdentifier"] = newWkAppBundleIdentifier
            
            let extensionDictionary = (plist["NSExtension"] as! NSDictionary).mutableCopy() as! NSMutableDictionary
            extensionDictionary["NSExtensionAttributes"] = extensionAttributes
            
            plist.setObject(extensionDictionary, forKey: "NSExtension" as NSCopying)
        }
        
        if plist.object(forKey: "WKCompanionAppBundleIdentifier") != nil {
            plist.setObject(newBundleIdPrefix, forKey: "WKCompanionAppBundleIdentifier" as NSCopying)
        }
    }
    
    private func changeExtensionBundleIdPrefix(filePath: String, bundleIdKey: String, newBundleIdPrefix: String) -> Bool {
        var plist: NSMutableDictionary!
        
        if FileManager.default.fileExists(atPath: filePath) {
            plist = NSMutableDictionary.init(contentsOfFile: filePath)
            let oldBundleId = plist.object(forKey: bundleIdKey)
            let newBundleId = "\(newBundleIdPrefix).\((oldBundleId as! NSString).components(separatedBy: ".").last!)"
            
            print(
                """
                ==============
                old: \(oldBundleId as! String)
                new: \(newBundleId)
                """
            )
            
            plist.setObject(newBundleId, forKey: bundleIdKey as NSCopying)
            
            updateWatchKitExtensionWithNewBundleId(plist, newBundleIdPrefix)
            
            let xmlData = try! PropertyListSerialization.data(fromPropertyList: plist, format: PropertyListSerialization.PropertyListFormat.xml, options: 0)
            FileManager.default.createFile(atPath: filePath, contents: xmlData, attributes: nil)
            return true
        }
        
        return false
    }
    
    private func signFile(filePath: NSString) {
        print("Codesigning \(filePath)")
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Codesigning \(filePath)", comment: ""))
        
        removeBundleResourceSpecificationFromPlist(filePath)
        
        let arguments = getSigningArguments(filePath: filePath)
        print("Signing arguments:\n \(arguments)")
        
        let codesignTask = Process()
        let pipe = Pipe()
        
        codesignTask.launchPath = "/usr/bin/codesign"
        codesignTask.arguments = arguments
        codesignTask.standardOutput = pipe
        codesignTask.standardError = pipe
        
        codesignTask.launch()
        codesignTask.waitUntilExit()
        let codesignResult = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        print("Result of codesign: \(codesignResult)")
        
        checkCodeSigning()
    }
    
    private func checkCodeSigning() {
        if additionalResourcesToSign.count > 0 {
            signFile(filePath: additionalResourcesToSign.popLast()! as NSString)
        } else if additionalToSign {
            additionalToSign = false
            signFile(filePath: SSResigner.appPath)
        } else {
            print("Codesigning done")
            delegate?.updateProgress(animate: true, message: NSLocalizedString("Codesigning completed", comment: ""))
            verifySignature()
        }
    }
    
    private func verifySignature() {
        verificationResult = ""
        let verifyTask = Process()
        let pipe = Pipe()
        
        verifyTask.launchPath = "/usr/bin/codesign"
        verifyTask.arguments = ["-v", SSResigner.appPath as String]
        verifyTask.standardOutput = pipe
        verifyTask.standardError = pipe
        
        print("Verifying \(SSResigner.appPath)")
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Verifying \(SSResigner.appPath.lastPathComponent)", comment: ""))
        
        verifyTask.launch()
        verifyTask.waitUntilExit()
        verificationResult = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        print("Result of verify: \(verificationResult)")
        
        checkVerificationProcess()
    }
    
    
    private func getSigningArguments(filePath: NSString) -> [String] {
        var arguments = [String]()
        arguments.append("-fs")
        arguments.append(certificateName)
        arguments.append("--no-strict")
        arguments.append(filePath as String)
        
        if entitlementsFilePath.length() > 0 {
            print("Adding entitlements with \(entitlementsFilePath)")
            arguments.append("--entitlements=\(entitlementsFilePath)")
        }
        return arguments
    }
    
    private func checkVerificationProcess() {
        if verificationSucceeded {
            print("Verification done")
            delegate?.updateProgress(animate: true, message: NSLocalizedString("Verification Complete", comment: ""))
            delegate?.signingComplete()
        } else {
            delegate?.updateProgress(animate: false, message: NSLocalizedString("Signing Verification Failed", comment: ""))
        }
    }
    
    private func removeBundleResourceSpecificationFromPlist(_ filePath: NSString) {
        let infoPath = "\(filePath)/\(kInfoPlistFilename)"
        let infoDict = NSMutableDictionary(contentsOfFile: infoPath)
        infoDict?.removeObject(forKey: "CFBundleResourceSpecification")
        infoDict?.write(toFile: infoPath, atomically: true)
    }
    
    private var verificationSucceeded: Bool {
        return verificationResult.length() == 0
    }
}
