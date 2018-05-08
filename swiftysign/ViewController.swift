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
    
    override func viewDidLoad() {
        super.viewDidLoad()

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
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkCerts(timer:)), userInfo: nil, repeats: true)
        
        getCertificateTask!.launch()
        
        let handle = pipe.fileHandleForReading
        Thread.detachNewThreadSelector(#selector(watchCertificates(handle:)), toTarget: self, with: handle)
    }
    
    @objc private func checkCerts(timer: Timer) {
        guard getCertificateTask != nil else {
            timer.invalidate()
            return
        }
        
        if !getCertificateTask!.isRunning {
            timer.invalidate()
            getCertificateTask = nil
            
            if certificates.count > 0 {
                print("Retrieved the certificates...")
                if UserDefaults.standard.value(forKey: "CERT_INDEX") != nil {
                    let selectedIndex = UserDefaults.standard.integer(forKey: "CERT_INDEX")
                    if selectedIndex != NSNotFound {
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
    }
    
    @IBAction func browseProvisioning(_ sender: Any) {
    }
    
    @IBAction func browseEntitlements(_ sender: Any) {
    }
    
    @IBAction func browseDylib(_ sender: Any) {
    }
    
    @IBAction func resignApp(_ sender: Any) {
        updateSavedPaths()
        
        
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

