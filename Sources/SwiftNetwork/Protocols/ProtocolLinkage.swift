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

/// Linkage pairs

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
// Linkage families are empty type-level tags that name a set of paired linkages. They carry
// no state, so their metatypes are safe to capture across isolation boundaries.
public protocol LinkageFamily: Sendable {
    associatedtype Upper: UpperProtocolLinkage
    associatedtype Lower: LowerProtocolLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol DataLinkageFamily: LinkageFamily where Upper: InboundDataLinkage, Lower: OutboundDataLinkage {
    associatedtype Listener: ListenerLinkage
    associatedtype InboundFlow: InboundFlowLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol DatagramLinkageFamily: DataLinkageFamily where Upper: InboundDatagramLinkage, Lower: OutboundDatagramLinkage, Listener: DatagramListenerLinkage, InboundFlow: InboundDatagramFlowLinkage, InboundFlow.DataLinkage == Lower, Listener.PairedLinkage.DataLinkage == Lower { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol StreamLinkageFamily: DataLinkageFamily where Upper: InboundStreamLinkage, Lower: OutboundStreamLinkage, Listener: StreamListenerLinkage, InboundFlow: InboundStreamFlowLinkage, InboundFlow.DataLinkage == Lower, Listener.PairedLinkage.DataLinkage == Lower { }

/// A strongly typed structure that holds a reference to another protocol and dispatches functions to it.
///
/// Each linkage is paired with a matching linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ProtocolLinkage: Hashable {
    associatedtype PairedLinkage: ProtocolLinkage
    init()
    var reference: ProtocolInstanceReference { get }
}

@available(Network 0.1.0, *)
extension ProtocolLinkage {
    public var isDetached: Bool {
        self.reference.isNone
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol UpperProtocolLinkage: ProtocolLinkage where PairedLinkage: LowerProtocolLinkage {
    // TODO: TFPDEBUG Move these out of the protocol and into implementation?
    func deliverConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    func deliverDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )
    func deliverNetworkProtocolEvent(
        state: inout NetworkContext.State,
        originalReference: ProtocolInstanceReference,
        selfReference: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    )

    /// `invokeAttachLowerProtocol` is the general entry point to connecting protocols. It will
    /// call `invokeAttachUpperProtocol` on the lower protocol.
    func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    // TODO: TFPDEBUG These are the ones callers need to implement
    func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )
    func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    )
}

@available(Network 0.1.0, *)
extension UpperProtocolLinkage {
    public func deliverConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        from.deliverEventToUpperProtocol(state: &state, event: .connected(from, self.reference, { state, from in
            self.handleConnectedEvent(state: &state, from)
        }))
    }
    public func deliverDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        from.deliverEventToUpperProtocol(
            state: &state,
            event: .disconnected(from, self.reference, error: error, { state, from, error in
                self.handleDisconnectedEvent(state: &state, from, error: error)
            })
        )
    }
    public func deliverNetworkProtocolEvent(
        state: inout NetworkContext.State,
        originalReference: ProtocolInstanceReference,
        selfReference: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        selfReference.deliverEventToUpperProtocol(
            state: &state,
            event: .networkProtocolEvent(originalReference, self.reference, event: event, { state, from, event in
                self.handleNetworkProtocolEvent(state: &state, from, event: event)
            })
        )
    }
//    public func invokeAttachLowerProtocol(
//        _ lowerProtocol: PairedLinkage,
//        remote: Endpoint?,
//        local: Endpoint?,
//        parameters: Parameters?,
//        path: PathProperties?
//    ) throws(NetworkError) {
//        try reference.attachLowerProtocol(
//            lowerProtocol,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
//    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDataLinkage: UpperProtocolLinkage where PairedLinkage: OutboundDataLinkage {
    func deliverInboundDataAvailableEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    func deliverOutboundRoomAvailableEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)

    // TODO: TFPDEBUG These are the ones callers need to implement
    func handleInboundDataAvailableEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    func handleOutboundRoomAvailableEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
}

@available(Network 0.1.0, *)
extension InboundDataLinkage {
    public func deliverInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        from.deliverEventToUpperProtocol(
            state: &state,
            event: .inboundDataAvailable(from, self.reference, { state, from in
                self.handleInboundDataAvailableEvent(state: &state, from)
            })
        )
    }
    public func deliverOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        from.deliverEventToUpperProtocol(
            state: &state,
            event: .outboundRoomAvailable(from, self.reference, { state, from in
                self.handleOutboundRoomAvailableEvent(state: &state, from)
            })
        )
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundFlowLinkage: UpperProtocolLinkage where PairedLinkage: ListenerLinkage {
    associatedtype DataLinkage: OutboundDataLinkage
    func deliverNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    )

    // TODO: TFPDEBUG These are the ones callers need to implement
    func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    )
}

@available(Network 0.1.0, *)
extension InboundFlowLinkage {
    public func deliverNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        from.deliverEventToUpperProtocol(
            state: &state,
            event: .newInboundFlow(
                from,
                self.reference,
                flowReference: flowReference,
                flowMetadata: flowMetadata,
                { state, from, flowReference, flowMetadata in
                    self.handleNewInboundFlowEvent(
                        state: &state,
                        from,
                        flowReference: flowReference,
                        flowMetadata: flowMetadata
                    )
                }
            )
        )
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ListenerLinkage: LowerProtocolLinkage where PairedLinkage: InboundFlowLinkage {
    #if !NETWORK_EMBEDDED
    func invokeAttachUpperProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self.PairedLinkage.DataLinkage

    func invokeAttachUpperProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> Self.PairedLinkage.DataLinkage
    #endif
}

@available(Network 0.1.0, *)
extension ListenerLinkage {
    #if !NETWORK_EMBEDDED
    public func invokeAttachUpperProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self.PairedLinkage.DataLinkage {
        throw .posix(1)
//        try reference.attachUpperProtocolToNewFlow(
//            from,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
//        return .init(reference: from)
    }

    public func invokeAttachUpperProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> Self.PairedLinkage.DataLinkage {
        throw .posix(1)

//        try reference.attachUpperProtocolToExistingFlow(
//            from,
//            flowReference: flowReference
//        )
//        return .init(reference: from)
    }
    #endif
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundDataLinkage: LowerProtocolLinkage where PairedLinkage: InboundDataLinkage {}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol LowerProtocolLinkage: ProtocolLinkage where PairedLinkage: UpperProtocolLinkage {
    func isConnected(state: inout NetworkContext.State) -> Bool
    func invokeConnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    func invokeDisconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?)
    func invokeAttachUpperProtocol(
        _ upperProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)
    func invokeDetach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError)
    func invokeApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    )
    func invokeGetMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>?
    func invokeGetMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics?
}

@available(Network 0.1.0, *)
extension LowerProtocolLinkage {
    public func isConnected(state: inout NetworkContext.State) -> Bool {
        reference.isConnected(state: &state)
    }

    public func invokeConnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
//        reference.connect(state: &state, from)
    }

    public func invokeDisconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError? = nil
    ) {
//        reference.disconnect(state: &state, from, error: error)
    }

    public func invokeDetach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
//        try reference.detach(state: &state, from)
    }

    public func invokeApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
//        reference.handleApplicationEvent(state: &state, from, event: event)
    }

    public func invokeGetMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
//        reference.getMetadata(state: &state, from)
        return nil
    }

    public func invokeGetMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
//        reference.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
        return nil
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDatagramLinkage: InboundDataLinkage where PairedLinkage: OutboundDatagramLinkage {
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundDatagramLinkage: OutboundDataLinkage where PairedLinkage: InboundDatagramLinkage {
    func invokeReceiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray?

    func invokeGetDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?

    func invokeSendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundStreamLinkage: InboundDataLinkage where PairedLinkage: OutboundStreamLinkage {
    func deliverInboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )
    func deliverOutboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )

    // TODO: TFPDEBUG These are the ones callers need to implement
    func handleInboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )
    func handleOutboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )
}

@available(Network 0.1.0, *)
extension InboundStreamLinkage {
    public func deliverInboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        from.deliverEventToUpperProtocol(
            state: &state,
            event: .inboundAborted(from, self.reference, error: error, { state, from, error in
                self.handleInboundAbortedEvent(state: &state, from, error: error)
            })
        )
    }
    public func deliverOutboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        from.deliverEventToUpperProtocol(
            state: &state,
            event: .outboundAborted(from, self.reference, error: error, { state, from, error in
                self.handleOutboundAbortedEvent(state: &state, from, error: error)
            })
        )
    }
}

/// A stub inbound stream linkage, for protocols that haven't yet moved over to a
/// concrete stream linkage family.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultInboundStreamLinkage: InboundStreamLinkage {
    public typealias PairedLinkage = DefaultOutboundStreamLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init() { self.reference = .init() }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG, concrete calls
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
    }

    public func handleInboundDataAvailableEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
    }

    public func handleOutboundRoomAvailableEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
    }

    public func handleInboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
    }

    public func handleOutboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundStreamLinkage: OutboundDataLinkage where PairedLinkage: InboundStreamLinkage {

    func invokeReceiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray?
    func invokeGetOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int
    func invokeSendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError)

    func invokeSendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError)

    func invokeAbortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError)
    func invokeAbortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError)
}

/// A stub outbound stream linkage, for protocols that haven't yet moved over to a
/// concrete stream linkage family.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultOutboundStreamLinkage: OutboundStreamLinkage {
    public typealias PairedLinkage = DefaultInboundStreamLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init() { self.reference = .init() }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG, concrete calls
    }

    public func invokeReceiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
//        try reference.receiveStreamData(state: &state, from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
        return nil
    }
    public func invokeGetOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
//        try reference.getOutboundStreamDataRoomAvailable(state: &state, from)
        return 0
    }
    public func invokeSendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
//        try reference.sendStreamData(state: &state, from, streamData: streamData)
    }

    public func invokeSendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
//        try reference.sendEarlyStreamData(state: &state, from, streamData: streamData)
    }

    public func invokeAbortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
//        try reference.abortInbound(state: &state, from, error: error)
    }
    public func invokeAbortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
//        try reference.abortOutbound(state: &state, from, error: error)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDatagramFlowLinkage: InboundFlowLinkage where PairedLinkage: DatagramListenerLinkage { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol DatagramListenerLinkage: ListenerLinkage where PairedLinkage: InboundDatagramFlowLinkage {
    func invokeAttachUpperDatagramProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> PairedLinkage.DataLinkage

    func invokeAttachNewDatagramFlowProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self

    func invokeAttachUpperDatagramProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> PairedLinkage.DataLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundStreamFlowLinkage: InboundFlowLinkage where PairedLinkage: StreamListenerLinkage { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol StreamListenerLinkage: ListenerLinkage where PairedLinkage: InboundStreamFlowLinkage {
    func invokeAttachUpperStreamProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> PairedLinkage.DataLinkage

    func invokeAttachNewStreamFlowProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self

    func invokeAttachUpperStreamProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> PairedLinkage.DataLinkage
}

/// A stub inbound stream flow linkage, for protocols that haven't yet moved over to a
/// concrete stream linkage family.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultInboundStreamFlowLinkage: InboundStreamFlowLinkage {
    public typealias PairedLinkage = DefaultStreamListenerLinkage
    public typealias DataLinkage = DefaultOutboundStreamLinkage

    private(set) public var reference: ProtocolInstanceReference
    public init() { self.reference = .init() }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG, concrete calls
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {

    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {

    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {

    }

    public func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {

    }
}

/// A stub stream listener linkage, for protocols that haven't yet moved over to a
/// concrete stream linkage family.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultStreamListenerLinkage: StreamListenerLinkage {
    public typealias PairedLinkage = DefaultInboundStreamFlowLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init() { self.reference = .init() }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG, concrete calls
    }

    public func invokeAttachNewStreamFlowProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self {
//        try reference.attachNewStreamFlowProtocol(
//            from,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
        return .init()
    }

    public func invokeAttachUpperStreamProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> DefaultOutboundStreamLinkage {
//        try reference.attachUpperStreamProtocolToNewFlow(
//            from,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
        return .init()
    }

    public func invokeAttachUpperStreamProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> DefaultOutboundStreamLinkage {
//        try reference.attachUpperStreamProtocolToExistingFlow(
//            from,
//            flowReference: flowReference
//        )
        return .init()
    }
}

// TODO: For linkages, if you need to customize, you wrap up another concrete linkage. If you have your type, you catch that an invoke the function directly, and if it's generic, you pass it through to the inner linkage.

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundMessageLinkage: InboundDataLinkage {
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundMessageLinkage: OutboundDataLinkage where PairedLinkage: InboundMessageLinkage {

    associatedtype OutboundMessageType: ~Copyable

    func invokeReceiveMessage(
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> OutboundMessageType?

    func invokeSendMessage(
        _ from: ProtocolInstanceReference,
        message: consuming OutboundMessageType
    ) throws(NetworkError)

}
