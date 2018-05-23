//
//  SSEntitlementUpdater.swift
//  swiftysign
//
//  Created by Michael Specht on 5/21/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

protocol SSEntitlementUpdaterDelegate: class {
    func readyForCodeSign(_ entitlementFilePath: String?)
    func updateProgress(animate: Bool, message: String)
}

class SSEntitlementUpdater: NSObject {
    
    private weak var delegate: SSEntitlementUpdaterDelegate?
    
    private var entitlementResult = ""
    private var entitlementsResult = ""
    private var entitlementsDirPath: NSString!
    private var workingPath: String!
    
    init(path: String, delegate: SSEntitlementUpdaterDelegate) {
        self.delegate = delegate
        
        workingPath = path
        entitlementsDirPath = workingPath.appending("-entitlements") as NSString
    }
 
    func fixEntitlements(premadeEntitlementsFilePath: String, provisioningFilePath: String) {
        setupFileDirectories()
        
        guard premadeEntitlementsFilePath.length() == 0 && provisioningFilePath.length() == 0 else {
            delegate?.readyForCodeSign(nil)
            return
        }
        
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Generating entitlements", comment: ""))
        print("Generating entitlements")
        
        let pipe = Pipe()
        let generateEntitlementsTask = Process()
        generateEntitlementsTask.launchPath = "/usr/bin/security"
        generateEntitlementsTask.arguments = ["cms", "-D", "-i", provisioningFilePath]
        generateEntitlementsTask.currentDirectoryPath = workingPath
        generateEntitlementsTask.standardError = pipe
        generateEntitlementsTask.standardOutput = pipe
        
        generateEntitlementsTask.launch()
        generateEntitlementsTask.waitUntilExit()
        
        entitlementsResult = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        print("Result of entitlement change: \(entitlementsResult)")
        
        checkEntitlementsFix()
    }
    
    private func checkEntitlementsFix() {
        print("Entitlements fixed")
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Entitlements Generated", comment: ""))
        editEntitlements()
    }
    
    private func editEntitlements() {
        trimUnnecessaryLinesFromEntitlementResult()
        
        var entitlements = entitlementsResult.propertyList() as! NSDictionary
        entitlements = entitlements["Entitlements"] as! NSDictionary
        let filePath = entitlementsDirPath.appendingPathComponent("entitlements.plist")
        print("Entitlements dir path \(entitlementsDirPath), filepath \(filePath)")
        let xmlData = try! PropertyListSerialization.data(fromPropertyList: entitlements, format: PropertyListSerialization.PropertyListFormat.xml, options: 0)
        let success = FileManager.default.createFile(atPath: filePath, contents: xmlData, attributes: nil)
        print("Writing entitlements complete with \(success)")
        delegate?.readyForCodeSign(filePath)
    }
    
    @objc private func watchEntitlements(handle: Pipe) {
        entitlementsResult = String(data: handle.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        print("Result of entitlement change: \(entitlementsResult)")
    }
  
    
    private func setupFileDirectories() {
        do {
            try FileManager.default.removeItem(atPath: String(entitlementsDirPath))
        } catch {
            print("file not removed")
        }
        
        try! FileManager.default.createDirectory(atPath: String(entitlementsDirPath), withIntermediateDirectories: true, attributes: nil)
    }
    
    private func trimUnnecessaryLinesFromEntitlementResult() {
        //ref: https://github.com/maciekish/iReSign/pull/96/commits/674731de0615b54ce3278579a324dc93da4c62be
        //macOS 10.12 bug: /usr/bin/security appends a junk line at the top of the XML file.
        
        if entitlementsResult.contains("SecPolicySetValue") {
            let nsEntitlementResult = entitlementsResult as NSString
            
            let newLineLocation = nsEntitlementResult.range(of: "\n").location
            if newLineLocation != NSNotFound {
                var length = nsEntitlementResult.length
                length -= newLineLocation
                entitlementsResult = entitlementsResult.substring(newLineLocation, length: length)
            }
        }
    }
}
