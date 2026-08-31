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

// TODO: TFPDEBUG Top protocols need to unregister their event managers

// MARK: - Top Protocol Adoption

/// Top protocols sit at the top of a stack and have only a lower protocol.
///
/// Conform to `TopStreamProtocol` or `TopDatagramProtocol`.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol TopProtocolHandler: ~Copyable, InboundDataHandler {

    /// The type of lower protocol (toward the network) that you can attach.
    var lower: LowerProtocol { get set }

    /// A function the framework calls when the lower protocol connects.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleConnectedEvent(state: inout NetworkContext.State)

    /// A function the framework calls when the lower protocol disconnects.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?)

    /// A function the framework calls when a lower protocol sends an event.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleNetworkProtocolEvent(state: inout NetworkContext.State, _ event: NetworkProtocolEvent)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol TopDatapathProtocol: ~Copyable, TopProtocolHandler where LowerProtocol: OutboundDataLinkage {

    /// A function the framework calls when the lower protocol has inbound data available to read.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleInboundDataAvailableEvent(state: inout NetworkContext.State)

    /// A function the framework calls when the lower protocol has outbound room available to send.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleOutboundRoomAvailableEvent(state: inout NetworkContext.State)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension TopProtocolHandler where Self: ~Copyable {
    /// Requests that the lower protocol start connecting.
    ///
    /// This is an external entry point: call it from code outside the protocol stack, such as an
    /// app or a unit test. If you already hold the context state, call the `state:`-taking
    /// variant instead so the state isn't re-derived from the context.
    public func invokeConnect() {
        fromExternal { state in
            invokeConnect(state: &state)
        }
    }

    /// Requests that the lower protocol start connecting, using an already-acquired context state.
    public func invokeConnect(state: inout NetworkContext.State) {
        lower.invokeConnect(state: &state, self.reference)
    }

    /// Requests that the lower protocol disconnect.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeDisconnect(error: NetworkError?) {
        fromExternal { state in
            invokeDisconnect(state: &state, error: error)
        }
    }

    /// Requests that the lower protocol disconnect, using an already-acquired context state.
    public func invokeDisconnect(state: inout NetworkContext.State, error: NetworkError?) {
        lower.invokeDisconnect(state: &state, self.reference, error: error)
    }

    /// Detaches the lower protocol.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public mutating func invokeDetach() throws(NetworkError) {
        try fromExternal { state throws(NetworkError) in
            try lower.invokeDetach(state: &state, self.reference)
        }
        lower = .init()
    }

    /// Detaches the lower protocol, using an already-acquired context state.
    public mutating func invokeDetach(state: inout NetworkContext.State) throws(NetworkError) {
        try lower.invokeDetach(state: &state, self.reference)
        lower = .init()
    }

    /// Signals an application-level event to lower protocols.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeApplicationEvent(_ event: ApplicationEvent) {
        fromExternal { state in
            invokeApplicationEvent(state: &state, event)
        }
    }

    /// Signals an application-level event to lower protocols, using an already-acquired context state.
    public func invokeApplicationEvent(state: inout NetworkContext.State, _ event: ApplicationEvent) {
        lower.invokeApplicationEvent(state: &state, self.reference, event: event)
    }

    /// Accesses protocol metadata from a lower protocol.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeGetMetadata<P: NetworkProtocol>() -> ProtocolMetadata<P>? {
        fromExternal { state in
            invokeGetMetadata(state: &state)
        }
    }

    /// Accesses protocol metadata from a lower protocol, using an already-acquired context state.
    public func invokeGetMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State
    ) -> ProtocolMetadata<P>? {
        lower.invokeGetMetadata(state: &state, self.reference)
    }
}

/// Top protocol with a lower stream linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol TopStreamProtocol: ~Copyable, TopDatapathProtocol, InboundStreamHandler
where LowerProtocol == OutboundStreamLinkage {
    /// A function the framework calls when the lower protocol reports that inbound stream data is aborted.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleInboundAbortedEvent(state: inout NetworkContext.State, error: NetworkError?)

    /// A function the framework calls when the lower protocol reports that outbound stream data is aborted.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleOutboundAbortedEvent(state: inout NetworkContext.State, error: NetworkError?)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension TopStreamProtocol where Self: ~Copyable {
    /// Receives stream data from the lower protocol.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeReceiveStreamData(minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray? {
        try fromExternal { state throws(NetworkError) in
            try invokeReceiveStreamData(state: &state, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
        }
    }

    /// Receives stream data from the lower protocol, using an already-acquired context state.
    public func invokeReceiveStreamData(
        state: inout NetworkContext.State,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        try lower.invokeReceiveStreamData(
            state: &state,
            self.reference,
            minimumBytes: minimumBytes,
            maximumBytes: maximumBytes
        )
    }

    /// Returns the number of bytes of stream data you can send to the lower protocol.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeGetOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int {
        try fromExternal { state throws(NetworkError) in
            try invokeGetOutboundStreamDataRoomAvailable(state: &state)
        }
    }

    /// Returns the number of bytes of stream data you can send to the lower protocol, using an
    /// already-acquired context state.
    public func invokeGetOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State
    ) throws(NetworkError) -> Int {
        try lower.invokeGetOutboundStreamDataRoomAvailable(state: &state, self.reference)
    }

    /// Sends stream data to the lower protocol.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeSendStreamData(_ streamData: consuming FrameArray) throws(NetworkError) {
        try fromExternal(streamData) { state, streamData throws(NetworkError) in
            try invokeSendStreamData(state: &state, streamData)
        }
    }

    /// Sends stream data to the lower protocol, using an already-acquired context state.
    public func invokeSendStreamData(
        state: inout NetworkContext.State,
        _ streamData: consuming FrameArray
    ) throws(NetworkError) {
        try lower.invokeSendStreamData(state: &state, self.reference, streamData: streamData)
    }

    /// Sends early stream data to the lower protocol.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeSendEarlyStreamData(_ streamData: consuming FrameArray) throws(NetworkError) {
        try fromExternal(streamData) { state, streamData throws(NetworkError) in
            try invokeSendEarlyStreamData(state: &state, streamData)
        }
    }

    /// Sends early stream data to the lower protocol, using an already-acquired context state.
    public func invokeSendEarlyStreamData(
        state: inout NetworkContext.State,
        _ streamData: consuming FrameArray
    ) throws(NetworkError) {
        try lower.invokeSendEarlyStreamData(state: &state, self.reference, streamData: streamData)
    }
}

/// Top protocol with a lower datagram linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol TopDatagramProtocol: ~Copyable, TopDatapathProtocol, InboundDatagramHandler
where LowerProtocol: OutboundDatagramLinkage {

}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension TopDatagramProtocol where Self: ~Copyable, Self: ~Copyable {
    /// Receives datagrams from the lower protocol.
    ///
    /// This is an external entry point; see `invokeConnect()`.
    public func invokeReceiveDatagrams(maximumDatagramCount: Int) throws(NetworkError) -> FrameArray? {
        try fromExternal { state throws(NetworkError) in
            try invokeReceiveDatagrams(state: &state, maximumDatagramCount: maximumDatagramCount)
        }
    }

    /// Receives datagrams from the lower protocol, using an already-acquired context state.
    public func invokeReceiveDatagrams(
        state: inout NetworkContext.State,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        try lower.invokeReceiveDatagrams(state: &state, self.reference, maximumDatagramCount: maximumDatagramCount)
    }

    /// Returns datagram memory you can write into, from the lower protocol.
    public func invokeGetDatagramsToSend(
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        try fromExternal { state throws(NetworkError) in
            try invokeGetDatagramsToSend(
                state: &state,
                maximumDatagramCount: maximumDatagramCount,
                minimumDatagramSize: minimumDatagramSize
            )
        }
    }

    /// Returns datagram memory you can write into, using an already-acquired context state.
    public func invokeGetDatagramsToSend(
        state: inout NetworkContext.State,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        try lower.invokeGetDatagramsToSend(
            state: &state,
            self.reference,
            maximumDatagramCount: maximumDatagramCount,
            minimumDatagramSize: minimumDatagramSize
        )
    }

    /// Sends previously retrieved datagrams to the lower protocol.
    ///
    /// Sends datagrams previously retrieved with `invokeGetDatagramsToSend`.
    public func invokeSendDatagrams(_ datagrams: consuming FrameArray) throws(NetworkError) {
        try fromExternal(datagrams) { state, datagrams throws(NetworkError) in
            try invokeSendDatagrams(state: &state, datagrams)
        }
    }

    /// Sends previously retrieved datagrams to the lower protocol, using an already-acquired
    /// context state.
    public func invokeSendDatagrams(
        state: inout NetworkContext.State,
        _ datagrams: consuming FrameArray
    ) throws(NetworkError) {
        try lower.invokeSendDatagrams(state: &state, self.reference, datagrams: datagrams)
    }
}

// MARK: - Top Protocol Implementation Details

@available(Network 0.1.0, *)
extension TopProtocolHandler where Self: ~Copyable {
    // TODO: TFPDEBUG remove
    var asUpper: LowerProtocol.PairedLinkage { .init() }

    internal func validate(
        lower lowerProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard !lowerProtocol.isNone else {
            Logger.proto.error("Received \'\(label)\' from incorrect lower protocol")
            throw ProtocolInstanceError.invalidLowerProtocol
        }
        #endif
    }

    public mutating func attachLowerProtocol(
        _ lowerProtocol: LowerProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        throw NetworkError.posix(EINVAL)

//        guard lower.isDetached else {
//            throw NetworkError.posix(EALREADY)
//        }
//        lower = lowerProtocol
//        try lowerProtocol.invokeAttachUpperProtocol(
//            asUpper,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleConnectedEvent(state: &state)
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleDisconnectedEvent(state: &state, error: error)
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        // Don't validate lower, can pass through
        self.handleNetworkProtocolEvent(state: &state, event)
    }
}

// Default implementations, to be overridden as necessary
@available(Network 0.1.0, *)
extension TopProtocolHandler where Self: ~Copyable {
    public func handleConnectedEvent(state: inout NetworkContext.State) {}

    public func handleDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?) {}

    public func handleNetworkProtocolEvent(state: inout NetworkContext.State, _ event: NetworkProtocolEvent) {}
}

@available(Network 0.1.0, *)
extension TopDatapathProtocol where Self: ~Copyable {
    public func handleInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleInboundDataAvailableEvent(state: &state)
    }

    public func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleOutboundRoomAvailableEvent(state: &state)
    }
}

@available(Network 0.1.0, *)
extension TopDatapathProtocol where Self: ~Copyable {
    // Default implementations, to be overridden as necessary
    public func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {}

    public func handleOutboundRoomAvailableEvent(state: inout NetworkContext.State) {}
}

@available(Network 0.1.0, *)
extension TopProtocolHandler where Self: ~Copyable, LowerProtocol == OutboundStreamLinkage {
    public mutating func attachLowerStreamProtocolToExistingFlow(
        listener: StreamListenerLinkage,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) {
        guard lower.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        self.lower = try listener.invokeAttachUpperStreamProtocolToExistingFlow(
            reference,
            flowReference: flowReference
        )
    }
}

@available(Network 0.1.0, *)
extension TopStreamProtocol where Self: ~Copyable {
    public func handleInboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleInboundAbortedEvent(state: &state, error: error)
    }

    public func handleOutboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleOutboundAbortedEvent(state: &state, error: error)
    }
}

@available(Network 0.1.0, *)
extension TopStreamProtocol where Self: ~Copyable {
    // Default implementations, to be overridden as necessary
    public func handleInboundAbortedEvent(state: inout NetworkContext.State, error: NetworkError?) {}

    public func handleOutboundAbortedEvent(state: inout NetworkContext.State, error: NetworkError?) {}
}
