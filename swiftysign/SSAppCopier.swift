//
//  SSAppCopier.swift
//  swiftysign
//
//  Created by Michael Specht on 5/22/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

protocol SSAppCopierDelegate: class {
    func updateProgress(animate: Bool, message: String)
    func doneCopying()
}

class SSAppCopier: NSObject {
    
    private var newAppName: String!
    private var newBundleId: String!
    private var archiveFilePath: NSString!
    
    private weak var delegate: SSAppCopierDelegate?
    
    init(delegate: SSAppCopierDelegate) {
        super.init()
        self.delegate = delegate
    }
    
    func copyArchive(settings: SSResignSettings) {
        
        self.newAppName = settings.newAppName
        self.newBundleId = settings.newBundleId
        self.archiveFilePath = settings.archiveFilePath
        
        let payloadPath = SSResigner.workingPath.appendingPathComponent(kPayloadDirName)
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Setting up \(kPayloadDirName) path in \(payloadPath)", comment: ""))
        
        try! FileManager.default.createDirectory(atPath: payloadPath, withIntermediateDirectories: true, attributes: nil)
        
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Retreiving \(kInfoPlistFilename)", comment: ""))
        
        do {
            let applicationPath = try getApplicationPath()
            delegate?.updateProgress(animate: true, message: NSLocalizedString("Copying .xcarchive app to \(kPayloadDirName) path", comment: ""))
            
            let copyTask = Process()
            copyTask.launchPath = "/bin/cp"
            copyTask.arguments = ["-r", applicationPath, payloadPath]
            copyTask.launch()
            copyTask.waitUntilExit()
            checkCopy()
        } catch SSError.errorOpeningPlist {
            delegate?.updateProgress(animate: false, message: NSLocalizedString("Error opening plist", comment: ""))
        } catch {
            delegate?.updateProgress(animate: false, message: NSLocalizedString("Error copying application", comment: ""))
        }
    }
    
    private func checkCopy() {
        print("Copy done")
        delegate?.updateProgress(animate: true, message: NSLocalizedString("xcarchive copied", comment: ""))
        
        if newBundleId.length() > 0 {
            changeAppBundleID()
            changeMetaDataBundleID()
        }
        
        if newAppName.length() > 0 {
            changeDisplayName()
        }
        
        delegate?.doneCopying()
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
        
        updateDisplayNameInStringsFiles()
        updateAppPlist()
        
        for case let file as NSString in SSResigner.directoryContents {
            if file.pathExtension.lowercased() == "plist" {
                let infoPlistPath = SSResigner.workingPath.appendingPathComponent(file as String)
                updatePlist(filePath: infoPlistPath, key: kKeyBundleDisplayNamePlistiTunesArtwork, value: newAppName)
                break
            }
        }
    }
    
    private func updateDisplayNameInStringsFiles() {
        
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
    }
    
    private func updateAppPlist() {
        let infoPlistPath = "\(SSResigner.appPath)/\(kInfoPlistFilename)"
        updatePlist(filePath: infoPlistPath, key: kKeyBundleDisplayNameApp, value: newAppName)
    }
    
    private func getApplicationPath() throws -> String {
        let infoPlistPath = archiveFilePath.appendingPathComponent(kInfoPlistFilename)
        let infoPlistDictionary = NSDictionary(contentsOfFile: infoPlistPath)
        
        guard infoPlistDictionary != nil && infoPlistDictionary![kKeyInfoPlistApplicationProperties] != nil else {
            throw SSError.errorOpeningPlist
        }
        
        let applicationPropertiesDict = infoPlistDictionary![kKeyInfoPlistApplicationProperties] as! NSDictionary
        var applicationPath = applicationPropertiesDict[kKeyInfoPlistApplicationPath] as! String
        applicationPath = (archiveFilePath.appendingPathComponent(kProductsDirName) as NSString).appendingPathComponent(applicationPath)
        
        return applicationPath
    }
}
