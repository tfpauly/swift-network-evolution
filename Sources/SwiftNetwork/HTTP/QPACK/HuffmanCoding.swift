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

    fileprivate struct _EncoderState {
        var remainingBits = 8
        var currentByte: UInt8 = 0
    }

    /// Returns the number of *bits* required to encode a given string.
    fileprivate static func huffmanEncodedBitLength(of bytes: some Collection<UInt8>) -> Int {
        let numberOfBits = bytes.reduce(0) { $0 + staticHuffmanTable[Int($1)].nbits }
        // round up to nearest multiple of 8 for EOS prefix
        return (numberOfBits + 7) & ~7
    }

    /// Returns the number of bytes required to encode a given string.
    package static func huffmanEncodedByteLength(of bytes: some Collection<UInt8>) -> Int {
        self.huffmanEncodedBitLength(of: bytes) / 8
    }

    /// Encodes the given string to the buffer, using QPACK Huffman encoding.
    ///
    /// - Parameter stringBytes: The string data to encode.
    package mutating func huffmanEncodedString(_ value: String) {
        let utf8 = value.utf8

        var state = _EncoderState()
        for byte in utf8 {
            self.huffmanEntry(staticHuffmanTable[Int(byte)], state: &state)
        }

        if state.remainingBits > 0 && state.remainingBits < 8 {
            // set all remaining bits of the last byte to 1
            state.currentByte |= UInt8(1 << state.remainingBits) - 1
            self.uint8(state.currentByte)
        }
    }

    fileprivate mutating func huffmanEntry(_ entry: HuffmanTableEntry,
                                           state: inout _EncoderState) {
        // will it fit as-is?
        if entry.nbits == state.remainingBits {
            state.currentByte |= UInt8(entry.bits)
            self.uint8(state.currentByte)
            state.currentByte = 0
            state.remainingBits = 8
        } else if entry.nbits < state.remainingBits {
            let diff = state.remainingBits - entry.nbits
            state.currentByte |= UInt8(entry.bits << diff)
            state.remainingBits -= entry.nbits
        } else {
            var (code, nbits) = entry

            nbits -= state.remainingBits
            state.currentByte |= UInt8(code >> nbits)
            self.uint8(state.currentByte)
            state.currentByte = 0

            if nbits & 0x7 != 0 {
                // align code to MSB
                code <<= 8 - (nbits & 0x7)
            }

            // we can short-circuit if less than 8 bits are remaining
            if nbits < 8 {
                state.currentByte = UInt8(truncatingIfNeeded: code)
                state.remainingBits = 8 - nbits
                return
            }

            // longer path for larger amounts
            switch nbits {
            case _ where nbits > 24:
                self.uint8(UInt8(truncatingIfNeeded: code >> 24))
                state.currentByte = UInt8(truncatingIfNeeded: code >> 24)
                nbits -= 8
                fallthrough
            case _ where nbits > 16:
                self.uint8(UInt8(truncatingIfNeeded: code >> 16))
                nbits -= 8
                fallthrough
            case _ where nbits > 8:
                self.uint8(UInt8(truncatingIfNeeded: code >> 8))
                nbits -= 8
            default:
                break
            }

            if nbits == 8 {
                self.uint8(UInt8(truncatingIfNeeded: code))
                state.currentByte = 0
                state.remainingBits = 8
            } else {
                state.remainingBits = 8 - nbits
                state.currentByte = UInt8(truncatingIfNeeded: code)
            }
        }
    }
}

extension Deserializer where Factory: ~Escapable {

    /// Decodes a huffman-encoded string
    /// - Parameters:
    ///   - length: The number of huffman-encoded octets to read.
    mutating func huffmanEncodedString(_ value: inout String, length: Int) throws(DeserializationError) {
        if length == 0 {
            value = ""
            return
        }

        let capacity = length * QPACKConstants.huffmanMaxCompressionRatio

        value = try String(unsafeUninitializedCapacity: capacity) { backingStorage throws(DeserializationError) in
            var state: UInt8 = 0

            // We do unchecked math on offset. Offset is strictly unable to get any larger than `length * 2`,
            // and we already did checked multiplication on that value.
            var offset = 0
            var acceptable = false

            var ch: UInt8 = 0
            for index in 0..<length {
                try self.uint8(&ch)

                var t = HuffmanDecoderTable.shared[state: state, nybble: ch >> 4]
                if t.flags.contains(.failure) {
                    throw .parsingFailed
                }
                if t.flags.contains(.symbol) {
                    backingStorage[offset] = t.sym
                    offset &+= 1
                }

                t = HuffmanDecoderTable.shared[state: t.state, nybble: ch & 0xf]
                if t.flags.contains(.failure) {
                    throw .parsingFailed
                }
                if t.flags.contains(.symbol) {
                    backingStorage[offset] = t.sym
                    offset &+= 1
                }

                state = t.state
                acceptable = t.flags.contains(.accepted)
            }

            guard acceptable else {
                throw .parsingFailed
            }

            return offset
        }
    }
}
