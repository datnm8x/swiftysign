//
//  SSZipper.swift
//  swiftysign
//
//  Created by Michael Specht on 5/21/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

protocol SSZipperDelegate: class {
    func updateProgress(animate: Bool, message: String)
}

class SSZipper: NSObject {
    
    private weak var delegate: SSZipperDelegate?
    private var zipTask: Process?
    private var destinationPath = "" as NSString
    
    init(delegate: SSZipperDelegate) {
        super.init()
        self.delegate = delegate
    }
    
    func doZip(archivePath: NSString) {
        
        let destinationPathComponents = archivePath.pathComponents
        
        for component in destinationPathComponents {
            if component != destinationPathComponents.last! {
                destinationPath = destinationPath.appendingPathComponent(component) as NSString
            }
        }
        
        var filename = archivePath.lastPathComponent
        filename = filename.replacingOccurrences(of: ".xcarchive", with: "-resigned.ipa")
        
        destinationPath = destinationPath.appendingPathComponent(filename) as NSString
        
        print("Destination: \(destinationPath)")
        
        zipTask = Process()
        zipTask!.launchPath = "/usr/bin/zip"
        zipTask!.currentDirectoryPath = SSResigner.workingPath as String
        zipTask!.arguments = ["-qry", destinationPath, "."] as [String]
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkZip(timer:)), userInfo: nil, repeats: true)
        
        print("Zipping \(destinationPath)")
        delegate?.updateProgress(animate: true, message: NSLocalizedString("Saving \(filename)", comment: ""))
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
            delegate?.updateProgress(animate: false, message: NSLocalizedString("Saved IPA to \(destinationPath)", comment: ""))
            try! FileManager.default.removeItem(atPath: SSResigner.workingPath as String)
        }
    }
}
