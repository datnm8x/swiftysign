//
//  main.swift
//  swiftysign
//
//  Created by Michael Specht on 5/22/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

class SSCommandLineSigner: NSObject, SSResignerDelegate, SSCertificateRetrieverDelegate {
    
    var resigner: SSResigner!
    
    init(arguments: [String]) {
        super.init()
        
        resigner = SSResigner(delegate: self, certificateDelegate: self)
        let settings = resignerSettingsFrom(arguments: CommandLine.arguments)
        
        if validateRequiredSettings(settings) {
            resigner.resign(resignerSettings: settings)
        } else {
            printUsage()
        }
    }
    
    private func resignerSettingsFrom(arguments: [String]) -> SSResignSettings {
        var args = arguments
        args.removeFirst()
        var settings = SSResignSettings()
        
        var i = 0
        while i+1 < args.count {
            let argname = args[i].lowercased()
            
            if argname == "-archive" {
                settings.archiveFilePath = args[i+1] as NSString
            } else if argname == "-provpath" {
                settings.provisioningFilePath = args[i+1] as NSString
            } else if argname == "-cert" {
                settings.certificateName = args[i+1] as NSString
            } else if argname == "-newappname" {
                settings.newAppName = args[i+1]
            } else if argname == "-newbundleid" {
                settings.newBundleId = args[i+1]
            } else if argname == "-entitlements" {
                settings.entitlementPath = args[i+1] as NSString
            } else if argname == "-newplistvalue" {
                if i+2 < args.count {
                    settings.changePlistEntry.append((key: args[i+1], newValue: args[i+2]))
                    i += 1
                }
            }
            
            i += 2
        }
        
        return settings
    }
    
    private func validateRequiredSettings(_ settings: SSResignSettings) -> Bool {
        return settings.archiveFilePath.length > 0 && settings.certificateName.length > 0
    }
    
    func printUsage() {
        let executableName = (CommandLine.arguments[0] as NSString).lastPathComponent
        
        print("""
usage:
\(executableName) -archive path/to/archive.xcarchive -provpath path/to/provision.mobileprovision -cert certificatename [-newbundleid new.bundle.identifier] [-newappname NewAppName] [-entitlements path/to/entitlements.plist] [-newplistvalue key newvalue]
""")
    }
    
    // MARK: Delegate functions
    
    func updateProgress(animate: Bool, message: String) {
        print(message)
    }
    
    func certificatesUpdated() {
        
    }
}

let _ = SSCommandLineSigner(arguments: CommandLine.arguments)






