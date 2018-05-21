//
//  ViewController.swift
//  swiftysign
//
//  Created by Michael Specht on 5/8/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Cocoa
import Foundation

class ViewController: NSViewController, NSComboBoxDataSource, SSCertificateRetrieverDelegate, SSResignerDelegate {

    @IBOutlet weak var ipaPathField: NSTextField!
    @IBOutlet weak var provisioningField: NSTextField!
    @IBOutlet weak var entitlementsField: NSTextField!
    @IBOutlet weak var dylibField: NSTextField!
    @IBOutlet weak var certificateField: NSComboBox!
    @IBOutlet weak var newAppNameField: NSTextField!
    @IBOutlet weak var newBundleIdField: NSTextField!
    @IBOutlet weak var progressLabel: NSTextField!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var resignAppButton: NSButton!
    
    private let resigner = SSResigner()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Swifty Sign", comment: "")
        
        certificateField.dataSource = self
        
        progressLabel.isHidden = true
        progressIndicator.isHidden = true
        
        
        resigner.setup(viewDelegate: self)
        
        entitlementsField.stringValue = resigner.entitlementPath as String
        provisioningField.stringValue = resigner.provisioningFilePath as String
    }
    
    
    @IBAction func resignApp(_ sender: Any) {
        disableControls()
        progressLabel.isHidden = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        
        resigner.resign(archivePath: ipaPathField.stringValue,
                        entitlementPath: entitlementsField.stringValue,
                        provisioningFilePath: provisioningField.stringValue,
                        certificateName: resigner.certificates[certificateField.indexOfSelectedItem].name,
                        newBundleId: newBundleIdField.stringValue,
                        newAppName: newAppNameField.stringValue)
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
        return resigner.certificates.count
    }
    
    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        return resigner.certificates[index].name
    }
    
    // MARK: SSResignerDelegate
    func updateProgress(animate: Bool, message: String) {
        if animate {
            disableControls()
        } else {
            enableControls()
        }
        
        progressLabel.stringValue = message
    }

    // MARK: SSCertificateRetrieverDelegate
    func certificatesUpdated() {
        certificateField.reloadData()
        
        let selectedIndex = UserDefaults.standard.integer(forKey: "CERT_INDEX")
        if selectedIndex != -1 && certificateField.numberOfItems > selectedIndex {
            certificateField.selectItem(at: selectedIndex)
        }
    }
}

