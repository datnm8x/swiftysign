//
//  main.swift
//  swiftysign
//
//  Created by Michael Specht on 5/22/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

enum Arguments: String {
    case palindrome = "p"
    case anagram = "a"
    case help = "h"
    case unknown
    
    init(value: String) {
        switch value {
        case "a": self = .anagram
        case "p": self = .palindrome
        case "h": self = .help
        default: self = .unknown
        }
    }
}

class SSCommandLineSigner: NSObject, SSResignerDelegate, SSCertificateRetrieverDelegate {
    
    var resigner: SSResigner!
    
    init(arguments: [String]) {
        super.init()
        
        resigner = SSResigner(delegate: self, certificateDelegate: self)
        let settings = resignerSettingsFrom(arguments: CommandLine.arguments)
        
        if validateRequiredSettings(settings) {
//            CFRunLoopRun();
            resigner.resign(resignerSettings: settings)
        } else {
            printUsage()
        }
    }
    
    private func resignerSettingsFrom(arguments: [String]) -> SSResignSettings {
        var args = arguments
        args.removeFirst()
        var settings = SSResignSettings()
        
        var argumentsAsTuples = [(argname: String, value: String)]()
        for i in stride(from: 0, to: args.count, by: 2) {
            argumentsAsTuples.append((argname: args[i].lowercased(), value: args[i+1]))
        }
        
        for tuple in argumentsAsTuples {
            if tuple.argname == "-archive" {
                settings.archiveFilePath = tuple.value as NSString
            } else if tuple.argname == "-provpath" {
                settings.provisioningFilePath = tuple.value as NSString
            } else if tuple.argname == "-cert" {
                settings.certificateName = tuple.value as NSString
            } else if tuple.argname == "-newappname" {
                settings.newAppName = tuple.value
            } else if tuple.argname == "-newbundleid" {
                settings.newBundleId = tuple.value
            } else if tuple.argname == "-entitlements" {
                settings.entitlementPath = tuple.value as NSString
            }
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
\(executableName) -archive path/to/archive.xcarchive -provpath path/to/provision.mobileprovision -cert certificatename [-newbundleid new.bundle.identifier] [-newappname NewAppName] [-entitlements path/to/entitlements.plist]
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






