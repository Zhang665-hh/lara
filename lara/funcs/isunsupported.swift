//
//  isunsupported.swift
//  lara
//
//  Created by ruter on 30.03.26.
//

import UIKit
import Darwin

func devicemachine() -> String {
    var sysinfo = utsname()
    uname(&sysinfo)

    let mirror = Mirror(reflecting: sysinfo.machine)
    return mirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func hasmie() -> Bool {
    let machine = devicemachine()
    
    if machine.contains("iPhone18,") {
        return true
    }
    
    return false
}

func isunsupported() -> Bool {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    
    if v.majorVersion < 16 {
        return true
    }
    
    // Match README support matrix: iOS 18.7.2+ is not supported.
    if v.majorVersion == 18 {
        if v.minorVersion > 7 { return true }
        if v.minorVersion == 7 && v.patchVersion >= 2 { return true }
    }
    
    // iOS 19–25 are outside the documented support window.
    if v.majorVersion >= 19 && v.majorVersion <= 25 {
        return true
    }
    
    if v.majorVersion > 26 {
        return true
    }
    
    if v.majorVersion == 26 {
        if v.minorVersion > 0 { return true }
        if v.minorVersion == 0 && v.patchVersion > 1 { return true }
    }
    
    if hasmie() {
        return true
    }
    
    if isdebugged() {
        return true
    }
    
    return false
}
