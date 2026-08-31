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

extension FrameSerializer {
    /// Write a string to this buffer, encoded for QPACK.
    /// The prefix must be between 2 and 8
    /// Parameters:
    /// - preferHuffmanEncoding: If true, huffman encoding will be used only if it will save space. If false, huffman encoding will not be used.
    /// - prefix: The number of bits in the first byte leave before starting the string
    /// - prefixBits: The bits to use in the first byte before the string begins.
    mutating func qpackEncodedString(_ string: String,
                                     preferHuffmanEncoding: Bool,
                                     prefix: Int,
                                     prefixBits: UInt8 = 0) {
        /// RFC 9204 4.1.2: The prefix size, N, can have a value between 2 and 8, inclusive. The remainder of the string literal is unmodified.
        precondition(prefix >= 2)
        precondition(prefix <= 8)
        let utf8 = string.utf8

        enum Encoding {
            case huffman(encodedByteLength: Int)
            case raw
        }

        // Using an enum to capture whether or not to use huffman AND the byte length means we avoid calculating the byte length again later
        let encoding: Encoding
        if preferHuffmanEncoding {
            let huffmanEncodedByteLength = Self.huffmanEncodedByteLength(of: utf8)
            let unencodedByteLength = utf8.count
            // Huffman coding is usually, but not always, more space-efficient. It is optimised for regular ASCII range.
            if huffmanEncodedByteLength < unencodedByteLength {
                encoding = .huffman(encodedByteLength: huffmanEncodedByteLength)
            } else {
                encoding = .raw
            }
        } else {
            encoding = .raw
        }

        // encode the value
        switch encoding {
        case .huffman(let encodedByteLength):
            let huffmanMask = UInt8(truncatingIfNeeded: 1 &<< (prefix - 1))
            // the prefix is now one bit less (one-bit huffman encoding flag)
            self.qpackPrefixedInteger(encodedByteLength,
                                      prefix: prefix - 1,
                                      prefixBits: huffmanMask | prefixBits)
            self.huffmanEncodedString(string)
        case .raw:
            // One bit is used for the Huffman flag (0)
            // So the prefix is reduced by one
            let byteCount = utf8.count
            self.qpackPrefixedInteger(byteCount, prefix: prefix - 1, prefixBits: prefixBits)
            self.fixedLengthUTF8(string, byteCount: byteCount)
        }
    }

}

extension Deserializer where Factory: ~Escapable {
    package mutating func qpackEncodedString(_ value: inout String,
                                             prefix: Int,
                                             firstByte: UInt8? = nil) throws(DeserializationError) {
        /// RFC 9204 4.1.2: The prefix size, N, can have a value between 2 and 8, inclusive. The remainder of the string literal is unmodified.
        precondition(prefix >= 2)
        precondition(prefix <= 8)

        // read the first byte to get the encoding bit
        var initialByte: UInt8 = 0
        try self.uint8(&initialByte)

        // We are using huffman encoding if the first bit after the prefix is 1
        // E.g. is prefix is 4, then the 5th bit represents huffman coding
        // so in that case we would & 0b00001000
        let huffmanMask = UInt8(truncatingIfNeeded: 1 &<< (prefix - 1))
        let huffmanEncoded = initialByte & huffmanMask == huffmanMask

        // read the length; the prefix is now one bit less (one-bit encoding flag above)
        var lengthInt = 0
        try self.qpackPrefixedInteger(&lengthInt, prefix: prefix - 1, firstByte: initialByte)

        if huffmanEncoded {
            try self.huffmanEncodedString(&value, length: lengthInt)
        } else {
            try self.fixedLengthUTF8(&value, byteCount: lengthInt)
        }
    }
}
