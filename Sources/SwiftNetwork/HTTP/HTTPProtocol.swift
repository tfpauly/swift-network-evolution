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

#if canImport(Synchronization)
internal import Synchronization
#endif

import HTTPTypes

@_spi(Essentials)
@available(Network 0.1.0, *)
public struct HTTPProtocol: NetworkProtocol {
    public typealias Options = HTTPOptions
    public typealias Metadata = HTTPMetadata
    typealias Instance = HTTPInstance

    public struct HTTPOptions: PerProtocolOptions {


        public init() {
        }

        public func serialize() -> [UInt8]? {
            nil
        }
        public var serializeInParameters: Bool {
            false
        }
        public func deepCopy() -> HTTPOptions {
            self
        }
        public func isEqual(to other: HTTPOptions, for: ProtocolCompareMode) -> Bool {
            self == other
        }
    }

    public class HTTPMetadata: PerProtocolMetadata {

        public init() {}

        public func isEqual(to other: HTTPMetadata, for: ProtocolCompareMode) -> Bool { true }

        public static func == (lhs: borrowing HTTPProtocol.HTTPMetadata, rhs: borrowing HTTPProtocol.HTTPMetadata) -> Bool {
            lhs.isEqual(to: rhs, for: .equal)
        }
    }

    public struct HTTPMessage: ~Copyable {
        var request: HTTPRequest?
        var response: HTTPResponse?
    }

    final class HTTPInstance: OneToOneDatapathProtocol, OutboundMessageHandler, TimerSchedulable {

        typealias OutboundMessageType = HTTPMessage

        typealias UpperProtocol = InboundHTTPMessageLinkage
        typealias LowerProtocol = OutboundStreamLinkage

        var upper = InboundHTTPMessageLinkage()
        var lower = OutboundStreamLinkage()

        private(set) var context: NetworkContext
        init(context: NetworkContext) { self.context = context }
        var reference: ProtocolInstanceReference { ProtocolInstanceReference() /*ProtocolInstanceReference(tcp: self)*/ }
        var passthroughEvents = false
        var log = NetworkLoggerState()
        var eventManager = ProtocolEventManager()
        func setup(
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            throw NetworkError.posix(ENOTSUP)
        }
        func wakeup() {}

        func receiveMessage(_ from: ProtocolInstanceReference) throws(NetworkError) -> HTTPProtocol.HTTPMessage? {
            return nil
        }

        func sendMessage(_ from: ProtocolInstanceReference, message: consuming HTTPProtocol.HTTPMessage) throws(NetworkError) {

        }

        func attachUpperStreamProtocol(_ from: ProtocolInstanceReference, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) -> OutboundStreamLinkage {
            return OutboundStreamLinkage()
        }

        func receiveStreamData(_ from: ProtocolInstanceReference, minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray? {
            return nil
        }

        func getOutboundStreamDataRoomAvailable(_ from: ProtocolInstanceReference) throws(NetworkError) -> Int {
            return 0
        }

        func sendStreamData(_ from: ProtocolInstanceReference, streamData: consuming FrameArray) throws(NetworkError) {

        }


        #if !NETWORK_EMBEDDED
        var metadata: AbstractProtocolMetadata? { nil }
        #endif
    }

    public init() {}
    public func newPerProtocolOptions() -> HTTPOptions? { HTTPOptions() }
    public func newPerProtocolOptions(from existing: HTTPOptions) -> HTTPOptions { existing }
    public func newPerProtocolOptions(from serializedBytes: [UInt8]) -> HTTPOptions? { nil }
    public func newPerProtocolMetadata() -> HTTPMetadata? { HTTPMetadata() }
    public func newProtocolInstance(context: NetworkContext) -> ProtocolInstanceReference? { nil }

    static let identifier = ProtocolIdentifier(name: "http", level: .transport, mapping: .oneToOne)

    #if !NETWORK_PRIVATE
    static public let definition = ProtocolDefinition<HTTPProtocol>(identifier: identifier)
    #endif

    static public func options() -> ProtocolOptions<HTTPProtocol> { HTTPProtocol.definition.protocolOptions() }

    static public func instance(context: NetworkContext) -> ProtocolInstanceReference {
        HTTPProtocol().newProtocolInstance(context: context)!
    }
}

