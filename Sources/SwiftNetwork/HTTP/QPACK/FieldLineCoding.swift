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

/// Represents a FieldSectionPrefix as per RFC 9204 § 4.5.1.
package struct FieldSectionPrefix: Sendable, Hashable {
    package let requiredInsertCount: Int
    package let base: Int

    package init(requiredInsertCount: Int, base: Int) {
        precondition(base >= 0)
        self.requiredInsertCount = requiredInsertCount
        self.base = base
    }

    package func encode(maxCapacity: Int) -> EncodedFieldSectionPrefix {
        // 4.5.1.1.
        // The encoder transforms the Required Insert Count as follows before encoding:
        // if ReqInsertCount == 0:
        //     EncInsertCount = 0
        // else:
        //     EncInsertCount = (ReqInsertCount mod (2 * MaxEntries)) + 1
        // Where MaxEntries = floor( MaxTableCapacity / 32 )
        if self.requiredInsertCount == 0 {
            return .init(encodedRequiredInsertCount: 0, deltaBase: self.base, signBit: false)
        }
        let maxEntries = maxCapacity / 32
        let encodedRequiredInsertCount = (requiredInsertCount % (2 * maxEntries)) + 1
        let deltaBase: Int
        let signBit: Bool
        if self.base >= self.requiredInsertCount {
            signBit = false
            deltaBase = self.base - self.requiredInsertCount
        } else {
            deltaBase = self.requiredInsertCount - self.base - 1
            signBit = true
        }
        return .init(encodedRequiredInsertCount: encodedRequiredInsertCount, deltaBase: deltaBase, signBit: signBit)
    }
}

/// Represents an EncodedFieldSectionPrefix as per RFC 9204 § 4.5.1.
/// Here, the requiredInsertCount is stored with an encoding as per RFC 9204 § 4.5.1.1.
/// The deltaBase can be used to get the base relative to the decoded requiredInsertCount.
package struct EncodedFieldSectionPrefix: Sendable, Hashable {
    package let encodedRequiredInsertCount: Int
    package let deltaBase: Int
    /// If true, the base is encodedRequiredInsertCount - deltaBase - 1. Otherwise base is encodedRequiredInsertCount + deltaBase.
    package let signBit: Bool

    package init(encodedRequiredInsertCount: Int, deltaBase: Int, signBit: Bool) {
        self.encodedRequiredInsertCount = encodedRequiredInsertCount
        self.deltaBase = deltaBase
        self.signBit = signBit
    }

    package func decode(totalInserts: Int, maxCapacity: Int) -> FieldSectionPrefix? {
        // 4.5.1.1.
        // FullRange = 2 * MaxEntries
        // if EncodedInsertCount == 0:
        //     ReqInsertCount = 0
        // else:
        // if EncodedInsertCount > FullRange:
        //     Error
        // MaxValue = TotalNumberOfInserts + MaxEntries
        //
        // # MaxWrapped is the largest possible value of
        // # ReqInsertCount that is 0 mod 2 * MaxEntries
        // MaxWrapped = floor(MaxValue / FullRange) * FullRange
        // ReqInsertCount = MaxWrapped + EncodedInsertCount - 1
        //
        // # If ReqInsertCount exceeds MaxValue, the Encoder's value
        // # must have wrapped one fewer time
        // if ReqInsertCount > MaxValue:
        //     if ReqInsertCount <= FullRange:
        //         Error
        //     ReqInsertCount -= FullRange
        //
        // # Value of 0 must be encoded as 0.
        // if ReqInsertCount == 0:
        //     Error
        if self.encodedRequiredInsertCount == 0 {
            return .init(requiredInsertCount: 0, base: self.deltaBase)
        }
        let maxEntries = maxCapacity / 32
        let fullRange = 2 * maxEntries
        if self.encodedRequiredInsertCount > fullRange {
            return nil
        }
        let maxValue = totalInserts + maxEntries
        // MaxWrapped is the largest possible value of ReqInsertCount that is 0 mod 2 * MaxEntries
        let maxWrapped = (maxValue / fullRange) * fullRange
        var reqInsertCount = maxWrapped + self.encodedRequiredInsertCount - 1
        // If ReqInsertCount exceeds MaxValue, the Encoder's value must have wrapped one fewer time
        if reqInsertCount > maxValue {
            if reqInsertCount <= fullRange {
                return nil
            }
            reqInsertCount -= fullRange
        }
        // Value of 0 must be encoded as 0.
        if reqInsertCount == 0 {
            return nil
        }
        let base: Int
        if self.signBit {
            base = reqInsertCount - self.deltaBase - 1
        } else {
            base = reqInsertCount + self.deltaBase
        }
        if base < 0 {
            // RFC 9204 § 4.5.1.2: The value of Base MUST NOT be negative.
            // Though the protocol might operate correctly with a negative Base using post-Base indexing, it is unnecessary and inefficient.
            // An endpoint MUST treat a field block with a Sign bit of 1 as invalid if the value of Required Insert Count is less than or equal to the value of Delta Base.
            return nil
        }
        return .init(requiredInsertCount: reqInsertCount, base: base)
    }
}

/// Represents a single field line as per RFC 9204 § 4.5.
package enum FieldLine: Sendable, Hashable {
    /// 4.5.2. Indexed Field Line.
    case indexed(QPACKReferenceTable, index: Int)
    /// 4.5.3. Indexed Field Line with Post-Base Index.
    case indexedWithPostBase(index: Int)
    /// 4.5.4. Literal Field Line with Name Reference.
    case literalWithNameReference(
        requireLiteralRepresentation: Bool,
        table: QPACKReferenceTable,
        index: Int,
        value: String
    )
    /// 4.5.5. Literal Field Line with Post-Base Name Reference.
    case literalWithNameReferenceWithPostBase(requireLiteralRepresentation: Bool, index: Int, value: String)
    /// 4.5.6. Literal Field Line with Literal Name.
    case literal(requireLiteralRepresentation: Bool, name: String, value: String)
}

/// Represents a full field section as per RFC 9204 § 4.5.
package struct FieldSection: Sendable, Hashable {
    /// The field section prefix.
    package var prefix: EncodedFieldSectionPrefix
    /// Each line of the field section. A line represents a header.
    package var lines: [FieldLine]

    package init(prefix: EncodedFieldSectionPrefix, lines: [FieldLine]) {
        self.prefix = prefix
        self.lines = lines
    }
}

extension Deserializer where Factory: ~Escapable {
    package mutating func qpackFieldLine(_ value: inout FieldLine) throws(DeserializationError) {
        var firstByte: UInt8 = 0
        try self.uint8(&firstByte)

        if firstByte & 0x80 == 0x80 {
            // First bit is 1. This is an Indexed Field Line
            // The 2nd bit represents static table (1) or dynamic table (0)
            let table = QPACKReferenceTable.staticIfTrue(firstByte & 0x40 == 0x40)
            // Remaining 6 bits are start of the integer for the relative index
            var relativeIndex = 0
            try self.qpackPrefixedInteger(&relativeIndex, prefix: 6, firstByte: firstByte)
            value = FieldLine.indexed(table, index: relativeIndex)
        } else if firstByte & 0x40 == 0x40 {
            // First 2 bits are 01. This is Literal Field Line with Name Reference
            // 3rd bit is N, if set then the encoded field line MUST always be encoded with a literal representation
            let requireLiteralRepresentation = firstByte & 0x20 == 0x20
            // 4th bit represents static table (1) or dynamic table (0)
            let table = QPACKReferenceTable.staticIfTrue(firstByte & 0x10 == 0x10)
            // Next 4 bits are the start of the index int
            var index = 0
            try self.qpackPrefixedInteger(&index, prefix: 4, firstByte: firstByte)
            var valueString = ""
            try self.qpackEncodedString(&valueString, prefix: 8)
            value = FieldLine.literalWithNameReference(
                requireLiteralRepresentation: requireLiteralRepresentation,
                table: table,
                index: index,
                value: valueString
            )
        } else if firstByte & 0x20 == 0x20 {
            // First 3 bits are 001. This is Literal Field Line with Literal Name
            // 4th bit is N, if set then the encoded field line MUST always be encoded with a literal representation
            let requireLiteralRepresentation = firstByte & 0x10 == 0x10
            var name = ""
            try self.qpackEncodedString(&name, prefix: 4, firstByte: firstByte)
            var valueString = ""
            try self.qpackEncodedString(&valueString, prefix: 8, firstByte: firstByte)
            value = FieldLine.literal(
                requireLiteralRepresentation: requireLiteralRepresentation,
                name: name,
                value: valueString
            )
        } else if firstByte & 0x10 == 0x10 {
            // First 4 bits are 0001. This is Indexed Field Line with Post-Base Index
            // Remaining 4 bits are start of the integer for the relative index of the dynamic table
            var relativeIndex = 0
            try self.qpackPrefixedInteger(&relativeIndex, prefix: 4, firstByte: firstByte)
            value = FieldLine.indexedWithPostBase(index: relativeIndex)
        } else {
            // First 4 bits are 0000. This is Literal Field Line with Post-Base Name Reference
            // 5th bit is N, if set then the encoded field line MUST always be encoded with a literal representation
            let requireLiteralRepresentation = firstByte & 0x8 == 0x8
            // Remaining 4 bits are start of the integer for the post-base index of the dynamic table
            var index = 0
            try self.qpackPrefixedInteger(&index, prefix: 3, firstByte: firstByte)
            var valueString = ""
            try self.qpackEncodedString(&valueString, prefix: 8)
            value = FieldLine.literalWithNameReferenceWithPostBase(
                requireLiteralRepresentation: requireLiteralRepresentation,
                index: index,
                value: valueString
            )
        }

    }
}

extension FrameSerializer {
    /// Write a single ``FieldLine`` to this buffer.
    /// - Parameters:
    ///   - fieldLine: The line to write.
    ///   - preferHuffmanEncoding: Whether to use huffman coding for strings (where applicable and where it would be more efficient to do so).
    package mutating func qpackFieldLine(_ fieldLine: FieldLine, preferHuffmanEncoding: Bool) {
        switch fieldLine {
        case .indexed(let table, let index):
            // First bit is 1. Then T. Then index
            let t = table == .staticTable ? UInt8.maskForBit(bit: 2) : 0
            let prefixBits = t | 0x80
            self.qpackPrefixedInteger(index, prefix: 6, prefixBits: prefixBits)
        case .indexedWithPostBase(let index):
            // First 4 bits are 0001. Then index
            self.qpackPrefixedInteger(index, prefix: 4, prefixBits: 0x10)
        case .literalWithNameReference(let requireLiteralRepresentation, let table, let index, let value):
            // First 2 bits are 01. Then N. Then T. Then index. Then value
            // When the 'N' bit is set, the encoded field line MUST always be encoded with a literal representation
            let n = requireLiteralRepresentation ? UInt8.maskForBit(bit: 3) : 0
            let t = table == .staticTable ? UInt8.maskForBit(bit: 4) : 0
            let prefixBits = n | t | 0x40
            self.qpackPrefixedInteger(index, prefix: 4, prefixBits: prefixBits)
            self.qpackEncodedString(value, preferHuffmanEncoding: preferHuffmanEncoding, prefix: 8)
        case .literalWithNameReferenceWithPostBase(let requireLiteralRepresentation, let index, let value):
            // First 4 bits are 0000. Then N. Then index. Then value
            // // When the 'N' bit is set, the encoded field line MUST always be encoded with a literal representation
            let prefixBits = requireLiteralRepresentation ? UInt8.maskForBit(bit: 5) : 0
            self.qpackPrefixedInteger(index, prefix: 3, prefixBits: prefixBits)
            self.qpackEncodedString(value, preferHuffmanEncoding: preferHuffmanEncoding, prefix: 8)
        case .literal(let requireLiteralRepresentation, let name, let value):
            // First 3 bits are 001. Then N. Then name. Then value
            // // When the 'N' bit is set, the encoded field line MUST always be encoded with a literal representation
            let n = requireLiteralRepresentation ? UInt8.maskForBit(bit: 4) : 0
            let prefixBits = n | 0x20
            self.qpackEncodedString(
                name,
                preferHuffmanEncoding: preferHuffmanEncoding,
                prefix: 4,
                prefixBits: prefixBits
            )
            self.qpackEncodedString(value, preferHuffmanEncoding: preferHuffmanEncoding, prefix: 8)
        }
    }
}

extension ByteBuffer {

    /// Read a single ``FieldSectionPrefix`` from this `ByteBuffer`.
    /// - Returns: The section, or nil if it cannot be decoded.
    package mutating func readFieldSectionPrefix() throws(IntegerReadingError) -> EncodedFieldSectionPrefix? {
        guard let result = try self.getFieldSectionPrefix(at: self.readerIndex) else { return nil }
        self.moveReaderIndex(forwardBy: result.bytesRead)
        return result.value
    }

    private func getFieldSectionPrefix(
        at startIndex: Int
    ) throws(IntegerReadingError) -> Decoded<EncodedFieldSectionPrefix>? {
        guard let requiredInsertCount = try self.getQPACKPrefixedInteger(as: Int.self, at: startIndex, withPrefix: 8)
        else {
            return nil
        }

        guard let signByte = self.getInteger(at: startIndex + requiredInsertCount.bytesRead, as: UInt8.self) else {
            return nil
        }
        // 4.5.1.2  the Base is encoded relative to the Required Insert Count using a one-bit sign
        let signBitMask = UInt8.maskForBit(bit: 1)
        let signBit = signBitMask & signByte == signBitMask
        guard
            let deltaBase = try self.getQPACKPrefixedInteger(
                as: Int.self,
                at: startIndex + requiredInsertCount.bytesRead,
                withPrefix: 7
            )
        else {
            return nil
        }

        let bytesRead = requiredInsertCount.bytesRead + deltaBase.bytesRead
        return .init(
            value: .init(
                encodedRequiredInsertCount: requiredInsertCount.value,
                deltaBase: deltaBase.value,
                signBit: signBit
            ),
            bytesRead: bytesRead
        )
    }

    /// Write a single ``FieldSectionPrefix`` to this buffer.
    /// - Parameters
    ///   - prefix: The ``FieldSectionPrefix`` to write.
    ///   - maxCapacity: The maximum capacity of the dynamic table.
    /// - Returns: The number of bytes written.
    @discardableResult
    package mutating func writeFieldSectionPrefix(_ prefix: EncodedFieldSectionPrefix) -> Int {
        var bytesWritten = 0
        bytesWritten += self.writeQPACKPrefixedInteger(
            prefix.encodedRequiredInsertCount,
            prefix: 8
        )
        let signBit = prefix.signBit ? UInt8.maskForBit(bit: 1) : 0
        bytesWritten += self.writeQPACKPrefixedInteger(prefix.deltaBase, prefix: 7, prefixBits: signBit)
        return bytesWritten
    }

    package mutating func readFieldSection() throws(IntegerReadingError) -> FieldSection? {
        guard let prefix = try self.readFieldSectionPrefix() else {
            return nil
        }
        var lines = [FieldLine]()
        lines.reserveCapacity(QPACKConstants.defaultFieldLinesCapacity)
        while let l = try self.readFieldLine() {
            lines.append(l)
        }
        return FieldSection(prefix: prefix, lines: lines)
    }
}

extension UInt8 {
    /// Returns a mask for getting the nth bit.
    ///
    /// E.g. calling this function with a parameter of 1 returns 0b10000000.
    ///
    /// E.g. calling this function with a parameter of 2 returns 0b01000000.
    ///
    /// E.g. calling this function with a parameter of 8 returns 0b00000001.
    /// - Parameter bit: The bit number desired.
    /// - Returns: The mask.
    fileprivate static func maskForBit(bit: Int) -> Self {
        UInt8(truncatingIfNeeded: 1 &<< (8 - bit))
    }
}
