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
    
    private var codesignResult = ""
    private var codesignTask: Process?
    
    private var verifyTask: Process?
    private var verificationResult = ""
    
    private let zipper = SSZipper()
    
    weak var delegate: SSCodeSignerDelegate?
    
    func codeSignApp(resigner: SSResigner) {
        
        self.entitlementsFilePath = resigner.entitlementsFilePath
        self.certificateName = resigner.certificateName as String!
        self.newBundleId = resigner.newBundleId
        
        var frameworksDirPath: String?
        additionalToSign = false
        additionalResourcesToSign.removeAll()
        
        frameworksDirPath = SSResigner.appPath.appendingPathComponent(kFrameworksDirName)
        print("Found \(SSResigner.appPath)")
        
        if FileManager.default.fileExists(atPath: frameworksDirPath!) {
            print("Found \(frameworksDirPath!)")
            additionalToSign = true
            let frameworkContents = try! FileManager.default.contentsOfDirectory(atPath: frameworksDirPath!)
            for frameworkFile in frameworkContents {
                let ext = (frameworkFile as NSString).pathExtension.lowercased()
                if ext == "framework" || ext == "dylib" {
                    let frameworkPath = (frameworksDirPath! as NSString).appendingPathComponent(frameworkFile)
                    print("Found \(frameworkPath)")
                    additionalResourcesToSign.append(frameworkPath)
                }
            }
        }
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Codesigning \(SSResigner.appPath.lastPathComponent)", comment: ""))
        
        
        // Sign plugins and other executables except the main one
        
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
        
        if additionalToSign {
            self.signFile(filePath: additionalResourcesToSign.last! as NSString)
            additionalResourcesToSign.removeLast()
        } else {
            self.signFile(filePath: SSResigner.appPath)
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
            
            let xmlData = try! PropertyListSerialization.data(fromPropertyList: plist, format: PropertyListSerialization.PropertyListFormat.xml, options: 0)
            FileManager.default.createFile(atPath: filePath, contents: xmlData, attributes: nil)
            return true
        }
        
        
        return false
        
    }
    
    private func signFile(filePath: NSString) {
        print("Codesigning \(filePath)")
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Codesigning \(filePath)", comment: ""))
        
        var arguments = [String]()
        arguments.append("-fs")
        arguments.append(certificateName)
        arguments.append("--no-strict")
        arguments.append(filePath as String)
        
        
        let infoPath = "\(filePath)/\(kInfoPlistFilename)"
        
        //        do {
        //            let rawData = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
        //            let realData = try PropertyListSerialization.propertyList(from: rawData, format: nil) as! [String:Any]
        //        } catch let error as NSError {
        //            print(error)
        //        }
        
        let infoDict = NSMutableDictionary(contentsOfFile: infoPath)
        infoDict?.removeObject(forKey: "CFBundleResourceSpecification")
        infoDict?.write(toFile: infoPath, atomically: true)
        
        if entitlementsFilePath.length() > 0 {
            print("Adding entitlements with \(entitlementsFilePath)")
            arguments.append("--entitlements=\(entitlementsFilePath)")
        }
        
        print("Signing arguments:\n \(arguments)")
        
        codesignTask = Process()
        let pipe = Pipe()
        
        codesignTask!.launchPath = "/usr/bin/codesign"
        codesignTask!.arguments = arguments
        codesignTask!.standardOutput = pipe
        codesignTask!.standardError = pipe
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkCodeSigning(timer:)), userInfo: nil, repeats: true)
        
        codesignTask!.launch()
        Thread.detachNewThreadSelector(#selector(watchCodeSigning(streamHandle:)), toTarget: self, with: pipe)
    }
    
    @objc private func watchCodeSigning(streamHandle: Pipe) {
        codesignResult = String(data: streamHandle.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        print("Result of codesign: \(codesignResult)")
    }
    
    
    @objc private func checkCodeSigning(timer: Timer) {
        guard codesignTask != nil else {
            return
        }
        
        if !codesignTask!.isRunning {
            timer.invalidate()
            codesignTask = nil
            if additionalResourcesToSign.count > 0 {
                signFile(filePath: additionalResourcesToSign.last! as NSString)
                additionalResourcesToSign.removeLast()
            } else if additionalToSign {
                additionalToSign = false
                signFile(filePath: SSResigner.appPath)
            } else {
                print("Codesigning done")
                delegate?.updateProgress(animate: true, message: NSLocalizedString("Codesigning completed", comment: ""))
                verifySignature()
            }
        }
    }
    
    private func verifySignature() {
        
        verifyTask = Process()
        let pipe = Pipe()
        
        verifyTask!.launchPath = "/usr/bin/codesign"
        verifyTask!.arguments = ["-v", SSResigner.appPath as String]
        verifyTask!.standardOutput = pipe
        verifyTask!.standardError = pipe
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkVerificationProcess(timer:)), userInfo: nil, repeats: true)
        
        print("Verifying \(SSResigner.appPath)")
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Verifying \(SSResigner.appPath.lastPathComponent)", comment: ""))
        
        verifyTask!.launch()
        
        Thread.detachNewThreadSelector(#selector(watchVerificationProcess(streamHandle:)), toTarget: self, with: pipe)
    }
    
    @objc private func watchVerificationProcess(streamHandle: Pipe) {
        verificationResult = String(data: streamHandle.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        print("Result of verify: \(verificationResult)")
    }
    
    @objc private func checkVerificationProcess(timer: Timer) {
        guard verifyTask != nil else {
            return
        }
        
        if !verifyTask!.isRunning {
            timer.invalidate()
            verifyTask = nil
            if verificationResult.length() == 0 {
                print("Verification done")
                delegate?.updateProgress(animate: true, message: NSLocalizedString("Verification Complete", comment: ""))
                delegate?.signingComplete()
            } else {
                delegate?.updateProgress(animate: false, message: NSLocalizedString("Signing Verification Failed", comment: ""))
            }
        }
    }
}
