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

private let valueMask: UInt8 = 127
private let continuationMask: UInt8 = 128

extension FrameSerializer {
    /// Encodes an integer value using the format defined in RFC 9204 § 4.1.1.
    ///
    /// - Parameters:
    ///   - value: The integer value to encode.
    ///   - prefix: The number of bits available for use in the first byte at `buffer`.
    ///   - prefixBits: Existing bits to place in that first byte of `buffer` before encoding `value`.
    mutating func qpackPrefixedInteger<Integer: FixedWidthInteger>(_ value: Integer,
                                                                   prefix: Int,
                                                                   prefixBits: UInt8 = 0) {
        assert(prefix <= 8)
        assert(prefix >= 1)
        precondition(value >= 0, "Negative integers cannot be encoded in QPACK.")

        // The prefix is always hard-coded, and must fit within 8, so unchecked math here is definitely safe.
        let k = (1 &<< prefix) &- 1
        var initialByte = prefixBits

        if value < k {
            // it fits already!
            initialByte |= UInt8(truncatingIfNeeded: value)
            self.uint8(initialByte)
            return
        }

        // if it won't fit in this byte altogether, fill in all the remaining bits and move
        // to the next byte.
        initialByte |= UInt8(truncatingIfNeeded: k)
        self.uint8(initialByte)

        // deduct the initial [prefix] bits from the value, then encode it seven bits at a time into
        // the remaining bytes.
        // We can safely use unchecked subtraction here: we know that `k` is zero or greater, and that `value` is
        // either the same value or greater. As a result, this can be unchecked: it's always safe.
        var n = value &- Integer(k)
        while n >= 128 {
            let nextByte = (1 << 7) | UInt8(truncatingIfNeeded: n & 0x7f)
            self.uint8(nextByte)
            n >>= 7
        }

        self.uint8(UInt8(truncatingIfNeeded: n))
    }
}

extension Deserializer where Factory: ~Escapable {
    /// Reads an integer encoded using the format defined in RFC 9204 § 4.1.1.
    /// - Precondition: The prefix MUST be between 1 and 8 inclusive.
    /// - Throws: DeserializationError if the result doesn't fit or doesn't parse
    mutating func qpackPrefixedInteger<Integer: FixedWidthInteger>(_ value: inout Integer,
                                                                   prefix: Int,
                                                                   firstByte: UInt8? = nil) throws(DeserializationError) {
        guard (1...8).contains(prefix) else {
            preconditionFailure("Prefixed integer must have a prefix between 1 and 8")
        }

        // See RFC 7541 § 5.1 for details of the encoding/decoding.

        // The shifting and arithmetic operate on 'Int' and prefix is 1...8, so these unchecked operations are
        // fine and the result must fit in a UInt8.
        let prefixMask = UInt8(truncatingIfNeeded: (1 &<< prefix) &- 1)
        var prefixBits = UInt8(0)
        if let firstByte {
            prefixBits = firstByte
        } else {
            try self.uint8(&prefixBits)
        }
        prefixBits &= prefixMask

        var accumulator = Integer(prefixBits)

        if prefixBits != prefixMask {
            // The prefix bits aren't all '1', so they represent the whole value, we're done.
            value = accumulator
            return
        }

        // for the remaining bytes, as long as the top bit is set, consume the low seven bits.
        var shift = 0
        var byte: UInt8 = 0

        repeat {
            var byte = UInt8(0)
            try self.uint8(&byte)

            let value = Integer(byte & valueMask)

            // The shift cannot overflow: the value of 'shift' is strictly less than 'Int.bitWidth'.
            let (multiplicationResult, multiplicationOverflowed) = value.multipliedReportingOverflow(by: 1 &<< shift)
            if multiplicationOverflowed {
                throw .parsingFailed
            }

            let (additionResult, additionOverflowed) = accumulator.addingReportingOverflow(multiplicationResult)
            if additionOverflowed {
                throw .parsingFailed
            }

            accumulator = additionResult

            // Unchecked is fine, there's no chance of it overflowing given the possible values of 'Int.bitWidth'.
            shift &+= 7
            if shift >= Int.bitWidth {
                throw .parsingFailed
            }
        } while byte & continuationMask == continuationMask

        value = accumulator
    }
}
