//
//  ViewController.swift
//  swiftysign
//
//  Created by Michael Specht on 5/8/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Cocoa
import Foundation

struct SSCertificate {
    var name = ""
    var id = ""
}

class ViewController: NSViewController, NSComboBoxDataSource {

    @IBOutlet weak var ipaPathField: NSTextField!
    @IBOutlet weak var provisioningField: NSTextField!
    @IBOutlet weak var entitlementsField: NSTextField!
    @IBOutlet weak var dylibField: NSTextField!
    @IBOutlet weak var certificateField: NSComboBox!
    @IBOutlet weak var newAppNameField: NSTextField!
    @IBOutlet weak var newBundleIdField: NSTextField!
    @IBOutlet weak var progressLabel: NSTextField!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var changeBundleIdCheckBox: NSButton!
    @IBOutlet weak var changeNameCheckBox: NSButton!
    @IBOutlet weak var resignAppButton: NSButton!
    
    var certificates = [SSCertificate]()
    var workingPath: NSString!
    var entitlementsDirPath: NSString!
    var appPath: NSString?
    
    var additionalResourcesToSign = [String]()
    var additionalToSign = false
    
    var verificationResult = ""
    var codesignResult = ""
    var entitlementsResult = ""
    var entitlementsFilePath = ""
    
    var codesignTask: Process?
    var verifyTask: Process?
    var zipTask: Process?
    var provisioningTask: Process?
    var generateEntitlementsTask: Process?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Swifty Sign", comment: "")
        // Do any additional setup after loading the view.
        progressLabel.isHidden = true
        progressIndicator.isHidden = true
        
        let defaults = UserDefaults.standard
        
        certificateField.dataSource = self
        getCertificates()
        
        
        if defaults.value(forKey: "ENTITLEMENT_PATH") != nil {
            entitlementsField.stringValue = defaults.string(forKey: "ENTITLEMENT_PATH")!
        }
        if defaults.value(forKey: "MOBILEPROVISION_PATH") != nil {
            provisioningField.stringValue = defaults.string(forKey: "MOBILEPROVISION_PATH")!
        }
        
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
        defaults.set(certificateField.indexOfSelectedItem, forKey: "CERT_INDEX")
        defaults.set(entitlementsField.stringValue, forKey: "ENTITLEMENT_PATH")
        defaults.set(provisioningField.stringValue, forKey: "MOBILEPROVISION_PATH")
        defaults.set(newBundleIdField.stringValue, forKey: kKeyPrefsBundleIDChange)
        defaults.synchronize()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    var getCertificateTask: Process?
    private func getCertificates() {
        
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
                        certificateField.reloadData()
                        certificateField.selectItem(at: selectedIndex)
                    }
                }
            } else {
                print("No certificates")
            }
        }
    
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
            
            self.certificateField.reloadData()
        }
    }
    @IBAction func browseIPA(_ sender: Any) {
        let openDialog = NSOpenPanel.init()
        openDialog.canChooseFiles = true
        openDialog.canChooseDirectories = false
        openDialog.allowsMultipleSelection = false
        openDialog.allowsOtherFileTypes = false
        openDialog.allowedFileTypes = ["ipa", "IPA", "xcarchive"]
        if openDialog.runModal() == NSApplication.ModalResponse.OK {
            let filenameOpened = openDialog.urls.first!.path
            ipaPathField.stringValue = filenameOpened
        }
    }
    
    @IBAction func browseProvisioning(_ sender: Any) {
        let openDialog = NSOpenPanel.init()
        openDialog.canChooseFiles = true
        openDialog.canChooseDirectories = false
        openDialog.allowsMultipleSelection = false
        openDialog.allowsOtherFileTypes = false
        openDialog.allowedFileTypes = ["mobileprovision"]
        if openDialog.runModal() == NSApplication.ModalResponse.OK {
            let filenameOpened = openDialog.urls.first!.path
            provisioningField.stringValue = filenameOpened
        }
    }
    
    @IBAction func browseEntitlements(_ sender: Any) {
    }
    
    @IBAction func browseDylib(_ sender: Any) {
    }
    
    @IBAction func resignApp(_ sender: Any) {
        updateSavedPaths()
        
        let executablePath = ipaPathField.stringValue as NSString
        workingPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("swiftysign") as NSString
        entitlementsDirPath = workingPath.appending("-entitlements") as NSString
        
        if certificateField.objectValue != nil {
            if executablePath.pathExtension.lowercased() == "ipa" || executablePath.pathExtension.lowercased() == "xcarchive" {
                disableControls()
                progressLabel.isHidden = false
                progressIndicator.isHidden = false
                progressIndicator.startAnimation(nil)

                do {
                    try FileManager.default.removeItem(atPath: String(workingPath))
                    try FileManager.default.removeItem(atPath: String(entitlementsDirPath))
                } catch {
                    print("file not removed")
                }
                
                try! FileManager.default.createDirectory(atPath: String(workingPath), withIntermediateDirectories: true, attributes: nil)
                try! FileManager.default.createDirectory(atPath: String(entitlementsDirPath), withIntermediateDirectories: true, attributes: nil)
                
                if executablePath.pathExtension.lowercased() == "ipa" {
                   
                    
                } else if executablePath.pathExtension.lowercased() == "xcarchive" {
                    let payloadPath = workingPath.appendingPathComponent(kPayloadDirName)
                    print("Setting up \(kPayloadDirName) path in \(payloadPath)")
                    
                    progressLabel.stringValue = NSLocalizedString("Setting up \(kPayloadDirName) path", comment: "")
                    
                    try! FileManager.default.createDirectory(atPath: payloadPath, withIntermediateDirectories: true, attributes: nil)
                    
                    print("Retrieving \(kInfoPlistFilename)")
                    progressLabel.stringValue = NSLocalizedString("Retreiving \(kInfoPlistFilename)", comment: "")
                    
                    let infoPlistPath = executablePath.appendingPathComponent(kInfoPlistFilename)
                    let infoPlistDictionary = NSDictionary(contentsOfFile: infoPlistPath)
                    
                    if infoPlistDictionary != nil {
                        var applicationPath: String?
                        
                        let applicationPropertiesDict = infoPlistDictionary!.object(forKey: kKeyInfoPlistApplicationProperties)
                        
                        if applicationPropertiesDict != nil {
                            applicationPath = (applicationPropertiesDict as! NSDictionary).object(forKey: kKeyInfoPlistApplicationPath) as? String
                        }
                        
                        if applicationPath != nil {
                            applicationPath = (executablePath.appendingPathComponent(kProductsDirName) as NSString).appendingPathComponent(applicationPath!)
                            
                            progressLabel.stringValue = "Copying .xcarchive app to \(kPayloadDirName) path"
                            
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
        } else {
            print("Certificate is required")
        }
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
            progressLabel.stringValue = "xcarchive copied"

            if changeBundleIdCheckBox.state == .on {
                if newBundleIdField.stringValue.length() > 0 {
                    changeAppBundleID()
                    changeMetaDataBundleID()
                }
            }
            
            if changeNameCheckBox.state == .on {
                if newAppNameField.stringValue.length() > 0 {
                    changeDisplayName()
                }
            }
            
            if provisioningField.stringValue.length() == 0 {
                codeSignApp()
            } else {
                doProvisioning()
            }
        }
    }
    
    private func changeAppBundleID() {
        
        var infoPlistPath = ""
        
        for file in directoryContents {
            if (file as NSString).pathExtension == "app" {
                infoPlistPath = "\(workingPath.appendingPathComponent(kPayloadDirName))/\(file)/\(kInfoPlistFilename)"
                break
            }
        }
        
        updatePlist(filePath: infoPlistPath, key: kFileSharingEnabledName, value: true)
        updatePlist(filePath: infoPlistPath, key: kKeyBundleIDPlistApp, value: newBundleIdField.stringValue)
    }
    
    private func updatePlist(filePath: String, key: String, value: Any) {
        if FileManager.default.fileExists(atPath: filePath) {
            let plist = NSMutableDictionary(contentsOfFile: filePath)!
            plist.setObject(value, forKey: key as NSCopying)
            
            let xmlData = try! PropertyListSerialization.data(fromPropertyList: plist, format: PropertyListSerialization.PropertyListFormat.xml, options: 0)
            FileManager.default.createFile(atPath: filePath, contents: xmlData, attributes: nil)
        }
    }
    
    private func changeMetaDataBundleID() {
        
        var infoPlistPath = ""
        
        for file in directoryContents {
            if (file as NSString).pathExtension.lowercased() == "plist" {
                infoPlistPath = workingPath.appendingPathComponent(file)
                break
            }
        }
        
        updatePlist(filePath: infoPlistPath, key: kKeyBundleIDPlistiTunesArtwork, value: newBundleIdField.stringValue)
    }
    
    private func changeDisplayName() {

        let appFolder = workingPath.appendingPathComponent(kPayloadDirName)
        let dirEnumerator = FileManager.default.enumerator(atPath: appFolder)!
        
        var stringsFiles = [String]()
        
        for case let file as NSString in dirEnumerator {
            if file.hasSuffix(".lproj/InfoPlist.strings") {
                stringsFiles.append("\(appFolder)/\(file)")
            }
        }
        
        for filePath in stringsFiles {
            if FileManager.default.fileExists(atPath: filePath) {
                updatePlist(filePath: filePath, key: kKeyBundleDisplayNameApp, value: newAppNameField.stringValue as NSCopying)
            }
        }

        for case let file as NSString in directoryContents {
            if file.pathExtension.lowercased() == "app" {
                let infoPlistPath = "\(workingPath)/\(kPayloadDirName)/\(file)/\(kInfoPlistFilename)"
                updatePlist(filePath: infoPlistPath, key: kKeyBundleDisplayNameApp, value: newAppNameField.stringValue as NSCopying)
                break
            }
        }
        
        for case let file as NSString in directoryContents {
            if file.pathExtension.lowercased() == "plist" {
                let infoPlistPath = workingPath.appendingPathComponent(file as String)
                updatePlist(filePath: infoPlistPath, key: kKeyBundleDisplayNamePlistiTunesArtwork, value: newAppNameField.stringValue as NSCopying)
                break
            }
        }
    }
    
    private func doProvisioning() {
        
        for case let file as NSString in directoryContents {
            if file.pathExtension.lowercased() == "app" {
                appPath = (workingPath.appendingPathComponent(kPayloadDirName) as NSString).appendingPathComponent(file as String) as NSString
                let embeddedPath = appPath!.appendingPathComponent("embedded.mobileprovision")
                if FileManager.default.fileExists(atPath: embeddedPath) {
                    print("Found embedded.mobileprovision, deleting...")
                    try! FileManager.default.removeItem(atPath: embeddedPath)
                }
                break
            }
        }
        
        let targetPath = appPath!.appendingPathComponent("embedded.mobileprovision")
        provisioningTask = Process()
        provisioningTask!.launchPath = "/bin/cp"
        provisioningTask!.arguments = [provisioningField.stringValue, targetPath]
        
        provisioningTask!.launch()
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkProvisioning(timer:)), userInfo: nil, repeats: true)
    }
    
    var directoryContents: [String] {
        get {
            return try! FileManager.default.contentsOfDirectory(atPath: workingPath.appendingPathComponent(kPayloadDirName))
        }
    }
    
    @objc private func checkProvisioning(timer: Timer) {
        guard provisioningTask != nil else {
            return
        }
        
        if !provisioningTask!.isRunning {
            timer.invalidate()
            provisioningTask = nil
            
            for case let file as NSString in directoryContents {
                if file.pathExtension.lowercased() == "app" {
                    appPath = (workingPath.appendingPathComponent(kPayloadDirName) as NSString).appendingPathComponent(file as String) as NSString
                    let embeddedPath = appPath!.appendingPathComponent("embedded.mobileprovision")
                    if FileManager.default.fileExists(atPath: embeddedPath) {
                        
                        var identifierOK = false
                        var identifierInProvisioning = ""
                        let embeddedProvisioning = try! NSString(contentsOfFile: appPath!.appendingPathComponent("embedded.mobileprovision"), encoding: String.Encoding.ascii.rawValue)
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
                        let infoPlist = NSDictionary(contentsOfFile: appPath!.appendingPathComponent(kInfoPlistFilename))!
                        if identifierInProvisioning == infoPlist[kKeyBundleIDPlistApp] as! String{
                            print("Identifiers match")
                            identifierOK = true
                        }
                        
                        if identifierOK {
                            print("Provisioning Complete")
                            progressLabel.stringValue = NSLocalizedString("Provisioning complete", comment: "")
                            fixEntitlements()
                        } else {
                            print("Provisioning failed -- bad identifier")
                            progressLabel.stringValue = NSLocalizedString("Provisioning Failed", comment: "")
                            enableControls()
                        }
                        
                    } else {
                        print("Provisioning failed")
                        progressLabel.stringValue = NSLocalizedString("Provisioning Failed", comment: "")
                        enableControls()
                    }
                    break
                }
            }
        }
    }
    
    private func usePreMadeEntitlementsFile() -> Bool {
        return entitlementsField.stringValue.length() > 0
    }
    
    private func provisioningFileSpecified() -> Bool {
        return provisioningField.stringValue.length() > 0
    }
    
    private func fixEntitlements() {
        
        guard !usePreMadeEntitlementsFile() && provisioningFileSpecified() else {
            codeSignApp()
            return
        }
        
        progressLabel.stringValue = NSLocalizedString("Generating entitlements", comment: "")
        print("Generating entitlements")
        
        guard appPath != nil else {
            print("App path is null")
            return
        }
        
        let pipe = Pipe()
        generateEntitlementsTask = Process()
        generateEntitlementsTask!.launchPath = "/usr/bin/security"
        generateEntitlementsTask!.arguments = ["cms", "-D", "-i", provisioningField.stringValue]
        generateEntitlementsTask!.currentDirectoryPath = workingPath as String
        generateEntitlementsTask!.standardError = pipe
        generateEntitlementsTask!.standardOutput = pipe
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkEntitlementsFix(timer:)), userInfo: nil, repeats: true)
        
        generateEntitlementsTask!.launch()
        
        Thread.detachNewThreadSelector(#selector(watchEntitlements(handle:)), toTarget: self, with: pipe)
    }
    
    @objc private func checkEntitlementsFix(timer: Timer) {
        guard generateEntitlementsTask != nil else {
            return
        }
        
        if !generateEntitlementsTask!.isRunning {
            timer.invalidate()
            generateEntitlementsTask = nil
            print("Entitlements fixed")
            progressLabel.stringValue = NSLocalizedString("Entitlements Generated", comment: "")
            editEntitlements()
        }
    }
    
    private func editEntitlements() {
     
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
        //end macOS 10.12 bug fix.
        
        var entitlements = entitlementsResult.propertyList() as! NSDictionary
        entitlements = entitlements["Entitlements"] as! NSDictionary
        let filePath = entitlementsDirPath.appendingPathComponent("entitlements.plist")
        print("Entitlements dir path \(entitlementsDirPath), filepath \(filePath)")
        let xmlData = try! PropertyListSerialization.data(fromPropertyList: entitlements, format: PropertyListSerialization.PropertyListFormat.xml, options: 0)
        let success = FileManager.default.createFile(atPath: filePath, contents: xmlData, attributes: nil)
        print("Writing entitlements complete with \(success)")
//        try! xmlData.write(to: URL(string: filePath)!)
        entitlementsFilePath = filePath
        codeSignApp()
    }
    
    @objc private func watchEntitlements(handle: Pipe) {
        entitlementsResult = String(data: handle.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        print("Result of entitlement change: \(entitlementsResult)")
    }
    
    private func codeSignApp() {

        var frameworksDirPath: String?
        additionalToSign = false
        additionalResourcesToSign.removeAll()
        
        for file in directoryContents {
            if (file as NSString).pathExtension.lowercased() == "app" {
                appPath = (workingPath.appendingPathComponent(kPayloadDirName) as NSString).appendingPathComponent(file) as NSString
                frameworksDirPath = appPath!.appendingPathComponent(kFrameworksDirName)
                print("Found \(appPath!)")
                
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
                progressLabel.stringValue = "Codesigning \(file)"
                break
            }
        }
        
        // Sign plugins and other executables except the main one
        
        let dir = appPath!
        let dirEnumerator = FileManager.default.enumerator(atPath: dir as String)!
        
        for case let file as NSString in dirEnumerator {
            if file.lastPathComponent == kInfoPlistFilename
                && file.deletingLastPathComponent.trimmingCharacters(in: CharacterSet.whitespaces).length() > 0 {
                let infoPlistPath = appPath!.appendingPathComponent(file as String)
                let infoDict = NSDictionary.init(contentsOfFile: infoPlistPath)
                if infoDict?.object(forKey: "CFBundleExecutable") != nil {
                    additionalToSign = true
                    let dirToSign = (infoPlistPath as NSString).deletingLastPathComponent
                    print("Found \(dirToSign)")
                    additionalResourcesToSign.append(dirToSign)
                    
                    let _ = self.changeExtensionBundleIdPrefix(filePath: infoPlistPath,
                                                       bundleIdKey: kKeyBundleIDPlistApp,
                                                       newBundleIdPrefix: newBundleIdField.stringValue)
                }
            }
        }
        
        if appPath != nil {
            if additionalToSign {
                self.signFile(filePath: additionalResourcesToSign.last! as NSString)
                additionalResourcesToSign.removeLast()
            } else {
                self.signFile(filePath: appPath!)
            }
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
        progressLabel.stringValue = "Codesigning \(filePath)"

        var arguments = [String]()
        arguments.append("-fs")
        arguments.append(certificateField.objectValue as! String)
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
                signFile(filePath: appPath!)
            } else {
                print("Codesigning done")
                progressLabel.stringValue = NSLocalizedString("Codesigning completed", comment: "")
                verifySignature()
            }
        }
    }
    
    private func verifySignature() {
        guard appPath != nil else {
            return
        }
        
        verifyTask = Process()
        let pipe = Pipe()
        
        verifyTask!.launchPath = "/usr/bin/codesign"
        verifyTask!.arguments = ["-v", appPath! as String]
        verifyTask!.standardOutput = pipe
        verifyTask!.standardError = pipe
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkVerificationProcess(timer:)), userInfo: nil, repeats: true)
        
        print("Verifying \(appPath!)")
        progressLabel.stringValue = NSLocalizedString("Verifying \(appPath!.lastPathComponent)", comment: "")
        
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
                progressLabel.stringValue = NSLocalizedString("Verification Complete", comment: "")
                doZip()
            } else {
                print("Signing failed")
            }
        }
    }
    
    private func doZip() {
        guard appPath != nil else {
            return
        }

        let destinationPathComponents = (ipaPathField.stringValue as NSString).pathComponents
        var destinationpath = "" as NSString
        
        for component in destinationPathComponents {
            if component != destinationPathComponents.last! {
                destinationpath = destinationpath.appendingPathComponent(component) as NSString
            }
        }
        
        var filename = (ipaPathField.stringValue as NSString).lastPathComponent
        filename = filename.replacingOccurrences(of: ".xcarchive", with: "-resigned.ipa")

        destinationpath = destinationpath.appendingPathComponent(filename) as NSString
        
        print("Destination: \(destinationpath)")
        
        zipTask = Process()
        zipTask!.launchPath = "/usr/bin/zip"
        zipTask!.currentDirectoryPath = workingPath as String
        zipTask!.arguments = ["-qry", destinationpath, "."] as [String]
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkZip(timer:)), userInfo: nil, repeats: true)
        
        print("Zipping \(destinationpath)")
        
        progressLabel.stringValue = NSLocalizedString("Saving \(filename)", comment: "")
        zipTask!.launch()
    }
    
    @objc private func checkZip(timer: Timer) {
        guard zipTask != nil else {
            return
        }
        
        if !zipTask!.isRunning {
            timer.invalidate()
            zipTask = nil
            
            print("Zip done")
            progressLabel.stringValue = NSLocalizedString("Saved IPA", comment: "")
            try! FileManager.default.removeItem(atPath: workingPath as String)
            
            enableControls()
        }
    }
    
    private func disableControls() {
     resignAppButton.isEnabled = false
        progressIndicator.isHidden = false
    }
    
    private func enableControls() {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        resignAppButton.isEnabled = true
    }
    
    func numberOfItems(in comboBox: NSComboBox) -> Int {
        return certificates.count
    }
    
    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        return certificates[index].name
    }
    
    private func matchesForRegexInText(_ regex: String!, text: String!) -> [String] {
        
        do {
            let regex = try NSRegularExpression(pattern: regex, options: [])
            let nsString = text as NSString
            let results = regex.matches(in: text,
                                        options: [], range: NSMakeRange(0, nsString.length))
            return results.map { nsString.substring(with: $0.range)}
        } catch let error as NSError {
            print("invalid regex: \(error.localizedDescription)")
            return []
        }
    }
    
}

