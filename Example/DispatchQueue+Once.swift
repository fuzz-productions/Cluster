// DispatchQueue+Once.swift
// Cluster
//
// Created by Nick Trienens on 2/6/20
// Copyright (c) 2020 Fuzzproductions  All rights reserved.
//

import Foundation

public extension DispatchQueue {
    private static var _onceTracker = [String]()

    class func once(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () -> Void
    ) {
        let token = "\(file):\(function):\(line)"
        once(token: token, block: block)
    }

    /**
     Executes a block of code, associated with a unique token, only once.  The code is thread safe and will
     only execute the code once even in the presence of multithreaded calls.

     - parameter token: A unique reverse DNS style name such as com.vectorform.<name> or a GUID
     - parameter block: Block to execute once
     */
    class func once(
        token: String,
        block: () -> Void
    ) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard !_onceTracker.contains(token) else { return }

        _onceTracker.append(token)
        block()
    }

    /**
     Executes a block of code, associated with a unique token, only once.  The code is thread safe and will
     only execute the code once even in the presence of multithreaded calls.

     - parameter token: A unique reverse DNS style name such as com.vectorform.<name> or a GUID
     - parameter block: Block to execute once
     */
    class func once(
        in interval: Double,
        token: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () -> Void
    ) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        let tokenToUse = token ?? "\(file):\(function):\(line)"

        guard !_onceTracker.contains(tokenToUse) else { return }

        _onceTracker.append(tokenToUse)
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            _onceTracker.removing(tokenToUse)
        }
        block()
    }
}

extension Array where Iterator.Element: Equatable {

    mutating func removing(_ item: Iterator.Element) {
        if let ind = firstIndex(of: item) {
            remove(at: ind)
        }
    }
}
