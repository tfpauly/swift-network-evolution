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
    /// `invokeAttachLowerProtocol` is the general entry point to connecting protocols. It will
    /// call `invokeAttachUpperProtocol` on the lower protocol.
    func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

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
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDataLinkage: UpperProtocolLinkage where PairedLinkage: OutboundDataLinkage {
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
    func invokeAttachUpperProtocolToNewFlow(
        _ upperProtocol: PairedLinkage.DataLinkage.PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    func invokeAttachUpperProtocolToExistingFlow(
        _ upperProtocol: PairedLinkage.DataLinkage.PairedLinkage,
        existingFlow: PairedLinkage.DataLinkage
    ) throws(NetworkError)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundDataLinkage: LowerProtocolLinkage where PairedLinkage: InboundDataLinkage {}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol LowerProtocolLinkage: ProtocolLinkage where PairedLinkage: UpperProtocolLinkage {
    func isConnected(state: inout NetworkContext.State) -> Bool
    func invokeAttachUpperProtocol(
        _ upperProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    func disconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?)
    func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError)
    /// Releases any storage the linkage holds for the protocol instance. This runs after
    /// `detach` has returned, once the call into the protocol stack has fully unwound, so
    /// that the instance is still reachable while it is detaching.
    func teardown(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    )
    func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>?
    func getMetrics(
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
        guard !reference.isNone else { return }
        reference.handleCallFromUpperProtocol(state: &state) { state in
            self.connect(state: &state, from)
        }
    }

    public func invokeDisconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError? = nil
    ) {
        guard !reference.isNone else { return }
        reference.handleCallFromUpperProtocol(state: &state) { state in
            self.disconnect(state: &state, from, error: error)
        }
    }

    public func invokeDetach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        guard !reference.isNone else { return }
        try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            try self.detach(state: &state, from)
        }
        // Cleanup happens after the call into the protocol stack has unwound, since the
        // instance needs to stay alive for the duration of its own detach.
        self.teardown(state: &state, from)
    }

    public func invokeApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        guard !reference.isNone else { return }
        reference.handleCallFromUpperProtocol(state: &state) { state in
            self.handleApplicationEvent(state: &state, from, event: event)
        }
    }

    public func invokeGetMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        guard !reference.isNone else { return nil }
        return reference.handleCallFromUpperProtocol(state: &state) { state -> ProtocolMetadata<P>? in
            self.getMetadata(state: &state, from)
        }
    }

    public func invokeGetMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        guard !reference.isNone else { return nil }
        return reference.handleCallFromUpperProtocol(state: &state) { state -> NetworkMetrics? in
            self.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDatagramLinkage: InboundDataLinkage where PairedLinkage: OutboundDatagramLinkage {
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundDatagramLinkage: OutboundDataLinkage where PairedLinkage: InboundDatagramLinkage {
    func receiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray?

    func getDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?

    func sendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public extension OutboundDatagramLinkage {
    func invokeReceiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !reference.isNone else { return nil }
        return try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            return try self.receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
        }
    }

    func invokeGetDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !reference.isNone else { return nil }
        return try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            return try self.getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
        }
    }

    func invokeSendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        guard !reference.isNone else {
            datagrams.finalizeAllFramesAsFailed()
            return
        }
        try reference.handleCallFromUpperProtocol(state: &state, datagrams) { state, datagrams throws(NetworkError) in
            return try self.sendDatagrams(state: &state, from, datagrams: datagrams)
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundStreamLinkage: InboundDataLinkage where PairedLinkage: OutboundStreamLinkage {
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

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundStreamLinkage: OutboundDataLinkage where PairedLinkage: InboundStreamLinkage {
    func receiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray?
    func getOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int
    func sendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError)

    func sendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError)

    func abortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError)
    func abortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public extension OutboundStreamLinkage {
    func invokeReceiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !reference.isNone else { return nil }
        return try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            return try self.receiveStreamData(
                state: &state,
                from,
                minimumBytes: minimumBytes,
                maximumBytes: maximumBytes
            )
        }
    }

    func invokeGetOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        guard !reference.isNone else { return 0 }
        return try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            return try self.getOutboundStreamDataRoomAvailable(state: &state, from)
        }
    }

    func invokeSendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        guard !reference.isNone else {
            streamData.finalizeAllFramesAsFailed()
            return
        }
        try reference.handleCallFromUpperProtocol(state: &state, streamData) { state, streamData throws(NetworkError) in
            return try self.sendStreamData(state: &state, from, streamData: streamData)
        }
    }

    func invokeSendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        guard !reference.isNone else {
            streamData.finalizeAllFramesAsFailed()
            return
        }
        try reference.handleCallFromUpperProtocol(state: &state, streamData) { state, streamData throws(NetworkError) in
            return try self.sendEarlyStreamData(state: &state, from, streamData: streamData)
        }
    }

    func invokeAbortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
        guard !reference.isNone else { return }
        try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            try self.abortInbound(state: &state, from, error: error)
        }
    }

    func invokeAbortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
        guard !reference.isNone else { return }
        try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            try self.abortOutbound(state: &state, from, error: error)
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDatagramFlowLinkage: InboundFlowLinkage where PairedLinkage: DatagramListenerLinkage { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol DatagramListenerLinkage: ListenerLinkage where PairedLinkage: InboundDatagramFlowLinkage { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundStreamFlowLinkage: InboundFlowLinkage where PairedLinkage: StreamListenerLinkage { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol StreamListenerLinkage: ListenerLinkage where PairedLinkage: InboundStreamFlowLinkage { }
