//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

extension String {
    @inlinable
    static func _backportUnsafeUninitializedCapacity(
        _ capacity: Int,
        initializingUTF8With initializer: (_ buffer: UnsafeMutableBufferPointer<UInt8>) throws -> Int
    ) rethrows -> String {
        // The buffer will store zero terminated C string
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity + 1)
        defer {
            buffer.deallocate()
        }

        let initializedCount = try initializer(buffer)
        precondition(initializedCount <= capacity, "Overran buffer in initializer!")

        // add zero termination
        buffer[initializedCount] = 0

        return String(cString: buffer.baseAddress!)
    }
}

extension String {
    @inlinable
    init(
        customUnsafeUninitializedCapacity capacity: Int,
        initializingUTF8With initializer: (
            _ buffer: UnsafeMutableBufferPointer<UInt8>
        ) throws -> Int
    ) rethrows {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, macCatalyst 14.0, *) {
            try self.init(
                unsafeUninitializedCapacity: capacity,
                initializingUTF8With: initializer
            )
        } else {
            self = try Self._backportUnsafeUninitializedCapacity(
                capacity,
                initializingUTF8With: initializer
            )
        }
    }
}
