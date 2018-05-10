//
//  StringExtension.swift
//  swiftysign
//
//  Created by Michael Specht on 5/8/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation


public extension String {
    public func length() -> Int64 {
        return Int64(self.count)
    }
    
    public func trim() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func substring(length: Int) -> String {
        var trimmedString = self
        if Int(trimmedString.length()) > length {
            trimmedString = trimmedString.substring(0, length: length)
        }
        return trimmedString
    }
    
    public func substring(_ location: Int, length: Int) -> String! {
        return (self as NSString).substring(with: NSRange(location: location, length: length))
    }
    
    public subscript(index: Int) -> String! {
        get {
            return self.substring(index, length: 1)
        }
    }
    
    public func location(_ other: String) -> Int {
        return (self as NSString).range(of: other).location
    }
    
    public func contains(_ other: String) -> Bool {
        return self.range(of: other) != nil
    }
    
    public func containsIgnoringCase(_ other: String) -> Bool {
        return self.range(of: other, options: NSString.CompareOptions.caseInsensitive) != nil
    }
    
    public func isNumeric() -> Bool {
        return (self as NSString).rangeOfCharacter(from: CharacterSet.decimalDigits.inverted).location == NSNotFound
    }
    
    public func isAlphaNumeric() -> Bool {
        return (self as NSString).rangeOfCharacter(from: CharacterSet.alphanumerics.inverted).location == NSNotFound
    }
    
    public func limitedTo(length n: Int) -> String {
        if (self.count <= n) {
            return self
        }
        return String(Array(self).prefix(upTo: n))
    }
}

