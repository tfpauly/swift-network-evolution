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
    /// Encode a single ``QPACKEncoderInstruction``
    /// - Parameters:
    ///   - instruction: The instruction to encode.
    ///   - preferHuffmanEncoding: Whether to use huffman coding for strings (where applicable and more efficient to do so).
    package mutating func qpackEncoderInstruction(_ instruction: QPACKEncoderInstruction, preferHuffmanEncoding: Bool) {
        switch instruction {
        case .setDynamicTableCapacity(let capacity):
            self.qpackPrefixedInteger(capacity, prefix: 5, prefixBits: 0x20)
        case .insertWithNameReference(let table, let relativeIndex, let value):
            // 1st bit is 1
            // 2nd bit represents static table (1) or dynamic table (0)
            let prefixBits: UInt8
            switch table {
            case .staticTable:
                prefixBits = 0xC0  // 11
            case .dynamicTable:
                prefixBits = 0x80  // 10
            }
            self.qpackPrefixedInteger(relativeIndex, prefix: 6, prefixBits: prefixBits)
            self.qpackEncodedString(value, preferHuffmanEncoding: preferHuffmanEncoding, prefix: 8)
        case .insertWithLiteralName(let name, let value):
            self.qpackEncodedString(name, preferHuffmanEncoding: preferHuffmanEncoding, prefix: 6, prefixBits: 0x40)
            self.qpackEncodedString(value, preferHuffmanEncoding: preferHuffmanEncoding, prefix: 8)
        case .duplicateEntry(let relativeIndex):
            self.qpackPrefixedInteger(relativeIndex, prefix: 5, prefixBits: 0)
        }
    }

    /// Encode a single ``QPACKDecoderInstruction``
    /// - Parameter instruction: The instruction to encode.
    package mutating func qpackDecoderInstruction(_ instruction: QPACKDecoderInstruction) {
        switch instruction {
        case .sectionAcknowledgement(let streamID):
            // Start with a 1, then a 7-bit prefix integer
            self.qpackPrefixedInteger(streamID, prefix: 7, prefixBits: 0x80)
        case .streamCancellation(let streamID):
            // Start with 01, then a 6-bit prefix integer
            self.qpackPrefixedInteger(streamID, prefix: 6, prefixBits: 0x40)
        case .insertCountIncrement(let increment):
            // Start with 00, then a 6-bit prefix integer
            self.qpackPrefixedInteger(increment, prefix: 6, prefixBits: 0)
        }
    }
}

extension Deserializer where Factory: ~Escapable {
    /// Read a single ``QPACKEncoderInstruction``
    /// Moves the reader index to the end of the instruction.
    /// If a valid instruction can't be formed, returns nil and leaves the reader index as it was.
    package mutating func qpackEncoderInstruction(_ instruction: inout QPACKEncoderInstruction) throws(DeserializationError) {
        var firstByte: UInt8 = 0
        try self.uint8(&firstByte)
        if firstByte & 0x80 == 0x80 {
            // First bit is 1. This is insertWithNameReference
            // The 2nd bit represents static table (1) or dynamic table (0)
            let table = QPACKReferenceTable.staticIfTrue(firstByte & 0x40 == 0x40)
            // Remaining 6 bits are start of the integer for the relative index

            // Integers always end on a byte boundary
            var relativeIndex = 0
            try self.qpackPrefixedInteger(&relativeIndex, prefix: 6, firstByte: firstByte)

            var value = ""
            try self.qpackEncodedString(&value, prefix: 8)

            instruction = .insertWithNameReference(table, relativeIndex: relativeIndex, value: value)
        } else if firstByte & 0x40 == 0x40 {
            // Second bit is 1, i.e we begin with a 01 pattern. This is insertWithLiteralName
            var name = ""
            try self.qpackEncodedString(&name, prefix: 6, firstByte: firstByte)

            var value = ""
            try self.qpackEncodedString(&value, prefix: 8)

            instruction = .insertWithLiteralName(name: name, value: value)
        } else if firstByte & 0x20 == 0x20 {
            // Third bit is 1, i.e. we begin with a 001 pattern. This is setDynamicTableCapacity
            var capacity = 0
            try self.qpackPrefixedInteger(&capacity, prefix: 5, firstByte: firstByte)
            instruction = .setDynamicTableCapacity(capacity)
        } else {
            // First 3 bits are 000. This is duplicate
            var relativeIndex = 0
            try self.qpackPrefixedInteger(&relativeIndex, prefix: 5, firstByte: firstByte)
            instruction = .duplicateEntry(relativeIndex: relativeIndex)
        }
    }

    /// Read a single ``QPACKDecoderInstruction``
    /// Moves the reader index to the end of the instruction.
    /// If a valid instruction can't be formed, returns nil and leaves the reader index as it was.
    package mutating func qpackDecoderInstruction(_ instruction: inout QPACKDecoderInstruction) throws(DeserializationError) {
        var firstByte: UInt8 = 0
        try self.uint8(&firstByte)

        let first2Bits = firstByte & 0xC0
        switch first2Bits {
        case 0:
            // Starts with 00
            // Remaining 6 bits are the increment
            var increment = 0
            try self.qpackPrefixedInteger(&increment, prefix: 6, firstByte: firstByte)
            instruction = .insertCountIncrement(increment: increment)
        case 0x40:
            // Starts with 01
            // Remaining 6 bits are the streamID
            var streamID: UInt64 = 0
            try self.qpackPrefixedInteger(&streamID, prefix: 6, firstByte: firstByte)
            instruction = .streamCancellation(streamID: streamID)
        default:
            // Starts with 1
            // Remaining 7 bits are the streamID
            var streamID: UInt64 = 0
            try self.qpackPrefixedInteger(&streamID, prefix: 7, firstByte: firstByte)
            instruction = .sectionAcknowledgement(streamID: streamID)
        }
    }
}
