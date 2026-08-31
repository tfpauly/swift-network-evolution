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
#elseif canImport(Musl)
import Musl
internal import Logging
#elseif canImport(os)
internal import os
#endif

// MARK: - Bottom Protocol Adoption

/// Bottom protocols sit at the bottom of a stack and have only an upper protocol.
///
/// Conform to `BottomStreamProtocol` or `BottomDatagramProtocol`.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol BottomProtocolHandler<LinkageFamily>: ~Copyable, OutboundDataHandler {
    associatedtype LinkageFamily: DataLinkageFamily

    /// The type of upper protocol (toward the app) that you can attach.
    var upper: LinkageFamily.Upper { get set }

    /// Sets up a protocol instance with parameters and endpoints.
    ///
    /// Protocols can implement this function to customize behavior.
    func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    /// Tears down a protocol when detaching.
    ///
    /// Protocols can implement this function to customize behavior.
    func teardown()

    /// Requests that this protocol initiate its handshake, if any.
    ///
    /// If not implemented, the protocol delivers the connected event automatically.
    /// Protocols can implement this function to customize behavior.
    func connect()

    /// Requests that this protocol initiate its handshake, with the context state already
    /// acquired by the framework.
    ///
    /// The default implementation forwards to `connect()`. Implement this instead when the
    /// protocol needs to call back into the stack, so the state isn't re-derived from the
    /// context.
    func connect(state: inout NetworkContext.State)

    /// Requests that this protocol gracefully close.
    ///
    /// Protocols can implement this function to customize behavior.
    func disconnect()

    /// Requests that this protocol gracefully close, with the context state already acquired
    /// by the framework.
    ///
    /// The default implementation forwards to `disconnect()`. See `connect(state:)`.
    func disconnect(state: inout NetworkContext.State)

    /// Handles an event the app sent.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleApplicationEvent(_ event: ApplicationEvent)

    #if !NETWORK_EMBEDDED
    /// The metadata state for this protocol.
    var metadata: AbstractProtocolMetadata? { get }
    #endif

    /// Update this protocols contribution to a data transfer snapshot.
    func updateDataTransferSnapshot(_ snapshot: inout DataTransferSnapshot)

    /// Fetch this protocols establishment report entry
    var protocolEstablishmentReport: ProtocolEstablishmentReport? { get }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension BottomProtocolHandler where Self: ~Copyable {
    /// Indicates to the upper protocol that this protocol is connected.
    ///
    /// Call this only if the protocol customizes `connect()`.
    ///
    /// This is an external entry point: call it from code outside the protocol stack, such as
    /// a socket readiness callback. If you already hold the context state, call the
    /// `state:`-taking variant instead so the state isn't re-derived from the context.
    public func deliverConnectedEvent() {
        fromExternal { state in
            deliverConnectedEvent(state: &state)
        }
    }

    /// Indicates to the upper protocol that this protocol is connected, using an
    /// already-acquired context state.
    public func deliverConnectedEvent(state: inout NetworkContext.State) {
        upper.deliverConnectedEvent(state: &state, self.reference)
    }

    /// Indicates to the upper protocol that this protocol is disconnected, with an error.
    ///
    /// This is an external entry point; see `deliverConnectedEvent()`.
    public func deliverDisconnectedEvent(error: NetworkError?) {
        fromExternal { state in
            deliverDisconnectedEvent(state: &state, error: error)
        }
    }

    /// Indicates to the upper protocol that this protocol is disconnected, using an
    /// already-acquired context state.
    public func deliverDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?) {
        upper.deliverDisconnectedEvent(state: &state, self.reference, error: error)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension BottomProtocolHandler where Self: ~Copyable, UpperProtocol: InboundDataLinkage {
    /// Indicates to the upper protocol that this protocol has data available to read.
    ///
    /// This is an external entry point; see `deliverConnectedEvent()`.
    public func deliverInboundDataAvailableEvent() {
        fromExternal { state in
            deliverInboundDataAvailableEvent(state: &state)
        }
    }

    /// Indicates to the upper protocol that this protocol has data available to read, using an
    /// already-acquired context state.
    public func deliverInboundDataAvailableEvent(state: inout NetworkContext.State) {
        guard isConnected(state: &state) else { return }
        upper.deliverInboundDataAvailableEvent(state: &state, self.reference)
    }

    /// Indicates to the upper protocol that this protocol has room available to send.
    ///
    /// This is an external entry point; see `deliverConnectedEvent()`.
    public func deliverOutboundRoomAvailableEvent() {
        fromExternal { state in
            deliverOutboundRoomAvailableEvent(state: &state)
        }
    }

    /// Indicates to the upper protocol that this protocol has room available to send, using an
    /// already-acquired context state.
    public func deliverOutboundRoomAvailableEvent(state: inout NetworkContext.State) {
        guard isConnected(state: &state) else { return }
        upper.deliverOutboundRoomAvailableEvent(state: &state, self.reference)
    }

    /// Passes an event to the upper protocol.
    ///
    /// This is an external entry point; see `deliverConnectedEvent()`.
    public func deliverNetworkProtocolEvent(_ event: NetworkProtocolEvent) {
        fromExternal { state in
            deliverNetworkProtocolEvent(state: &state, event)
        }
    }

    /// Passes an event to the upper protocol, using an already-acquired context state.
    public func deliverNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ event: NetworkProtocolEvent
    ) {
        upper.deliverNetworkProtocolEvent(
            state: &state,
            originalReference: self.reference,
            selfReference: self.reference,
            event: event
        )
    }
}

/// Bottom protocol with an upper stream linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol BottomStreamProtocol: ~Copyable, BottomProtocolHandler, OutboundStreamHandler
where LinkageFamily: StreamLinkageFamily, LinkageFamily.Upper == UpperProtocol {

    /// Returns received stream data to the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func receiveStreamData(minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray?

    /// Returns the number of bytes of stream data that can be written.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func getOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int

    /// Sends stream data created by the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func sendStreamData(_ streamData: consuming FrameArray) throws(NetworkError)
}

/// Bottom protocol with an upper datagram linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol BottomDatagramProtocol: ~Copyable, BottomProtocolHandler, OutboundDatagramHandler
where LinkageFamily: DatagramLinkageFamily, LinkageFamily.Upper == UpperProtocol {

    /// Returns received datagrams to the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func receiveDatagrams(maximumDatagramCount: Int) throws(NetworkError) -> FrameArray?

    /// Returns datagram frames the upper protocol can use to send.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func getDatagramsToSend(
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?

    /// Sends datagrams created by the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func sendDatagrams(_ datagrams: consuming FrameArray) throws(NetworkError)
}

// MARK: - Bottom Protocol Implementation Details

@available(Network 0.1.0, *)
extension BottomProtocolHandler where Self: ~Copyable {
//    var asLower: LinkageFamily.Lower { .init(reference: reference) }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        // Don't validate upper, can pass through
        self.handleApplicationEvent(event)
    }

    internal func validate(
        upper upperProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard upperProtocol == upper.reference else {
            Logger.proto.fault("Received \'\(label)\' from incorrect upper protocol")
            throw ProtocolInstanceError.invalidUpperProtocol
        }
        #endif
    }

    public mutating func attachUpperProtocol(
        _ upperProtocol: LinkageFamily.Upper,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard upper.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        upper = upperProtocol

        do {
            try self.setup(remote: remote, local: local, parameters: parameters, path: path)
        } catch let error {
            upper = .init()
            throw error
        }
    }

    public mutating func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        upper = .init()
        teardown()
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        do { try validate(upper: from, #function) } catch { return }
        if canCallConnect(state: &state, requested: true) {
            connect(state: &state)
        }
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(upper: from, #function) } catch { return }
        if canCallDisconnect(state: &state) {
            disconnect(state: &state)
        }
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        do { try validate(upper: from, #function) } catch { return nil }
        #if !NETWORK_EMBEDDED
        if let metadata = self.metadata as? ProtocolMetadata<P> {
            return metadata
        }
        #endif
        return nil
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        do { try validate(upper: from, #function) } catch { return nil }
        switch requestedNetworkMetric {
        case .protocolEstablishmentReports:
            guard let report = protocolEstablishmentReport else { return nil }
            return .protocolEstablishmentReports([report])
        case .dataTransferSnapshot:
            var snapshot = DataTransferSnapshot()
            updateDataTransferSnapshot(&snapshot)
            return .dataTransferSnapshot(snapshot)
        }
    }

    #if !NETWORK_EMBEDDED
    public func getOptions<T>(from parameters: Parameters) -> ProtocolOptions<T>? {
        parameters.protocolOptions(for: self.reference)
    }
    public func getOptions(from parameters: Parameters) -> AbstractProtocolOptions? {
        parameters.protocolOptions(for: self.reference)
    }
    #endif
}

// Default implementations, to be overridden as necessary
@available(Network 0.1.0, *)
extension BottomProtocolHandler where Self: ~Copyable {
    public func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {}

    public func teardown() {}

    public func connect() {
        deliverConnectedEvent()
    }

    public func connect(state: inout NetworkContext.State) {
        deliverConnectedEvent(state: &state)
    }

    public func disconnect() {
        deliverDisconnectedEvent(error: nil)
    }

    public func disconnect(state: inout NetworkContext.State) {
        deliverDisconnectedEvent(state: &state, error: nil)
    }

    public func handleApplicationEvent(_ event: ApplicationEvent) {}

    #if !NETWORK_EMBEDDED
    public var metadata: AbstractProtocolMetadata? { nil }
    #endif

    public func updateDataTransferSnapshot(_ snapshot: inout DataTransferSnapshot) {}

    public var protocolEstablishmentReport: ProtocolEstablishmentReport? { nil }
}

@available(Network 0.1.0, *)
extension BottomDatagramProtocol where Self: ~Copyable {
    public mutating func receiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected(state: &state) else { throw NetworkError.posix(ENOTCONN) }
        return try self.receiveDatagrams(maximumDatagramCount: maximumDatagramCount)
    }
    public mutating func getDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected(state: &state) else { throw NetworkError.posix(ENOTCONN) }
        return try self.getDatagramsToSend(
            maximumDatagramCount: maximumDatagramCount,
            minimumDatagramSize: minimumDatagramSize
        )
    }
    public mutating func sendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch {
            datagrams.finalizeAllFramesAsFailed()
            throw NetworkError.posix(EINVAL)
        }
        guard isConnected(state: &state) else {
            datagrams.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try self.sendDatagrams(datagrams)
    }
}

@available(Network 0.1.0, *)
extension BottomStreamProtocol where Self: ~Copyable {
    public mutating func receiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected(state: &state) else { throw NetworkError.posix(ENOTCONN) }
        return try self.receiveStreamData(minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }
    public mutating func getOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected(state: &state) else { throw NetworkError.posix(ENOTCONN) }
        return try self.getOutboundStreamDataRoomAvailable()
    }
    public mutating func sendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(EINVAL)
        }
        guard isConnected(state: &state) else {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try self.sendStreamData(streamData)
    }
}
