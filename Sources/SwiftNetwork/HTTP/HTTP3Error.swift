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

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct HTTP3Error: NetworkDomainSpecificError {
    public static var domain: NetworkError.Domain { .init(rawValue: "HTTP3Error") }

    public enum HTTP3ErrorCode: Int64, Sendable {
        case noError = 0x0100
        case generalProtocolError = 0x0101
        case internalError = 0x0102
        case streamCreationError = 0x0103
        case closedCriticalStream = 0x0104
        case frameUnexpected = 0x0105
        case frameError = 0x0106
        case excessiveLoad = 0x0107
        case idError = 0x0108
        case settingsError = 0x0109
        case missingSettings = 0x010A
        case requestRejected = 0x010B
        case requestCancelled = 0x010C
        case requestIncomplete = 0x010D
        case messageError = 0x010E
        case connectError = 0x010F
        case versionFallback = 0x0110

        case datagramError = 0x33

        case qpackDecompressionFailed = 0x0200
        case qpackEncoderStreamError = 0x0201
        case qpackDecoderStreamError = 0x0202
    }

    let errorCode: HTTP3ErrorCode
    public let reason: String?

    public var code: Int64 {
        errorCode.rawValue
    }

    init(_ code: HTTP3ErrorCode, _ reason: String? = nil) {
        let reasonString: String?
        if let reason, !reason.isEmpty {
            reasonString = reason
        } else {
            reasonString = nil
        }
        self.errorCode = code
        self.reason = reasonString
    }

    public init?(_ code: Int64, _ reason: String? = nil) {
        guard let code = HTTP3ErrorCode(rawValue: code) else { return nil }
        self.init(code, reason)
    }

    public init?(_ code: UInt64, _ reason: String? = nil) {
        guard let code = Int64(exactly: code) else { return nil }
        self.init(code, reason)
    }

    public static func category(of error: HTTP3Error) -> NetworkError.CommonCategory? {
        switch error.errorCode {
        case .generalProtocolError, .streamCreationError, .closedCriticalStream, .frameUnexpected, .frameError, .idError, .settingsError, .missingSettings, .messageError, .connectError: return .specViolation
        case .excessiveLoad: return .excessiveLoad
        case .requestCancelled: return .applicationCancellation
        default: return nil
        }
    }

    public var description: String {
        if let reason {
            return reason
        }
        switch errorCode {
        case .noError: return "No error"
        case .generalProtocolError: return "General protocol error"
        case .internalError: return "Internal error"
        case .streamCreationError: return "Stream creation error"
        case .closedCriticalStream: return "Closed critical stream"
        case .frameUnexpected: return "Frame unexpected"
        case .frameError: return "Frame error"
        case .excessiveLoad: return "Excessive load"
        case .idError: return "ID error"
        case .settingsError: return "Settings error"
        case .missingSettings: return "Missing settings"
        case .requestRejected: return "Request rejected"
        case .requestCancelled: return "Request cancelled"
        case .requestIncomplete: return "Request incomplete"
        case .messageError: return "Message error"
        case .connectError: return "Connect error"
        case .versionFallback: return "Version fallback"
        case .datagramError: return "Datagram error"
        case .qpackDecompressionFailed: return "QPACK decompression failed"
        case .qpackEncoderStreamError: return "QPACK encoder stream error"
        case .qpackDecoderStreamError: return "QPACK decoder stream error"
        }
    }

    static func code(for error: NetworkError) -> Int64 {
        if let domainSpecificError = error.domainSpecificError,
            domainSpecificError.domain == Self.domain
        {
            return domainSpecificError.code
        }
        if let category = error.category {
            switch category {
            case .specViolation: return HTTP3ErrorCode.generalProtocolError.rawValue
            case .applicationCancellation: return HTTP3ErrorCode.requestCancelled.rawValue
            default: break
            }
        }
        return HTTP3ErrorCode.internalError.rawValue
    }
}
