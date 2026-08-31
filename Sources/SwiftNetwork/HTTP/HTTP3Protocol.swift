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

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(os)
internal import os
#endif

import HTTPTypes

// MARK: - H3 Frame Types

enum H3FrameType: UInt64 {
    case data = 0x00
    case headers = 0x01
    case cancelPush = 0x03
    case settings = 0x04
    case pushPromise = 0x05
    case goaway = 0x07
    case maxPushID = 0x0d
    case priorityUpdate = 0xf0700
    case priorityUpdatePush = 0xf0701
}

// MARK: - H3 Settings

enum H3SettingID: UInt64, Sendable {
    case qpackMaxTableCapacity  = 0x01
    case maxFieldSectionSize    = 0x06
    case qpackBlockedStreams    = 0x07
    case enableConnectProtocol  = 0x08
    case h3Datagram             = 0x33
    case h3DatagramLegacy       = 0x276
}

struct H3Settings: Equatable, Sendable {
    var qpackMaxTableCapacity: UInt64 = 0
    var maxFieldSectionSize: UInt64 = 65536
    var qpackBlockedStreams: UInt64 = 0
    var enableConnectProtocol: Bool = true
    var h3Datagram: Bool = true
    var h3DatagramLegacy: Bool = false

    init() {}

    /// (id, value) pairs emitted on the wire, in stable order.
    /// `h3DatagramLegacy` is only emitted when set since most peers don't
    /// recognize the draft ID 0x276.
    private var pairs: [(id: UInt64, value: UInt64)] {
        var p: [(id: UInt64, value: UInt64)] = []
        p.append((H3SettingID.qpackMaxTableCapacity.rawValue, qpackMaxTableCapacity))
        p.append((H3SettingID.maxFieldSectionSize.rawValue, maxFieldSectionSize))
        p.append((H3SettingID.qpackBlockedStreams.rawValue, qpackBlockedStreams))
        p.append((H3SettingID.enableConnectProtocol.rawValue, enableConnectProtocol ? 1 : 0))
        p.append((H3SettingID.h3Datagram.rawValue, h3Datagram ? 1 : 0))
        if h3DatagramLegacy {
            p.append((H3SettingID.h3DatagramLegacy.rawValue, 1))
        }
        return p
    }

    /// On-wire SETTINGS payload byte count (sum of VLE id + VLE value).
    var payloadByteCount: Int {
        pairs.reduce(0) { sum, pair in
            sum + pair.id.variableLengthSize + pair.value.variableLengthSize
        }
    }

    /// Encode the SETTINGS payload only (id/value pairs, no frame header).
    func encodePayload() -> FrameArray {
        let capacity = max(payloadByteCount, 8)
        return Serializer.serialize(frameCapacity: capacity) { write in
            for pair in pairs {
                write.vle(pair.id)
                write.vle(pair.value)
            }
        }
    }

    /// Encode the complete SETTINGS frame (type VLE + length VLE + payload).
    func encodeFrame() -> FrameArray {
        let payloadLen = UInt64(payloadByteCount)
        return Serializer.serialize(frameCapacity: 32) { write in
            write.vle(H3FrameType.settings.rawValue)
            write.vle(payloadLen)
            for pair in pairs {
                write.vle(pair.id)
                write.vle(pair.value)
            }
        }
    }

    /// Decode a SETTINGS payload from a Deserializer positioned at the start.
    /// `payloadByteCount` is the on-wire payload length from the SETTINGS
    /// frame's length VLE.
    ///
    /// Returns nil for protocol violations (caller should close with
    /// `HTTP3Error.HTTP3ErrorCode.settingsError`, or `frameError` for a truncated
    /// VLE pair): duplicate setting ID, boolean-valued setting > 1, or VLE
    /// pair extending past the declared payload boundary. Unknown IDs skipped.
    static func decodePayload<F: DeserializerSpanFactory & ~Copyable & ~Escapable>(
        from read: inout Deserializer<F>,
        payloadByteCount: Int
    ) -> H3Settings? {
        var s = H3Settings()
        var seen: Set<UInt64> = []
        var consumed = 0

        while consumed < payloadByteCount {
            var id: UInt64 = 0
            var idSize: Int = 0
            do {
                try read.vleWithSize(&id, &idSize)
            } catch {
                return nil
            }
            consumed += idSize
            if consumed > payloadByteCount { return nil }

            var value: UInt64 = 0
            var valSize: Int = 0
            do {
                try read.vleWithSize(&value, &valSize)
            } catch {
                return nil
            }
            consumed += valSize
            if consumed > payloadByteCount { return nil }

            guard seen.insert(id).inserted else {
                return nil
            }

            switch id {
            case H3SettingID.qpackMaxTableCapacity.rawValue:
                s.qpackMaxTableCapacity = value
            case H3SettingID.maxFieldSectionSize.rawValue:
                s.maxFieldSectionSize = value
            case H3SettingID.qpackBlockedStreams.rawValue:
                s.qpackBlockedStreams = value
            case H3SettingID.enableConnectProtocol.rawValue:
                guard value <= 1 else { return nil }
                s.enableConnectProtocol = (value != 0)
            case H3SettingID.h3Datagram.rawValue:
                guard value <= 1 else { return nil }
                s.h3Datagram = (value != 0)
            case H3SettingID.h3DatagramLegacy.rawValue:
                guard value <= 1 else { return nil }
                s.h3DatagramLegacy = (value != 0)
            default:
                break
            }
        }
        return s
    }

    /// Decode a SETTINGS payload from a byte buffer.
    static func decodePayload(_ bytes: borrowing [UInt8]) -> H3Settings? {
        var result: H3Settings? = nil
        let r = Deserializer.deserialize(bytes) { (read: inout Deserializer) throws(DeserializationError) in
            result = decodePayload(from: &read, payloadByteCount: bytes.count)
        }
        guard r.isValid else { return nil }
        return result
    }
}

// MARK: - H3 Header Field Encoding (Literal, No QPACK)

enum H3HeaderEncoding {

    static func encodeRequest(_ request: HTTPRequest) -> FrameArray {
        var headers: [(name: String, value: String)] = []
        headers.append((name: ":method", value: request.method.rawValue))
        if let scheme = request.scheme {
            headers.append((name: ":scheme", value: scheme))
        }
        if let authority = request.authority {
            headers.append((name: ":authority", value: authority))
        }
        if let path = request.path {
            headers.append((name: ":path", value: path))
        }
        if let proto = request.extendedConnectProtocol {
            headers.append((name: ":protocol", value: proto))
        }
        for field in request.headerFields {
            headers.append((name: field.name.rawName, value: field.value))
        }
        return encodeHeaderBlock(headers)
    }

    static func encodeResponse(_ response: HTTPResponse) -> FrameArray {
        var headers: [(name: String, value: String)] = []
        headers.append((name: ":status", value: String(response.status.code)))
        for field in response.headerFields {
            headers.append((name: field.name.rawName, value: field.value))
        }
        return encodeHeaderBlock(headers)
    }

    static func decodeRequest(_ payload: consuming FrameArray) -> HTTPRequest? {
        let headers = decodeHeaderBlock(consume payload)
        guard let method = headers.first(where: { $0.name == ":method" })?.value,
              let httpMethod = HTTPRequest.Method(method) else {
            return nil
        }
        var request = HTTPRequest(
            method: httpMethod,
            scheme: headers.first(where: { $0.name == ":scheme" })?.value,
            authority: headers.first(where: { $0.name == ":authority" })?.value,
            path: headers.first(where: { $0.name == ":path" })?.value
        )
        request.extendedConnectProtocol = headers.first(where: { $0.name == ":protocol" })?.value
        for field in headers where !field.name.hasPrefix(":") {
            if let fieldName = HTTPField.Name(field.name) {
                request.headerFields.append(HTTPField(name: fieldName, value: field.value))
            }
        }
        return request
    }

    static func decodeResponse(_ payload: consuming FrameArray) -> HTTPResponse? {
        let headers = decodeHeaderBlock(consume payload)
        guard let statusStr = headers.first(where: { $0.name == ":status" })?.value,
              let statusCode = Int(statusStr) else {
            return nil
        }
        var response = HTTPResponse(status: HTTPResponse.Status(code: statusCode))
        for field in headers where !field.name.hasPrefix(":") {
            if let fieldName = HTTPField.Name(field.name) {
                response.headerFields.append(HTTPField(name: fieldName, value: field.value))
            }
        }
        return response
    }

    private static func encodeHeaderBlock(_ headers: [(name: String, value: String)]) -> FrameArray {
        return Serializer.serialize(frameCapacity: 64) { write in
            write.uint8(0x00)
            write.uint8(0x00)
            for (name, value) in headers {
                let nameBytes = Array(name.utf8)
                let valueBytes = Array(value.utf8)
                // RFC 9204 §4.5.6 Literal Field Line With Literal Name; flags
                // 0x20 sets the 001 pattern with N=0, H=0.
                write.buffer(encodePrefixedInteger(nameBytes.count, prefixBits: 3, flags: 0x20))
                write.buffer(nameBytes)
                write.buffer(encodePrefixedInteger(valueBytes.count, prefixBits: 7, flags: 0x00))
                write.buffer(valueBytes)
            }
        }
    }

    private static func decodeHeaderBlock(_ payload: consuming FrameArray) -> [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = []
        var pl = payload

        // Skip the 2-byte QPACK header-block prefix.
        let prefix = Deserializer.deserialize(&pl, claim: true, removeClaimedFrames: true) {
            (read: inout Deserializer<FrameArraySpanFactory>) throws(DeserializationError) in
            try read.skip(2)
        }
        guard prefix.isValid else {
            pl.finalizeAllFramesAsFailed()
            return headers
        }

        // One Literal-with-Literal-Name entry per pass. Stops on empty or unknown pattern.
        while pl.unclaimedLength > 0 {
            var name = ""
            var value = ""
            let entry = Deserializer.deserialize(&pl, claim: true, removeClaimedFrames: true) {
                (read: inout Deserializer<FrameArraySpanFactory>) throws(DeserializationError) in
                var firstByte: UInt8 = 0
                try read.uint8(&firstByte)
                // Only the 001-pattern (Literal-with-Literal-Name) is supported.
                guard firstByte & 0xE0 == 0x20 else {
                    throw DeserializationError.parsingFailed
                }
                let nameLen = try readPrefixedIntegerRest(initial: firstByte,
                                                          prefixBits: 3, read: &read)
                try read.fixedLengthUTF8(&name, byteCount: nameLen)

                var firstValueByte: UInt8 = 0
                try read.uint8(&firstValueByte)
                let valueLen = try readPrefixedIntegerRest(initial: firstValueByte,
                                                            prefixBits: 7, read: &read)
                try read.fixedLengthUTF8(&value, byteCount: valueLen)
            }
            guard entry.isValid else { break }
            headers.append((name: name, value: value))
        }

        pl.finalizeAllFramesAsFailed()
        return headers
    }

    private static func readPrefixedIntegerRest<F: DeserializerSpanFactory & ~Copyable & ~Escapable>(
        initial: UInt8, prefixBits: Int,
        read: inout Deserializer<F>
    ) throws(DeserializationError) -> Int {
        let maxPrefix = (1 << prefixBits) - 1
        let prefixMask = UInt8(maxPrefix)
        let initialValue = Int(initial & prefixMask)
        if initialValue < maxPrefix {
            return initialValue
        }
        var value = initialValue
        var shift = 0
        while true {
            var byte: UInt8 = 0
            try read.uint8(&byte)
            value += Int(byte & 0x7F) << shift
            shift += 7
            if byte & 0x80 == 0 { break }
        }
        return value
    }

    private static func prefixedIntegerSize(_ value: Int, prefixBits: Int) -> Int {
        let maxPrefix = (1 << prefixBits) - 1
        if value < maxPrefix { return 1 }
        var size = 1
        var remaining = value - maxPrefix
        while remaining >= 128 {
            size += 1
            remaining >>= 7
        }
        return size + 1
    }

    private static func encodePrefixedInteger(_ value: Int, prefixBits: Int, flags: UInt8) -> [UInt8] {
        let maxPrefix = (1 << prefixBits) - 1
        if value < maxPrefix {
            return [flags | UInt8(value)]
        }
        var bytes: [UInt8] = [flags | UInt8(maxPrefix)]
        var remaining = value - maxPrefix
        while remaining >= 128 {
            bytes.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(remaining))
        return bytes
    }
}

// MARK: - H3 Request Stream Validator (RFC 9114 §4.1)
//
// Legal frame sequence on a request stream is HEADERS DATA* HEADERS?.
// Control-stream-only frames (SETTINGS, GOAWAY, CANCEL_PUSH, MAX_PUSH_ID)
// and PUSH_PROMISE (we don't implement push) are protocol errors here.
// Reserved / "grease" types (RFC 9114 §7.2.8) are silently dropped.

struct H3RequestStreamValidator: Sendable {
    enum State: Equatable, Sendable {
        case expectingHeaders          // initial — only HEADERS is valid
        case expectingDataOrTrailers   // after the request/response HEADERS
        case expectingTrailerOrEnd     // after at least one DATA frame
        case afterTrailers             // after the trailing HEADERS
    }

    private(set) var state: State = .expectingHeaders

    init() {}

    /// Update state for an incoming frame. Returns nil if allowed (and may
    /// update `state`); returns the violation code otherwise. Reserved /
    /// grease types return nil without state change.
    mutating func observe(frameType: UInt64) -> HTTP3Error.HTTP3ErrorCode? {
        // Frames forbidden on a request stream regardless of state.
        switch frameType {
        case H3FrameType.settings.rawValue,
             H3FrameType.goaway.rawValue,
             0x03,  // CANCEL_PUSH
             0x05,  // PUSH_PROMISE — we don't implement server push
             0x0D:  // MAX_PUSH_ID
            return .frameUnexpected
        default:
            break
        }

        switch frameType {
        case H3FrameType.headers.rawValue:
            switch state {
            case .expectingHeaders:
                state = .expectingDataOrTrailers
            case .expectingDataOrTrailers, .expectingTrailerOrEnd:
                state = .afterTrailers   // trailing HEADERS section
            case .afterTrailers:
                return .frameUnexpected
            }
        case H3FrameType.data.rawValue:
            switch state {
            case .expectingHeaders:
                return .frameUnexpected
            case .expectingDataOrTrailers, .expectingTrailerOrEnd:
                state = .expectingTrailerOrEnd
            case .afterTrailers:
                return .frameUnexpected
            }
        default:
            // Reserved / unknown — silently dropped per RFC 9114 §7.2.8.
            break
        }
        return nil
    }
}

// MARK: - H3 Request-Stream Codec
//
// Outbound HEADERS / DATA encoders, inbound parser + validator, and
// HTTPRequest/HTTPResponse materialization for one request stream.

struct H3RequestStreamCodec: ~Copyable {
    enum Role: Sendable {
        /// Local peer is the client: encodes requests, decodes HEADERS as `HTTPResponse`.
        case client
        /// Local peer is the server: encodes responses, decodes HEADERS as `HTTPRequest`.
        case server
    }

    /// One decoded H3 frame from the request stream. `.unknown` covers reserved
    /// / grease types the validator allowed past. `.capsule` is yielded only in
    /// `capsuleMode`, where DATA payloads are walked as RFC 9297 capsules.
    enum DecodedFrame: ~Copyable {
        case request(HTTPRequest)
        case response(HTTPResponse)
        case data(FrameArray)
        case capsule(rawType: UInt64, payload: FrameArray)
        case unknown(type: UInt64, payload: FrameArray)
        case error(HTTP3Error.HTTP3ErrorCode)
    }

    let role: Role
    /// In capsule mode, H3 DATA bodies are walked as RFC 9297 capsules and
    /// surfaced as `.capsule(rawType, payload)` (capsules may span DATA frames).
    let capsuleMode: Bool
    private var pending: FrameArray = FrameArray()
    private var validator: H3RequestStreamValidator = H3RequestStreamValidator()
    /// Cross-DATA-frame capsule reassembly buffer; empty unless `capsuleMode`.
    private var capsuleBuffer: FrameArray = FrameArray()
    /// Sticky failure flag — once `nextFrame()` yields `.error(...)`, subsequent
    /// calls return nil and further `feed()` bytes are dropped.
    private var failed: Bool = false

    init(role: Role, capsuleMode: Bool = false) {
        self.role = role
        self.capsuleMode = capsuleMode
    }

    // MARK: Encode (outbound)

    /// Encode an HTTPRequest as a complete H3 HEADERS frame (client-side).
    static func encodeRequest(_ request: HTTPRequest) -> FrameArray {
        let block = H3HeaderEncoding.encodeRequest(request)
        return H3Framing.encodeFrame(type: .headers, payload: consume block)
    }

    /// Encode an HTTPResponse as a complete H3 HEADERS frame (server-side).
    static func encodeResponse(_ response: HTTPResponse) -> FrameArray {
        let block = H3HeaderEncoding.encodeResponse(response)
        return H3Framing.encodeFrame(type: .headers, payload: consume block)
    }

    /// Wrap a payload as a complete H3 DATA frame; payload frames moved (no copy).
    static func encodeData(_ payload: consuming FrameArray) -> FrameArray {
        return H3Framing.encodeFrame(type: .data, payload: consume payload)
    }

    /// Encode a single RFC 9297 capsule wrapped in an H3 DATA frame.  Used on
    /// streams that have negotiated the capsule protocol (CONNECT-UDP / -IP).
    static func encodeCapsule(rawType: UInt64,
                                     payload: consuming FrameArray) -> FrameArray {
        let capsule = H3CapsuleFraming.encode(rawType: rawType, payload: consume payload)
        return H3Framing.encodeFrame(type: .data, payload: consume capsule)
    }

    // MARK: Decode (inbound)

    /// Append more inbound stream bytes; pull frames out via `nextFrame()`.
    mutating func feed(_ frames: consuming FrameArray) {
        if failed {
            var drop = frames
            drop.finalizeAllFramesAsFailed()
            return
        }
        pending.add(frames: consume frames)
    }

    /// Return the next decoded frame, or nil if a complete frame is not yet
    /// available (or the stream has previously yielded an error). On `.error`
    /// the codec is wedged: subsequent calls return nil and `feed()` drops bytes.
    mutating func nextFrame() -> DecodedFrame? {
        if failed { return nil }
        // In capsule mode, drain buffered capsules from prior DATA frames first.
        if capsuleMode, let cap = nextBufferedCapsule() {
            return cap
        }
        while let head = H3Framing.consumeNextFrameHead(from: &pending) {
            if let err = validator.observe(frameType: head.type) {
                var bad = pending.drainArray(maximumByteCount: head.payloadByteCount)
                bad.finalizeAllFramesAsFailed()
                failed = true
                return .error(err)
            }
            let payload = pending.drainArray(maximumByteCount: head.payloadByteCount)
            switch head.type {
            case H3FrameType.headers.rawValue:
                return decodeHeaders(consume payload)
            case H3FrameType.data.rawValue:
                if capsuleMode {
                    capsuleBuffer.add(frames: consume payload)
                    if let cap = nextBufferedCapsule() {
                        return cap
                    }
                    continue
                }
                return .data(consume payload)
            default:
                return .unknown(type: head.type, payload: consume payload)
            }
        }
        return nil
    }

    /// Try to extract one complete capsule from the cross-DATA-frame
    /// reassembly buffer. Only meaningful in capsule mode.
    private mutating func nextBufferedCapsule() -> DecodedFrame? {
        guard let head = H3CapsuleFraming.consumeNextCapsuleHead(from: &capsuleBuffer) else {
            return nil
        }
        let payload = capsuleBuffer.drainArray(maximumByteCount: head.payloadByteCount)
        return .capsule(rawType: head.rawType, payload: consume payload)
    }

    var validatorState: H3RequestStreamValidator.State { validator.state }

    private func decodeHeaders(_ payload: consuming FrameArray) -> DecodedFrame {
        switch role {
        case .server:
            guard let request = H3HeaderEncoding.decodeRequest(consume payload) else {
                return .error(.messageError)
            }
            return .request(request)
        case .client:
            guard let response = H3HeaderEncoding.decodeResponse(consume payload) else {
                return .error(.messageError)
            }
            return .response(response)
        }
    }
}

// MARK: - H3 Frame Encoding/Decoding

enum H3Framing {

    static func encodeFrame(type: H3FrameType, payload: [UInt8]) -> [UInt8] {
        var frame: [UInt8] = []
        frame.reserveCapacity(type.rawValue.variableLengthSize + UInt64(payload.count).variableLengthSize + payload.count)
        type.rawValue.variableLengthEncodeInto(&frame)
        UInt64(payload.count).variableLengthEncodeInto(&frame)
        frame.append(contentsOf: payload)
        return frame
    }

    /// FrameArray-based encode of an H3 frame; payload frames moved (no copy).
    static func encodeFrame(type: H3FrameType, payload: consuming FrameArray) -> FrameArray {
        let payloadLen = UInt64(payload.unclaimedLength)
        var result = Serializer.serialize(frameCapacity: 16) { write in
            write.vle(type.rawValue)
            write.vle(payloadLen)
        }
        result.add(frames: consume payload)
        return result
    }

    /// One H3 frame's header fields produced by `peekNextFrameHead` /
    /// `consumeNextFrameHead`.
    struct H3FrameHead: Sendable, Equatable {
        let type: UInt64
        let headerLength: Int       // VLE type + VLE length bytes
        let payloadByteCount: Int

        var totalLength: Int { headerLength + payloadByteCount }
    }

    /// Peek at the next frame's header (VLE type + VLE length) without
    /// consuming. Returns nil if VLEs aren't fully present yet (does not
    /// require the payload to have arrived).
    static func peekNextFrameHead(in pending: inout FrameArray) -> H3FrameHead? {
        guard pending.count > 0, pending.unclaimedLength > 0 else { return nil }

        var frameType: UInt64 = 0
        var typeSize = 0
        var payloadLen: UInt64 = 0
        var lenSize = 0
        let r = Deserializer.deserialize(&pending, claim: false, removeClaimedFrames: false) {
            (read: inout Deserializer<FrameArraySpanFactory>) throws(DeserializationError) in
            try read.vleWithSize(&frameType, &typeSize)
            try read.vleWithSize(&payloadLen, &lenSize)
        }
        guard r.isValid else { return nil }
        return H3FrameHead(type: frameType,
                           headerLength: typeSize + lenSize,
                           payloadByteCount: Int(payloadLen))
    }

    /// If `pending` contains a complete H3 frame at its head, consume the
    /// header bytes (VLE type + VLE length); leaves `payloadByteCount` bytes of
    /// payload at the head. Returns nil (and leaves `pending` unchanged) if
    /// the header isn't fully present or the declared payload hasn't arrived.
    static func consumeNextFrameHead(from pending: inout FrameArray) -> H3FrameHead? {
        guard let head = peekNextFrameHead(in: &pending) else { return nil }
        guard pending.unclaimedLength >= head.totalLength else { return nil }
        guard pending.claim(fromStart: head.headerLength, removeClaimedFrames: true) else {
            return nil
        }
        return head
    }

    // MARK: - GOAWAY (RFC 9114 §5.2)
    //
    // Single-VLE payload: server-side = largest request stream ID processed,
    // client-side = largest push ID accepted (we don't push, so client GOAWAYs
    // are decode-only). Monotonicity is enforced at connection level.

    /// Encode a complete GOAWAY frame (type VLE + length VLE + ID VLE).
    static func encodeGoaway(largestProcessedID: UInt64) -> FrameArray {
        let payloadLen = UInt64(largestProcessedID.variableLengthSize)
        let total = H3FrameType.goaway.rawValue.variableLengthSize
                  + payloadLen.variableLengthSize
                  + Int(payloadLen)
        let capacity = max(total, 8)
        return Serializer.serialize(frameCapacity: capacity) { write in
            write.vle(H3FrameType.goaway.rawValue)
            write.vle(payloadLen)
            write.vle(largestProcessedID)
        }
    }

    /// Decode a GOAWAY payload from a Deserializer at the start of payload.
    /// `payloadByteCount` is the on-wire length from the frame's length VLE.
    /// Returns nil for a truncated VLE or trailing bytes after the ID
    /// (caller should close with `HTTP3Error.HTTP3ErrorCode.frameError`).
    static func decodeGoawayPayload<F: DeserializerSpanFactory & ~Copyable & ~Escapable>(
        from read: inout Deserializer<F>,
        payloadByteCount: Int
    ) -> UInt64? {
        var id: UInt64 = 0
        var idSize: Int = 0
        do {
            try read.vleWithSize(&id, &idSize)
        } catch {
            return nil
        }
        // The VLE must occupy the entire payload (RFC 9114 §7.2.6).
        guard idSize == payloadByteCount else { return nil }
        return id
    }

    /// Decode a GOAWAY payload from a byte buffer.
    static func decodeGoawayPayload(_ bytes: borrowing [UInt8]) -> UInt64? {
        var result: UInt64? = nil
        let r = Deserializer.deserialize(bytes) { (read: inout Deserializer) throws(DeserializationError) in
            result = decodeGoawayPayload(from: &read, payloadByteCount: bytes.count)
        }
        guard r.isValid else { return nil }
        return result
    }
}

// MARK: - HTTP Capsule Protocol (RFC 9297)
//
// Once a stream negotiates `Capsule-Protocol: ?1`, H3 DATA bodies become a
// sequence of `VLE type ‖ VLE length ‖ payload`. All encode/decode operates
// on `FrameArray` so the data path doesn't materialize `[UInt8]` copies.

struct H3CapsuleHead: Equatable, Sendable {
    let rawType: UInt64
    let headerLength: Int      // VLE type + VLE length bytes
    let payloadByteCount: Int

    var totalLength: Int { headerLength + payloadByteCount }
}

enum H3CapsuleFraming {

    /// Encode one capsule; payload frames moved (no copy).
    static func encode(rawType: UInt64, payload: consuming FrameArray) -> FrameArray {
        let payloadLen = UInt64(payload.unclaimedLength)
        var result = Serializer.serialize(frameCapacity: 16) { write in
            write.vle(rawType)
            write.vle(payloadLen)
        }
        result.add(frames: consume payload)
        return result
    }

    /// Peek at the next capsule header without consuming. Returns nil if the
    /// type/length VLEs are not yet fully present.
    static func peekNextCapsuleHead(in pending: inout FrameArray) -> H3CapsuleHead? {
        guard pending.count > 0, pending.unclaimedLength > 0 else { return nil }

        var rawType: UInt64 = 0
        var typeSize = 0
        var payloadLen: UInt64 = 0
        var lenSize = 0
        let r = Deserializer.deserialize(&pending, claim: false, removeClaimedFrames: false) {
            (read: inout Deserializer<FrameArraySpanFactory>) throws(DeserializationError) in
            try read.vleWithSize(&rawType, &typeSize)
            try read.vleWithSize(&payloadLen, &lenSize)
        }
        guard r.isValid else { return nil }
        return H3CapsuleHead(rawType: rawType,
                             headerLength: typeSize + lenSize,
                             payloadByteCount: Int(payloadLen))
    }

    /// If `pending` contains a complete capsule at its head, consume the
    /// header bytes (VLE type + VLE length), leaving `payloadByteCount` bytes
    /// of payload at the head. Returns nil (and leaves `pending` unchanged)
    /// if header is incomplete or the payload hasn't all arrived.
    static func consumeNextCapsuleHead(from pending: inout FrameArray) -> H3CapsuleHead? {
        guard let head = peekNextCapsuleHead(in: &pending) else { return nil }
        guard pending.unclaimedLength >= head.totalLength else { return nil }
        guard pending.claim(fromStart: head.headerLength, removeClaimedFrames: true) else {
            return nil
        }
        return head
    }
}

// MARK: - H3 Datagram Session (RFC 9297 / RFC 9221)
//
// Per-request-stream H3 datagram channel. Hides the wire-format choice
// (RFC 9221 QUIC DATAGRAM frames vs RFC 9297 capsules over the bidi request
// stream). Callers exchange `(context-id VLE ‖ inner payload)`; the session
// adds/strips qsid (DATAGRAM-frame path) or capsule header (capsule path).

final class H3DatagramSession {

    /// Sender for the bidi request stream (RFC 9297 capsule path); installed
    /// by the owner (e.g. `MASQUEConnectUDPInstance`).
    var streamSender: ((consuming FrameArray) throws(NetworkError) -> Void)?

    /// Sender for the QUIC DATAGRAM-frame path; installed by the wiring layer
    /// (e.g. `MASQUEProxyServer`) once a per-session `QUICDatagramFlow` is
    /// open AND the peer advertised `SETTINGS_H3_DATAGRAM`. Receives
    /// `(context-id VLE ‖ inner payload)`; the QUIC layer prepends the qsid
    /// VLE because the flow's `flowID` is set. When non-nil, `send(_:)` prefers
    /// this over the capsule fallback.
    var flowSender: ((consuming FrameArray) throws(NetworkError) -> Void)?

    /// Quarter-stream-id of the bidi request stream this session is bound to.
    /// Required for the QUIC DATAGRAM-frame path; optional for the capsule path.
    var quarterStreamID: UInt64?

    /// Connection coordinator for peer settings and qsid demux registration.
    /// Optional in the capsule path.
    weak var connection: HTTP3ConnectionInstance?

    /// Inbound H3 datagram callback. Receives `(context-id VLE ‖ inner payload)`
    /// per RFC 9297; qsid (DATAGRAM-frame path) or capsule header (capsule
    /// path) is already stripped.
    var onDatagramReceived: ((consuming FrameArray) -> Void)?

    init() {}

    /// Send one H3 datagram. `payload` is `(context-id VLE ‖ inner payload)`.
    /// Routes via QUIC DATAGRAM frame when `flowSender` is installed; else
    /// wraps as an RFC 9297 DATAGRAM capsule and ships through `streamSender`.
    func send(_ payload: consuming FrameArray) throws(NetworkError) {
        if let viaFlow = flowSender {
            // QUIC DATAGRAM-frame path: QUIC prepends qsid; H3 adds nothing further.
            try viaFlow(consume payload)
            return
        }
        guard let sender = streamSender else {
            var drop = payload
            drop.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        // RFC 9297 §3.1: DATAGRAM capsule type = 0x00.
        let h3Frame = H3RequestStreamCodec.encodeCapsule(rawType: 0x00,
                                                          payload: consume payload)
        try sender(consume h3Frame)
    }

    /// Called by the bidi-stream codec on a DATAGRAM capsule, or (Phase 2) by
    /// connection-level demux on a QUIC DATAGRAM frame for this session's qsid.
    /// `payload` is `(context-id VLE ‖ inner payload)`.
    func deliverInbound(_ payload: consuming FrameArray) {
        if let cb = onDatagramReceived {
            cb(consume payload)
        } else {
            var drop = payload
            drop.finalizeAllFramesAsFailed()
        }
    }
}

// MARK: - HTTP/3 Connection Instance (RFC 9114 §6.2)
//
// Coordinator class — NOT a byte-carrying NetworkProtocol. Mirrors libnetcore's
// `nw_protocol_http3` connection level. Owns control-stream signaling
// (SETTINGS, GOAWAY) while bytes flow through `MASQUE → HTTP3StreamShim →
// QUICStreamProtocol` as before.

final class HTTP3ConnectionInstance {
    var log = NetworkLoggerState("h3-conn")

    let isServer: Bool
    var localSettings: H3Settings
    private(set) var peerSettings: H3Settings? = nil

    private(set) var settingsSent: Bool = false
    private(set) var settingsReceived: Bool = false
    private(set) var peerControlStreamInstalled: Bool = false

    private(set) var lastGoawayIDSent: UInt64? = nil
    private(set) var lastGoawayIDReceived: UInt64? = nil
    private(set) var goingAway: Bool = false

    private(set) var closeError: HTTP3Error.HTTP3ErrorCode? = nil
    private(set) var closeReason: String? = nil

    /// Called once when SETTINGS arrives on the inbound control stream.
    var onSettingsReceived: ((H3Settings) -> Void)? = nil
    /// Called whenever a GOAWAY arrives on the inbound control stream.
    var onGoawayReceived: ((UInt64) -> Void)? = nil
    /// Fired once on the first `recordCloseWithError`; sticky-no-op afterwards.
    var onCloseWithError: ((HTTP3Error.HTTP3ErrorCode, String?) -> Void)? = nil

    init(server: Bool, localSettings: H3Settings = H3Settings()) {
        self.isServer = server
        self.localSettings = localSettings
        if server {
            // RFC 9220: server MUST advertise SETTINGS_ENABLE_CONNECT_PROTOCOL
            // for extended-CONNECT (which MASQUE relies on).
            self.localSettings.enableConnectProtocol = true
        }
    }

    // MARK: Outbound

    /// Bytes for a freshly-opened outbound uni QUIC stream: the H3 control-stream
    /// type byte (0x00) followed by the local SETTINGS frame. Single-shot.
    func makeOutboundControlPrologue() -> FrameArray {
        precondition(!settingsSent, "makeOutboundControlPrologue called twice")
        var payload = localSettings.encodePayload()
        let payloadLen = UInt64(payload.unclaimedLength)
        let result = Serializer.serialize(frameCapacity: 16) { write in
            write.vle(UInt64(0x00))                          // uni stream type: control
            write.vle(H3FrameType.settings.rawValue)         // SETTINGS frame type
            write.vle(payloadLen)                            // payload length VLE
            write.frameArray(&payload)                       // SETTINGS payload (no copy)
        }
        settingsSent = true
        return result
    }

    /// Encode a GOAWAY frame for the outbound control stream. Returns nil
    /// (no state change) if `largestProcessedID` exceeds the previous GOAWAY
    /// — RFC 9114 §5.2 forbids raising the value.
    func makeGoaway(largestProcessedID: UInt64) -> FrameArray? {
        if let prev = lastGoawayIDSent, largestProcessedID > prev {
            return nil
        }
        lastGoawayIDSent = largestProcessedID
        goingAway = true
        return H3Framing.encodeGoaway(largestProcessedID: largestProcessedID)
    }

    // MARK: Inbound — uni-stream type-byte demux

    enum UniStreamDispatch: Equatable, Sendable {
        /// Type VLE not yet fully present; caller accumulates and retries.
        /// `pending` unchanged.
        case needMoreBytes
        /// Type 0x00. Caller treats this as the peer's inbound control stream
        /// and feeds remaining + future bytes to `processControlStreamBytes`.
        /// `pending` advanced past the type byte.
        case controlStream
        /// Type 0x02 / 0x03 — QPACK encoder/decoder. We run literal-only
        /// QPACK so we never read or write here. Caller abandons the stream.
        case qpackStream
        /// Unaccepted type (push 0x01, WebTransport 0x54, anything else).
        /// Caller resets the stream with the returned error code.
        case rejectStream(HTTP3Error.HTTP3ErrorCode)
    }

    /// Consume the uni-stream type VLE at the head of `pending` and classify.
    /// Type byte is removed from `pending` on any return other than `.needMoreBytes`.
    func tryClassifyUniStream(_ pending: inout FrameArray) -> UniStreamDispatch {
        guard pending.count > 0, pending.unclaimedLength > 0 else { return .needMoreBytes }

        var typeID: UInt64 = 0
        var typeSize = 0
        let r = Deserializer.deserialize(&pending, claim: false, removeClaimedFrames: false) {
            (read: inout Deserializer<FrameArraySpanFactory>) throws(DeserializationError) in
            try read.vleWithSize(&typeID, &typeSize)
        }
        guard r.isValid else { return .needMoreBytes }
        guard pending.claim(fromStart: typeSize, removeClaimedFrames: true) else {
            recordCloseWithError(.frameError, reason: "uni stream type VLE consumption failed")
            return .rejectStream(.frameError)
        }

        switch typeID {
        case 0x00:
            // RFC 9114 §6.2.1: only one peer control stream is permitted.
            if peerControlStreamInstalled {
                recordCloseWithError(.streamCreationError, reason: "second peer control stream")
                return .rejectStream(.streamCreationError)
            }
            peerControlStreamInstalled = true
            return .controlStream
        case 0x02, 0x03:
            // QPACK encoder/decoder — literal-only QPACK ignores them.
            return .qpackStream
        case 0x01:
            // Server push — not implemented.
            return .rejectStream(.streamCreationError)
        default:
            // Unknown / WebTransport (0x54) / etc.
            return .rejectStream(.streamCreationError)
        }
    }

    // MARK: Inbound — control stream frame parsing

    /// Process complete frames at the head of `pending` (the inbound control
    /// stream's accumulator after `tryClassifyUniStream`). Enforces:
    /// SETTINGS-first (`H3_MISSING_SETTINGS`); subsequent SETTINGS or
    /// DATA/HEADERS → `H3_FRAME_UNEXPECTED`; GOAWAY monotonicity per RFC 9114
    /// §5.2 (`H3_ID_ERROR`); reserved/unknown silently ignored.
    /// On violation the error is recorded via `recordCloseWithError` and
    /// processing stops; consumed bytes are removed from `pending`.
    func processControlStreamBytes(_ pending: inout FrameArray) {
        while closeError == nil, let head = H3Framing.consumeNextFrameHead(from: &pending) {
            // Drain the payload as its own FrameArray.
            var payload = pending.drainArray(maximumByteCount: head.payloadByteCount)

            // Enforce the SETTINGS-first invariant.
            if !settingsReceived {
                guard head.type == H3FrameType.settings.rawValue else {
                    payload.finalizeAllFramesAsFailed()
                    recordCloseWithError(.missingSettings,
                                         reason: "first control-stream frame was \(head.type), not SETTINGS")
                    return
                }
                let payloadBytes = drainBytes(consume payload)
                guard let s = H3Settings.decodePayload(payloadBytes) else {
                    recordCloseWithError(.settingsError, reason: "malformed initial SETTINGS")
                    return
                }
                peerSettings = s
                settingsReceived = true
                onSettingsReceived?(s)
                continue
            }

            switch head.type {
            case H3FrameType.settings.rawValue:
                payload.finalizeAllFramesAsFailed()
                recordCloseWithError(.frameUnexpected, reason: "second SETTINGS on control stream")
                return
            case H3FrameType.goaway.rawValue:
                let payloadBytes = drainBytes(consume payload)
                guard let id = H3Framing.decodeGoawayPayload(payloadBytes) else {
                    recordCloseWithError(.frameError, reason: "malformed GOAWAY")
                    return
                }
                if let prev = lastGoawayIDReceived, id > prev {
                    recordCloseWithError(.idError,
                                         reason: "GOAWAY ID increased: \(prev) → \(id)")
                    return
                }
                lastGoawayIDReceived = id
                goingAway = true
                onGoawayReceived?(id)
            case H3FrameType.data.rawValue, H3FrameType.headers.rawValue:
                payload.finalizeAllFramesAsFailed()
                recordCloseWithError(.frameUnexpected,
                                     reason: "DATA/HEADERS frame type \(head.type) on control stream")
                return
            default:
                // Reserved / unknown on control stream — silently ignore (RFC 9114 §7.2.8).
                payload.finalizeAllFramesAsFailed()
            }
        }
    }

    // MARK: Connection-level errors

    /// Record the close code; first call wins (sticky-no-op afterwards) so the
    /// original cause is preserved. Caller polls `closeError` and invokes
    /// `quicConnection.closeWithError(applicationError: code.rawValue)`.
    func recordCloseWithError(_ code: HTTP3Error.HTTP3ErrorCode, reason: String? = nil) {
        guard closeError == nil else { return }
        closeError = code
        closeReason = reason
        log.error("H3 connection close: code=\(code) reason=\(reason ?? "(none)")")
        onCloseWithError?(code, reason)
    }

    // MARK: helpers

    /// Drain a small FrameArray's bytes into a `[UInt8]` for decoders that
    /// take `[UInt8]`. Finalizes the frames as it goes.
    private func drainBytes(_ array: consuming FrameArray) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(array.unclaimedLength)
        while var frame = array.popFirst() {
            if let span = frame.span {
                bytes.append(contentsOf: [UInt8](copying: span, maxCount: span.count))
            }
            frame.finalize(success: true)
        }
        return bytes
    }
}

// MARK: - Protocol Definition

struct HTTP3Protocol: NetworkProtocol {
    typealias Options = HTTP3Options
    typealias Metadata = HTTP3Metadata
    typealias Instance = HTTP3StreamShim

    static let identifier = ProtocolIdentifier(
        name: "http3",
        level: .application,
        mapping: .oneToOne
    )

    init() {}

    func newPerProtocolOptions() -> HTTP3Options? { HTTP3Options() }
    func newPerProtocolOptions(from existing: HTTP3Options) -> HTTP3Options { existing.deepCopy() }
    func newPerProtocolOptions(from serializedBytes: [UInt8]) -> HTTP3Options? { nil }
    func newPerProtocolMetadata() -> HTTP3Metadata? { HTTP3Metadata() }
    func newProtocolInstance(context: NetworkContext) -> ProtocolInstanceReference? { nil }

#if !NETWORK_PRIVATE
    static let definition = ProtocolDefinition<HTTP3Protocol>(identifier: identifier)

    static func options() -> ProtocolOptions<HTTP3Protocol> {
        return HTTP3Protocol.definition.protocolOptions()
    }
#endif
}

// MARK: - Options / Metadata

struct HTTP3Options: PerProtocolOptions {
    init() {}
    func serialize() -> [UInt8]? { nil }
    var serializeInParameters: Bool { false }
    func deepCopy() -> HTTP3Options { self }
    func isEqual(to other: HTTP3Options, for mode: ProtocolCompareMode) -> Bool { true }
    static func == (lhs: HTTP3Options, rhs: HTTP3Options) -> Bool { true }
}

struct HTTP3Metadata: PerProtocolMetadata {
    init() {}
    func isEqual(to other: HTTP3Metadata, for mode: ProtocolCompareMode) -> Bool { true }
    static func == (lhs: HTTP3Metadata, rhs: HTTP3Metadata) -> Bool { true }
}

// MARK: - HTTP/3 Stream Shim (OneToOneStreamProtocol passthrough)

final class HTTP3StreamShim: OneToOneStreamProtocol, ProtocolInstanceContainer, LoggableProtocol, OutboundStreamHandler, InboundStreamHandler {
    var passthroughEvents = false

    var upper = InboundStreamLinkage()
    var lower = OutboundStreamLinkage()

    private(set) var context: NetworkContext
    var reference: ProtocolInstanceReference {
        ProtocolInstanceReference(custom: self)
    }
    var log = NetworkLoggerState("h3-shim")
    var eventManager = ProtocolEventManager()

    /// Fired when the underlying QUIC stream reports connected. The harness
    /// uses this to open the H3 control uni-stream — by then the QUIC handshake
    /// is done, so a uni open is allowed (vs ENOTCONN before handshake).
    var onConnected: (() -> Void)? = nil
    /// Fired from `handleDisconnectedEvent` so an owning proxy can drop
    /// per-stream state (session table entry, references) on tunnel teardown.
    var onDisconnected: ((NetworkError?) -> Void)? = nil

    init(context: NetworkContext) {
        self.context = context
    }

    func connect() {
        log.info("H3 stream connected")
        if !upper.isDetached {
            upper.deliverConnectedEvent(reference)
        }
    }

    func handleConnectedEvent(_ from: ProtocolInstanceReference) {
        log.info("H3 stream transport connected")
        onConnected?()
        if !upper.isDetached {
            upper.deliverConnectedEvent(reference)
        }
    }

    func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        log.info("H3 stream transport disconnected")
        onDisconnected?(error)
        if !upper.isDetached {
            upper.deliverDisconnectedEvent(reference, error: error)
        }
    }

    func receiveStreamData(minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray? {
        return try lower.invokeReceiveStreamData(reference, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }

    func getOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int {
        return try lower.invokeGetOutboundStreamDataRoomAvailable(reference)
    }

    func sendStreamData(_ streamData: consuming FrameArray) throws(NetworkError) {
        try lower.invokeSendStreamData(reference, streamData: streamData)
    }

#if !NETWORK_EMBEDDED
    var metadata: AbstractProtocolMetadata? { nil }
#endif
}

// MARK: - H3 Control Stream Coordinator
//
// Inbound coordinator above a uni QUIC stream. Classifies the leading uni
// type VLE via `HTTP3ConnectionInstance.tryClassifyUniStream`, then routes
// peer control bytes (type 0x00) through `processControlStreamBytes`. QPACK
// / push / unknown stream types log an error and stop reading.
// For outbound control the harness uses `HTTP3StreamShim` directly with the
// prologue from `makeOutboundControlPrologue`.

final class H3ControlStreamCoordinator: OneToOneStreamProtocol, ProtocolInstanceContainer, LoggableProtocol, OutboundStreamHandler, InboundStreamHandler {
    var upper = InboundStreamLinkage()
    var lower = OutboundStreamLinkage()

    private(set) var context: NetworkContext
    var reference: ProtocolInstanceReference {
        ProtocolInstanceReference(custom: self)
    }
    var log = NetworkLoggerState("h3-control-rx")
    var eventManager = ProtocolEventManager()

    let h3Connection: HTTP3ConnectionInstance

    private var pendingInbound: FrameArray = FrameArray()
    private var typeClassified: Bool = false

    init(context: NetworkContext, h3Connection: HTTP3ConnectionInstance) {
        self.context = context
        self.h3Connection = h3Connection
    }

    func connect() {
        if !upper.isDetached {
            upper.deliverConnectedEvent(reference)
        }
    }

    func handleConnectedEvent(_ from: ProtocolInstanceReference) {
        if !upper.isDetached {
            upper.deliverConnectedEvent(reference)
        }
    }

    func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        // RFC 9114 §6.2.1: the control stream is critical.
        h3Connection.recordCloseWithError(.closedCriticalStream,
                                          reason: "peer control stream closed")
        pendingInbound.finalizeAllFramesAsFailed()
        pendingInbound = FrameArray()
        if !upper.isDetached {
            upper.deliverDisconnectedEvent(reference, error: error)
        }
    }

    func handleInboundDataAvailableEvent() {
        guard let frames = try? lower.invokeReceiveStreamData(reference, minimumBytes: 1, maximumBytes: 65536) else {
            return
        }
        pendingInbound.add(frames: consume frames)

        if !typeClassified {
            switch h3Connection.tryClassifyUniStream(&pendingInbound) {
            case .needMoreBytes:
                return
            case .controlStream:
                typeClassified = true
                h3Connection.processControlStreamBytes(&pendingInbound)
            case .qpackStream:
                typeClassified = true
                pendingInbound.finalizeAllFramesAsFailed()
                pendingInbound = FrameArray()
                log.error("H3 control RX classified as QPACK — caller wired wrong stream")
            case .rejectStream(let code):
                pendingInbound.finalizeAllFramesAsFailed()
                pendingInbound = FrameArray()
                log.error("H3 control RX peer uni stream rejected: \(code)")
            }
        } else {
            h3Connection.processControlStreamBytes(&pendingInbound)
        }
    }

    func handleOutboundRoomAvailableEvent() {}

    // No upper protocol attached; methods required for the protocol but should not be called.
    func receiveStreamData(minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray? {
        nil
    }
    func getOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int { 0 }
    func sendStreamData(_ streamData: consuming FrameArray) throws(NetworkError) {
        streamData.finalizeAllFramesAsFailed()
    }

#if !NETWORK_EMBEDDED
    var metadata: AbstractProtocolMetadata? { nil }
#endif
    var passthroughEvents = false
}
