//
//  SSError.swift
//  swiftysign
//
//  Created by Michael Specht on 5/22/18.
//  Copyright © 2018 mspecht. All rights reserved.
//

import Foundation

enum SSError: Error {
    case errorOpeningPlist
    case insufficientFunds(coinsNeeded: Int)
    case genericError
}
