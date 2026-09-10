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

#if IMPORT_SWIFTTLS && canImport(SwiftTLS)
#if EXPORT_SWIFTTLS
@_spi(SwiftTLSOptions) @_spi(SwiftTLSProtocol) import SwiftTLS
#else
@_spi(SwiftTLSOptions) @_spi(SwiftTLSProtocol) @_weakLinked internal import SwiftTLS
#endif
#endif

#if canImport(Foundation) && !NETWORK_EMBEDDED
import Foundation
#endif

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(Musl)
import Musl
internal import Logging
#elseif canImport(os)
internal import os
#endif

#if IMPORT_CRYPTO || IMPORT_SWIFTTLS
#if canImport(CryptoKit)
internal import CryptoKit
#elseif canImport(Crypto)
@preconcurrency internal import Crypto
#endif
#endif

#if canImport(SwiftSystem)
internal import SwiftSystem
#endif

#if !NETWORK_PRIVATE
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public typealias TLSProtocol = SwiftTLSProtocol
#endif

@available(Network 0.1.0, *)
protocol SwiftTLSQUICInstance<LinkageFamily>: AnyObject {
    associatedtype LinkageFamily: StreamLinkageFamily
    func getLowerLinkage(
        for level: SwiftTLSOptions.EncryptionLevel,
        upperLinkage: LinkageFamily.Upper
    ) -> LinkageFamily.Lower
    func updateSecret(_ secret: [UInt8], for level: SwiftTLSOptions.EncryptionLevel, isWrite: Bool)
    func updateEncryptionLevel(_ level: SwiftTLSOptions.EncryptionLevel, isWrite: Bool)
    func updateSessionTickets(_ sessionTicketArray: [[UInt8]])
    func updatePeerQUICTransportParameters(_ peerQUICTransportParameters: [UInt8], earlyData: Bool)
    func updateEarlyDataAccepted(_ earlyDataAccepted: Bool)
    func updateNegotiatedCiphersuite(_ ciphersuite: Int)
}

let SwiftTLSRecordProtocolMaxOutstandingReadBytes: Int = (8 * 1024 * 1024)  // 8MB

// Wrapper to send a value. Ensures that the value is only accessed
// from the context and fails otherwise.
@available(Network 0.1.0, *)
private struct ContextBound<Value>: @unchecked Sendable {
    public let context: NetworkContext

    @usableFromInline
    var _value: Value

    @inlinable
    public init(_ value: Value, context: NetworkContext) {
        context.assert()
        self.context = context
        self._value = value
    }

    @inlinable
    public var value: Value {
        get {
            self.context.assert()
            return self._value
        }
        _modify {
            self.context.assert()
            yield &self._value
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct SwiftTLSProtocol: NetworkProtocol {
    public typealias Options = SwiftTLSProtocolOptions
    public typealias Metadata = SwiftTLSMetadata

    public init() {}

    public struct SwiftTLSProtocolOptions: PerProtocolOptions {
        private var _tlsOptions = SwiftTLSOptionsStorage()

        #if EXPORT_SWIFTTLS
        private typealias SwiftTLSOptionsStorage = SwiftTLSOptions

        public var tlsOptions: SwiftTLSOptions {
            get { _tlsOptions }
            set { _tlsOptions = newValue }
        }

        public mutating func setExternalPSK(identity: [UInt8], epsk: [UInt8]) {
            _tlsOptions.externalPSK = .init(externalIdentity: identity, epsk: .init(data: epsk))
        }
        #else
        private struct SwiftTLSOptionsStorage {
            var serverName: String?
            var quicTransportParameters: [UInt8]?
            var applicationProtocols: [String]?
            var trustedRawPublicKeyCertificates: [[UInt8]]?
            var rawPrivateKey: [UInt8]?
            var enableEarlyData: Bool = false
            var clientAuthRequired: Bool = false
            var externalPSKIdentity: [UInt8]?
            var externalPSKData: [UInt8]?
        }

        var tlsOptions: SwiftTLSOptions {
            get {
                var tlsOptions = SwiftTLSOptions()
                tlsOptions.serverName = _tlsOptions.serverName
                tlsOptions.quicTransportParameters = _tlsOptions.quicTransportParameters
                tlsOptions.applicationProtocols = _tlsOptions.applicationProtocols
                tlsOptions.trustedRawPublicKeyCertificates = _tlsOptions.trustedRawPublicKeyCertificates
                tlsOptions.rawPrivateKey = _tlsOptions.rawPrivateKey
                tlsOptions.enableEarlyData = _tlsOptions.enableEarlyData
                tlsOptions.clientAuthRequired = _tlsOptions.clientAuthRequired
                #if IMPORT_SWIFTTLS
                if let externalPSKIdentity = _tlsOptions.externalPSKIdentity,
                    let externalPSKData = _tlsOptions.externalPSKData
                {
                    tlsOptions.externalPSK = .init(
                        externalIdentity: externalPSKIdentity,
                        epsk: .init(data: externalPSKData)
                    )
                }
                #endif
                return tlsOptions
            }
            set {
                _tlsOptions.serverName = newValue.serverName
                _tlsOptions.quicTransportParameters = newValue.quicTransportParameters
                _tlsOptions.applicationProtocols = newValue.applicationProtocols
                _tlsOptions.trustedRawPublicKeyCertificates = newValue.trustedRawPublicKeyCertificates
                _tlsOptions.rawPrivateKey = newValue.rawPrivateKey
                _tlsOptions.enableEarlyData = newValue.enableEarlyData
                _tlsOptions.clientAuthRequired = newValue.clientAuthRequired
            }
        }

        public mutating func setExternalPSK(identity: [UInt8], epsk: [UInt8]) {
            _tlsOptions.externalPSKIdentity = identity
            _tlsOptions.externalPSKData = epsk
        }
        #endif

        public var serverName: String? {
            get { _tlsOptions.serverName }
            set { _tlsOptions.serverName = newValue }
        }
        public var quicTransportParameters: [UInt8]? {
            get { _tlsOptions.quicTransportParameters }
            set { _tlsOptions.quicTransportParameters = newValue }
        }
        public var applicationProtocols: [String]? {
            get { _tlsOptions.applicationProtocols }
            set { _tlsOptions.applicationProtocols = newValue }
        }

        // Options used for setting up clients or servers
        // with the raw public keys they are willing to
        // trust from their peer.
        public var trustedRawPublicKeyCertificates: [[UInt8]]? {
            get { _tlsOptions.trustedRawPublicKeyCertificates }
            set { _tlsOptions.trustedRawPublicKeyCertificates = newValue }
        }

        // Server or client private key for use with Raw Public Keys
        public var rawPrivateKey: [UInt8]? {
            get { _tlsOptions.rawPrivateKey }
            set { _tlsOptions.rawPrivateKey = newValue }
        }

        public var enableEarlyData: Bool {
            get { _tlsOptions.enableEarlyData }
            set { _tlsOptions.enableEarlyData = newValue }
        }

        public var clientAuthRequired: Bool {
            get { _tlsOptions.clientAuthRequired }
            set { _tlsOptions.clientAuthRequired = newValue }
        }

        // Resumed QUIC transport parameter state, set on clients
        public var resumedQUICTransportParameters: [UInt8]?

        public init() {
            #if EXPORT_SWIFTTLS
            _tlsOptions.keyExchangeGroup = .x25519
            #endif
        }
        public func serialize() -> [UInt8]? { nil }
        public var serializeInParameters: Bool { false }
        public func deepCopy() -> SwiftTLSProtocolOptions {
            var copy = SwiftTLSProtocolOptions()
            copy.serverName = self.serverName
            copy.tlsOptions = self.tlsOptions
            copy.resumedQUICTransportParameters = self.resumedQUICTransportParameters
            return copy
        }
        public func isEqual(to other: SwiftTLSProtocolOptions, for: ProtocolCompareMode) -> Bool {
            self == other
        }
        public static func == (lhs: SwiftTLSProtocolOptions, rhs: SwiftTLSProtocolOptions) -> Bool {
            lhs.isEqual(to: rhs, for: .equal)
        }
    }

    public struct SwiftTLSMetadata: PerProtocolMetadata {
        init() {}
        public func isEqual(to other: SwiftTLSMetadata, for: ProtocolCompareMode) -> Bool { true }
    }

    /// The base of the TLS instance hierarchy.
    ///
    /// This class holds the state common to every flavor of TLS instance and satisfies the
    /// `OneToOneStreamProtocol` conformance, but it does not implement any of the protocol
    /// behavior itself: it is abstract. Concrete behavior lives in the subclasses,
    /// `SwiftTLSQUICOnlyInstance` (a QUIC handshake with no record layer) and
    /// `SwiftTLSRecordInstance` (a full record-layer TLS connection). The base implementations
    /// below abort or throw, so a missing override surfaces immediately rather than silently
    /// doing nothing.
    class SwiftTLSInstance<LinkageFamily: StreamLinkageFamily>: OneToOneStreamProtocol,
        ProtocolInstanceContainer
    {
        typealias UpperProtocol = LinkageFamily.Upper
        typealias LowerProtocol = LinkageFamily.Lower

        var metadata: AbstractProtocolMetadata?
        var upper = UpperProtocol()
        var lower = LowerProtocol()
        private(set) var context: NetworkContext
        var reference: ProtocolInstanceReference
        var passthroughEvents = false
        var log = NetworkLoggerState()
        var eventManager = ProtocolEventManager()

        init(context: NetworkContext) {
            self.context = context
            self.reference = ProtocolInstanceReference(context: context, eventManager: &self.eventManager)
        }

        /// Reads the per-protocol TLS options out of `parameters`, which every subclass needs
        /// before it can set itself up.
        final func perProtocolOptions(
            from parameters: Parameters?
        ) throws(NetworkError) -> SwiftTLSProtocolOptions {
            // Note: all logic about what tlsOptions are valid/required should be handled
            // within SwiftTLS, so that logic does not need to be duplicated here and in
            // nwswifttls.m/nwswifttlsrecord.m
            guard let parameters,
                let options = tlsOptions(from: parameters),
                let protocolOptions = options.perProtocolOptions
            else {
                throw NetworkError.posix(EINVAL)
            }
            return protocolOptions
        }

        func setup(
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            throw NetworkError.posix(ENOTSUP)
        }

        func teardown() {
            preconditionFailure("teardown must be implemented by a SwiftTLSInstance subclass")
        }

        func connect(state: inout NetworkContext.State) {
            preconditionFailure("connect must be implemented by a SwiftTLSInstance subclass")
        }

        func disconnect(state: inout NetworkContext.State, error: NetworkError?) {
            preconditionFailure("disconnect must be implemented by a SwiftTLSInstance subclass")
        }

        func handleDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?) {
            preconditionFailure(
                "handleDisconnectedEvent must be implemented by a SwiftTLSInstance subclass"
            )
        }

        func sendStreamData(
            state: inout NetworkContext.State,
            _ streamData: consuming FrameArray
        ) throws(NetworkError) {
            throw NetworkError.posix(ENOTSUP)
        }

        func getOutboundStreamDataRoomAvailable(state: inout NetworkContext.State) throws(NetworkError) -> Int {
            throw NetworkError.posix(ENOTSUP)
        }

        func receiveStreamData(
            state: inout NetworkContext.State,
            minimumBytes: Int,
            maximumBytes: Int
        ) throws(NetworkError) -> FrameArray? {
            throw NetworkError.posix(ENOTSUP)
        }

        func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {
            preconditionFailure(
                "handleInboundDataAvailableEvent must be implemented by a SwiftTLSInstance subclass"
            )
        }
    }

    #if HAS_SWIFTTLS_RECORD && IMPORT_SWIFTTLS && canImport(SwiftTLS)
    /// A TLS instance that runs a full record layer, for stacks that are not carrying QUIC.
    final class SwiftTLSRecordInstance<LinkageFamily: StreamLinkageFamily>: SwiftTLSInstance<LinkageFamily> {
        private var recordLayer: SwiftTLSRecordLayerInstance?

        private func requireRecordLayer() throws(NetworkError) -> SwiftTLSRecordLayerInstance {
            guard let recordLayer else { throw NetworkError.posix(EINVAL) }
            return recordLayer
        }

        override func setup(
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            let protocolOptions = try perProtocolOptions(from: parameters)
            guard protocolOptions.tlsOptions.quicTransportParameters == nil else {
                // QUIC transport parameters mean this should have been a QUIC-only instance.
                throw NetworkError.posix(EINVAL)
            }
            recordLayer = try SwiftTLSRecordLayerInstance(self, protocolOptions, parameters)
        }

        override func teardown() {
            log.debug("")
            guard let recordLayer else { preconditionFailure("record layer unexpectedly nil") }
            recordLayer.teardown()
            self.recordLayer = nil
        }

        override func connect(state: inout NetworkContext.State) {
            log.debug("")
            guard let recordLayer else { preconditionFailure("record layer unexpectedly nil") }
            recordLayer.connect()
        }

        override func disconnect(state: inout NetworkContext.State, error: NetworkError?) {
            log.debug("")
            guard let recordLayer else { preconditionFailure("record layer unexpectedly nil") }
            recordLayer.disconnect(error: error)
        }

        override func handleDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?) {
            log.debug("")
            guard let recordLayer else { preconditionFailure("record layer unexpectedly nil") }
            recordLayer.handleDisconnectedEvent(error: error)
        }

        override func sendStreamData(
            state: inout NetworkContext.State,
            _ streamData: consuming FrameArray
        ) throws(NetworkError) {
            log.debug("")
            try requireRecordLayer().sendStreamData(streamData)
        }

        override func getOutboundStreamDataRoomAvailable(
            state: inout NetworkContext.State
        ) throws(NetworkError) -> Int {
            log.debug("")
            return try requireRecordLayer().getOutboundStreamDataRoomAvailable()
        }

        override func receiveStreamData(
            state: inout NetworkContext.State,
            minimumBytes: Int,
            maximumBytes: Int
        ) throws(NetworkError) -> FrameArray? {
            log.debug("")
            return try requireRecordLayer().receiveStreamData(
                minimumBytes: minimumBytes,
                maximumBytes: maximumBytes
            )
        }

        override func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {
            log.debug("")
            guard let recordLayer else { preconditionFailure("record layer unexpectedly nil") }
            recordLayer.handleInboundDataAvailableEvent(state: &state)
        }
    }
    #endif


    /// A TLS instance that runs only the handshake, with QUIC carrying the records.
    ///
    /// In addition to the stream linkage family shared with the rest of the hierarchy, this is
    /// generic over the QUIC linkage families, so that it can eventually hand typed linkages
    /// back to the QUIC instance for each encryption level (see the commented-out
    /// `getLowerLinkage` calls in `connect`).
    final class SwiftTLSQUICOnlyInstance<
        TLSLinkageFamily: StreamLinkageFamily,
        Families: QUICLinkageFamilies
    >: SwiftTLSInstance<TLSLinkageFamily> {
        var isConnected = false
        var isServer = false
        #if CLIENT_ONLY
        let handshaker = SwiftTLSHandshaker.createClientHandshake()
        #else
        #if SERVER_ONLY
        let handshaker = SwiftTLSHandshaker.createServerHandshake()
        #else
        // Client or server case
        var handshaker = SwiftTLSHandshaker.createClientHandshake()
        #endif
        #endif
        var serverSentHello = false
        var startedHandshake = false
        // Populated by `setup(remote:local:parameters:path:)`, which runs before anything else
        // touches the instance.
        var options = SwiftTLSProtocolOptions()

        /// The QUIC crypto instance this handshake feeds keys and transport parameters to.
        ///
        /// Held strongly, which forms a cycle with `QUICCrypto.tlsInstance`; `teardown()`
        /// breaks it by clearing this reference.
        private var quicCrypto: QUICCrypto<Families>?

        init(context: NetworkContext, quicCrypto: QUICCrypto<Families>?) {
            self.quicCrypto = quicCrypto
            super.init(context: context)
        }

        override func setup(
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            let protocolOptions = try perProtocolOptions(from: parameters)
            guard protocolOptions.tlsOptions.quicTransportParameters != nil else {
                // Without QUIC transport parameters this should have been a record-layer instance.
                throw NetworkError.posix(EINVAL)
            }
            self.options = protocolOptions
            if let parameters {
                isServer = parameters.isServer
            }
        }

        final class EncryptionLevelHandler: TopStreamProtocol, ProtocolInstanceContainer {
            typealias LinkageFamily = TLSLinkageFamily
            typealias LowerProtocol = LinkageFamily.Lower

            var lower = LowerProtocol()

            let level: SwiftTLSOptions.EncryptionLevel
            var parentInstance: SwiftTLSQUICOnlyInstance? {
                didSet {
                    // The context comes from parentInstance, so the reference can only be
                    // built once a parent has been assigned.
                    guard let parentInstance else { return }
                    reference = .init()
                    reference.setParentReference(parentInstance.reference)
                }
            }
            public var context: NetworkContext { parentInstance!.context }

            public var reference = ProtocolInstanceReference()

            var eventManager = ProtocolEventManager()

            init(level: SwiftTLSOptions.EncryptionLevel) { self.level = level }

            func destroy() {
                if !lower.isDetached {
                    try? lower.invokeDetach(state: &context.state, reference)
                    lower = LowerProtocol()
                }
                parentInstance = nil
            }

            func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {
                guard !lower.isDetached, let parentInstance else {
                    return
                }
                let frameArray = try? lower.invokeReceiveStreamData(
                    state: &state,
                    reference,
                    minimumBytes: 1,
                    maximumBytes: Int.max
                )
                guard var frameArray else {
                    return
                }

                while var frame = frameArray.popFirst() {
                    if let bytes = frame.span, !bytes.isEmpty {
                        do {
                            try parentInstance.continueHandshake(
                                state: &state,
                                with: [UInt8](copying: bytes, maxCount: bytes.count)
                            )
                        } catch {
                            parentInstance.log.error("Failed to continue handshake \(error)")
                            let handshakerErrorCode = parentInstance.handshaker.errorCode
                            if handshakerErrorCode != 0 {
                                parentInstance.reportError(state: &state, handshakerErrorCode)
                            }
                        }
                    } else {
                        frame.finalize(success: false)
                        continue
                    }

                    frame.finalize(success: true)
                }
            }

            func getOutboundStreamDataRoomAvailable(state: inout NetworkContext.State) throws(NetworkError) -> Int {
                guard !lower.isDetached else {
                    throw NetworkError.posix(EINVAL)
                }
                return try lower.invokeGetOutboundStreamDataRoomAvailable(state: &state, reference)
            }

            func sendStreamData(
                state: inout NetworkContext.State,
                _ streamData: consuming FrameArray
            ) throws(NetworkError) {
                guard !lower.isDetached else {
                    throw NetworkError.posix(EINVAL)
                }
                try lower.invokeSendStreamData(state: &state, reference, streamData: streamData)
            }
        }

        let initialDataHandler = EncryptionLevelHandler(level: .initial)
        let earlyDataHandler = EncryptionLevelHandler(level: .earlyData)
        let handshakeDataHandler = EncryptionLevelHandler(level: .handshake)
        let applicationDataHandler = EncryptionLevelHandler(level: .application)

        func continueHandshake(
            state: inout NetworkContext.State,
            with message: [UInt8]? = nil
        ) throws(TLSNetworkError) {
            var messageToProcess: [UInt8]? = message
            while true {

                // Loop to gather all handshake data into one message
                var dataToSend: [UInt8]?
                while true {
                    do {
                        let singleData = try handshaker.continueHandshake(with: messageToProcess)
                        if let singleData {
                            // Append to data to send
                            if dataToSend != nil {
                                dataToSend = dataToSend! + singleData
                            } else {
                                dataToSend = singleData
                            }

                            if !serverSentHello {
                                // Need to send the initial server message, break this inner loop
                                break
                            }
                        } else {
                            // No more data to send, break this inner loop
                            break
                        }
                    } catch {
                        throw TLSNetworkError.handshakeFailed
                    }
                }

                guard dataToSend != nil || messageToProcess != nil else {
                    // Exit loop if no progress
                    break
                }

                messageToProcess = nil
                if let quicCrypto {
                    if handshaker.earlyDataAccepted {
                        quicCrypto.updateEarlyDataAccepted(true)
                    }

                    if let peerQUICTransportParameters = handshaker.peerQUICTransportParameters {
                        quicCrypto.updatePeerQUICTransportParameters(peerQUICTransportParameters, earlyData: false)
                    }

                    let hasWriteEncryptionLevel = (handshaker.writeEncryptionLevel != .initial)
                    let hasReadEncryptionLevel = (handshaker.readEncryptionLevel != .initial)
                    if hasWriteEncryptionLevel || hasReadEncryptionLevel {
                        quicCrypto.updateNegotiatedCiphersuite(handshaker.negotiatedCiphersuite)
                        if hasReadEncryptionLevel, let readSecret = handshaker.readEncryptionSecret {
                            quicCrypto.updateSecret(readSecret, for: handshaker.readEncryptionLevel, isWrite: false)
                        }
                        if hasWriteEncryptionLevel, let writeSecret = handshaker.writeEncryptionSecret {
                            quicCrypto.updateSecret(writeSecret, for: handshaker.writeEncryptionLevel, isWrite: true)
                        }
                    }

                    if !handshaker.receivedSessionTickets.isEmpty {
                        let ticketArray = handshaker.receivedSessionTickets
                        handshaker.receivedSessionTickets = [[UInt8]]()
                        quicCrypto.updateSessionTickets(ticketArray)
                    }
                }

                if let dataToSend {
                    if isServer {
                        if serverSentHello {
                            sendMessage(state: &state, dataToSend, level: .handshake)
                        } else {
                            serverSentHello = true
                            sendMessage(state: &state, dataToSend, level: .initial)
                        }
                    } else {
                        sendMessage(state: &state, dataToSend, level: .handshake)
                    }
                } else if handshaker.errorCode != 0 {
                    reportError(state: &state, handshaker.errorCode)
                }

                if isServer {
                    if handshaker.readEncryptionLevel == .application {
                        completeHandshake(state: &state)
                    }
                } else {
                    if handshaker.writeEncryptionLevel == .application {
                        completeHandshake(state: &state)
                    }
                }
            }
        }

        func completeHandshake(state: inout NetworkContext.State) {
            let newlyConnected = !isConnected
            isConnected = true

            deliverConnectedEvent(state: &state)
            if !isServer, newlyConnected, let quicCrypto, !handshaker.earlyDataAccepted {
                quicCrypto.updateEarlyDataAccepted(false)
            }
        }

        func reportError(state: inout NetworkContext.State, _ error: Int32) {
            log.error("Reporting TLS error \(error)")
            deliverDisconnectedEvent(state: &state, error: NetworkError.posix(error))
        }

        func sendMessage(
            state: inout NetworkContext.State,
            _ message: [UInt8],
            level: SwiftTLSOptions.EncryptionLevel
        ) {
            let encryptionLevelHandler: EncryptionLevelHandler
            switch level {
            case .initial: encryptionLevelHandler = initialDataHandler
            case .earlyData: encryptionLevelHandler = earlyDataHandler
            case .handshake: encryptionLevelHandler = handshakeDataHandler
            case .application: encryptionLevelHandler = applicationDataHandler
            }

            try? encryptionLevelHandler.sendStreamData(state: &state, FrameArray(frame: Frame(copyBuffer: message)))
        }

        override func teardown() {
            #if canImport(SwiftTLS) && SWIFTTLS_CERTIFICATE_VERIFICATION
            handshaker.setAsyncContinuationHandler(nil)
            #endif
            initialDataHandler.destroy()
            handshakeDataHandler.destroy()
            earlyDataHandler.destroy()
            applicationDataHandler.destroy()
            quicCrypto = nil
        }

        // Disconnect and the disconnected event are passed straight through: QUIC owns the
        // connection lifetime, this instance only runs the handshake.
        override func disconnect(state: inout NetworkContext.State, error: NetworkError?) {
            log.debug("")
            invokeDisconnect(state: &state, error: error)
        }

        override func handleDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?) {
            log.debug("")
            deliverDisconnectedEvent(state: &state, error: error)
        }

        // Inbound data arrives through the per-encryption-level handlers, not here.
        override func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {
            log.debug("")
        }

        override func connect(state: inout NetworkContext.State) {
            guard !isConnected else {
                // Already connected, report
                deliverConnectedEvent(state: &state)
                return
            }

            guard !startedHandshake else {
                // Already started, ignore
                return
            }

            startedHandshake = true
            #if CLIENT_ONLY
            if isServer {
                log.error("Server TLS not supported")
                reportError(state: &state, EINVAL)
                return
            }
            #else
            #if SERVER_ONLY
            if !isServer {
                log.error("Client TLS not supported")
                reportError(state: &state, EINVAL)
                return
            }
            #else
            if isServer {
                // Switch to server mode
                handshaker = SwiftTLSHandshaker.createServerHandshake()
            }
            #endif
            #endif

            // We currently assume QUIC-only
            guard let quicCrypto else {
                log.error("Failed to find QUIC crypto instance")
                reportError(state: &state, EINVAL)
                return
            }

            // Link up the per-level handlers
            initialDataHandler.parentInstance = self
            earlyDataHandler.parentInstance = self
            handshakeDataHandler.parentInstance = self
            applicationDataHandler.parentInstance = self
//            initialDataHandler.lower = quicCrypto.getLowerLinkage(
//                for: .initial,
//                upperLinkage: initialDataHandler.asUpper
//            )
//            earlyDataHandler.lower = quicCrypto.getLowerLinkage(
//                for: .earlyData,
//                upperLinkage: earlyDataHandler.asUpper
//            )
//            handshakeDataHandler.lower = quicCrypto.getLowerLinkage(
//                for: .handshake,
//                upperLinkage: handshakeDataHandler.asUpper
//            )
//            applicationDataHandler.lower = quicCrypto.getLowerLinkage(
//                for: .application,
//                upperLinkage: applicationDataHandler.asUpper
//            )

            #if canImport(SwiftTLS) && SWIFTTLS_CERTIFICATE_VERIFICATION
            let contextBoundSelf = ContextBound(self, context: self.context)
            handshaker.setAsyncContinuationHandler { result in
                contextBoundSelf.value.async {
                    contextBoundSelf.value.handshaker.setAsyncResult(result)
                    let instance = contextBoundSelf.value
                    do {
                        try instance.continueHandshake(state: &instance.context.state)
                    } catch {
                        instance.log.error("Failed to continue handshake \(error)")
                        let handshakerErrorCode = instance.handshaker.errorCode
                        if handshakerErrorCode != 0 {
                            instance.reportError(state: &instance.context.state, handshakerErrorCode)
                        }
                    }
                }
            }
            #endif

            if isServer {
                do {
                    let handshakeBytes = try handshaker.setupHandshake(options: options.tlsOptions)
                    guard handshakeBytes == nil else {
                        log.error("Server handshaker unexpectedly set up bytes")
                        reportError(state: &state, EINVAL)
                        return
                    }
                } catch {
                    log.error("Failed to set up server handshaker")
                    reportError(state: &state, EINVAL)
                    return
                }
            } else {
                guard let handshakeBytesToSend = try? handshaker.setupHandshake(options: options.tlsOptions) else {
                    log.error("Failed to set up client handshaker")
                    reportError(state: &state, EINVAL)
                    return
                }

                sendMessage(state: &state, handshakeBytesToSend, level: .initial)
            }

            // Update the encryption secrets for early data
            if handshaker.writeEncryptionLevel != .initial {
                if handshaker.writeEncryptionLevel == .earlyData,
                    let earlyDataTransportParameters = options.resumedQUICTransportParameters
                {
                    quicCrypto.updatePeerQUICTransportParameters(earlyDataTransportParameters, earlyData: true)
                }

                quicCrypto.updateNegotiatedCiphersuite(handshaker.negotiatedCiphersuite)
                if let readSecret = handshaker.readEncryptionSecret {
                    quicCrypto.updateSecret(readSecret, for: handshaker.readEncryptionLevel, isWrite: false)
                }
                if let writeSecret = handshaker.writeEncryptionSecret {
                    quicCrypto.updateSecret(writeSecret, for: handshaker.writeEncryptionLevel, isWrite: true)
                }
            }
        }

        // Application data never flows through the TLS instance in QUIC mode: QUIC carries the
        // records itself, so these stay unsupported rather than merely unimplemented.
        override func sendStreamData(
            state: inout NetworkContext.State,
            _ streamData: consuming FrameArray
        ) throws(NetworkError) {
            throw NetworkError.posix(ENOTSUP)
        }

        override func getOutboundStreamDataRoomAvailable(
            state: inout NetworkContext.State
        ) throws(NetworkError) -> Int {
            throw NetworkError.posix(ENOTSUP)
        }

        override func receiveStreamData(
            state: inout NetworkContext.State,
            minimumBytes: Int,
            maximumBytes: Int
        ) throws(NetworkError) -> FrameArray? {
            throw NetworkError.posix(ENOTSUP)
        }
    }

    public func newProtocolInstance(context: NetworkContext) -> ProtocolInstanceReference? {
        nil
    }

    public func newPerProtocolOptions() -> SwiftTLSProtocolOptions? { SwiftTLSProtocolOptions() }
    public func newPerProtocolOptions(from existing: SwiftTLSProtocolOptions) -> SwiftTLSProtocolOptions { existing }
    public func newPerProtocolOptions(from serializedBytes: [UInt8]) -> SwiftTLSProtocolOptions? { nil }
    public func newPerProtocolMetadata() -> SwiftTLSMetadata? { SwiftTLSMetadata() }

    static public let identifier = ProtocolIdentifier(name: "swift-tls", level: .application, mapping: .oneToOne)
    #if !NETWORK_PRIVATE
    static let definition = ProtocolDefinition<SwiftTLSProtocol>(identifier: identifier)
    #endif

    static public func options() -> ProtocolOptions<SwiftTLSProtocol> { SwiftTLSProtocol.definition.protocolOptions() }

    static public func instance(context: NetworkContext) -> ProtocolInstanceReference {
        SwiftTLSProtocol().newProtocolInstance(context: context)!
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension ProtocolOptions<SwiftTLSProtocol> {
    public var tlsOptions: SwiftTLSProtocol.Options {
        get {
            perProtocolOptions ?? SwiftTLSProtocol.Options()
        }
        set {
            perProtocolOptions?.tlsOptions = newValue.tlsOptions
        }
    }
}

#if !IMPORT_SWIFTTLS || !canImport(SwiftTLS)

// Stubs for Swift TLS
enum SwiftTLSError: Int, Error, CustomStringConvertible {
    case handshakeFailed
    case invalidTransportParameters
    case internalTLSError

    var description: String {
        switch self {
        case .handshakeFailed: return "Handshake Failed"
        case .invalidTransportParameters: return "Invalid Transport Parameters"
        case .internalTLSError: return "TLS Error: Check error from SwiftTLS"
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct SwiftTLSOptions {
    @frozen public enum EncryptionLevel: CustomDebugStringConvertible {
        case initial
        case earlyData
        case handshake
        case application

        public var debugDescription: String {
            switch self {
            case .initial: return "initial"
            case .earlyData: return "early data"
            case .handshake: return "handshake"
            case .application: return "application"
            }
        }
    }

    public var trustedRawPublicKeyCertificates: [[UInt8]]?
    public var rawPrivateKey: [UInt8]?
    public var quicTransportParameters: [UInt8]?
    public var enableEarlyData: Bool = false
    public var applicationProtocols: [String]?
    public var serverName: String? = nil
    public enum KeyExchangeGroup: UInt16 {
        case secp256 = 0x0017
        case secp384 = 0x0018
        case x25519 = 0x001D
        case x25519MLKEM768 = 0x11EC
    }
    public var keyExchangeGroup: KeyExchangeGroup = .secp384

    // When true, server sends CertificateRequest to client during TLS handshake
    public var clientAuthRequired: Bool = false

    public init() {}
}

@available(Network 0.1.0, *)
class SwiftTLSHandshaker {
    public static func createClientHandshake() -> SwiftTLSHandshaker {
        SwiftTLSHandshaker()
    }

    public static func createServerHandshake() -> SwiftTLSHandshaker {
        SwiftTLSHandshaker()
    }

    public var receivedSessionTickets = [[UInt8]]()

    public var errorCode: Int32 { 0 }

    public func setupHandshake(options: SwiftTLSOptions) throws -> [UInt8]? { nil }

    public var writeEncryptionLevel: SwiftTLSOptions.EncryptionLevel { .initial }

    public var readEncryptionLevel: SwiftTLSOptions.EncryptionLevel { .initial }

    public var negotiatedCiphersuite: Int { 0 }

    public var peerQUICTransportParameters: [UInt8]? { nil }

    public var earlyDataAccepted: Bool { false }

    public var readEncryptionSecret: [UInt8]? { nil }

    public var writeEncryptionSecret: [UInt8]? { nil }

    public func continueHandshake(with message: [UInt8]?) throws -> [UInt8]? { nil }
}
#endif
