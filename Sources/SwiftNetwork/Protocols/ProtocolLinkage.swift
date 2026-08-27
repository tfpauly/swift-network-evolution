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
public protocol LinkageFamily {
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
public protocol StreamLinkageFamily: DataLinkageFamily where Upper == InboundStreamLinkage, Lower == OutboundStreamLinkage, Listener == StreamListenerLinkage, InboundFlow == InboundStreamFlowLinkage, InboundFlow.DataLinkage == Lower, Listener.PairedLinkage.DataLinkage == Lower { }

/// A strongly typed structure that holds a reference to another protocol and dispatches functions to it.
///
/// Each linkage is paired with a matching linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ProtocolLinkage: Hashable {
    associatedtype PairedLinkage: ProtocolLinkage
    init(reference: ProtocolInstanceReference) // TODO: TFPDEBUG Remove this
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
    func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)
}

@available(Network 0.1.0, *)
extension UpperProtocolLinkage {
    public func deliverConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        from.deliverEventToUpperProtocol(state: &state, event: .connected(from, self.reference))
    }
    public func deliverDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        from.deliverEventToUpperProtocol(state: &state, event: .disconnected(from, self.reference, error: error))
    }
    public func deliverNetworkProtocolEvent(
        state: inout NetworkContext.State,
        originalReference: ProtocolInstanceReference,
        selfReference: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        selfReference.deliverEventToUpperProtocol(
            state: &state,
            event: .networkProtocolEvent(originalReference, self.reference, event: event)
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
}

@available(Network 0.1.0, *)
extension InboundDataLinkage {
    public func deliverInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        from.deliverEventToUpperProtocol(state: &state, event: .inboundDataAvailable(from, self.reference))
    }
    public func deliverOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        from.deliverEventToUpperProtocol(state: &state, event: .outboundRoomAvailable(from, self.reference))
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
            event: .newInboundFlow(from, self.reference, flowReference: flowReference, flowMetadata: flowMetadata)
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
//        try reference.attachUpperProtocolToNewFlow(
//            from,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
        return .init(reference: from)
    }

    public func invokeAttachUpperProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> Self.PairedLinkage.DataLinkage {
//        try reference.attachUpperProtocolToExistingFlow(
//            from,
//            flowReference: flowReference
//        )
        return .init(reference: from)
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
    func invokeAttachUpperDatagramProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self

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
public struct InboundStreamLinkage: InboundDataLinkage {
    public typealias PairedLinkage = OutboundStreamLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) { self.reference = reference }
    public init() { self.reference = .init() }

    public func deliverInboundAbortedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?) {
        from.deliverEventToUpperProtocol(state: &state, event: .inboundAborted(from, self.reference, error: error))
    }
    public func deliverOutboundAbortedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?) {
        from.deliverEventToUpperProtocol(state: &state, event: .outboundAborted(from, self.reference, error: error))
    }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG, concrete calls
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundStreamTypeLinkage: OutboundDataLinkage {

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


@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct OutboundStreamLinkage: OutboundStreamTypeLinkage {
    public typealias PairedLinkage = InboundStreamLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) { self.reference = reference }
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

    public func invokeAttachUpperStreamProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self {
//        try reference.attachUpperStreamProtocol(from, remote: remote, local: local, parameters: parameters, path: path)
        return .init(reference: from)
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
public struct InboundStreamFlowLinkage: InboundFlowLinkage {
    public typealias PairedLinkage = StreamListenerLinkage
    public typealias DataLinkage = OutboundStreamLinkage

    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) { self.reference = reference }
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
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct StreamListenerLinkage: ListenerLinkage {
    public typealias PairedLinkage = InboundStreamFlowLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) { self.reference = reference }
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
        return .init(reference: from)
    }

    public func invokeAttachUpperStreamProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> OutboundStreamLinkage {
//        try reference.attachUpperStreamProtocolToNewFlow(
//            from,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
        return .init(reference: from)
    }

    public func invokeAttachUpperStreamProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> OutboundStreamLinkage {
//        try reference.attachUpperStreamProtocolToExistingFlow(
//            from,
//            flowReference: flowReference
//        )
        return .init(reference: from)
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

//@_spi(ProtocolProvider)
//@available(Network 0.1.0, *)
//public struct InboundHTTPMessageLinkage: InboundMessageLinkage {
//    public typealias PairedLinkage = OutboundHTTPMessageLinkage
//    private(set) public var reference: ProtocolInstanceReference
//    public init(reference: ProtocolInstanceReference) { self.reference = reference }
//    public init() { self.reference = .init() }
//
//    public func invokeAttachLowerProtocol(
//        _ lowerProtocol: PairedLinkage,
//        remote: Endpoint?,
//        local: Endpoint?,
//        parameters: Parameters?,
//        path: PathProperties?
//    ) throws(NetworkError) {
//        // TODO: TFPDEBUG, concrete calls
//    }
//}

//@_spi(ProtocolProvider)
//@available(Network 0.1.0, *)
//public struct OutboundHTTPMessageLinkage: OutboundMessageLinkage, OutboundStreamTypeLinkage {
//    public typealias OutboundMessageType = HTTPProtocol.HTTPMessage
//
//    public typealias PairedLinkage = InboundHTTPMessageLinkage
//    private(set) public var reference: ProtocolInstanceReference
//    public init(reference: ProtocolInstanceReference) { self.reference = reference }
//    public init() { self.reference = .init() }
//
//    public func invokeAttachUpperProtocol(
//        _ upperProtocol: PairedLinkage,
//        remote: Endpoint?,
//        local: Endpoint?,
//        parameters: Parameters?,
//        path: PathProperties?
//    ) throws(NetworkError) {
//        // TODO: TFPDEBUG, concrete calls
//    }
//
//    public func invokeAttachUpperStreamProtocol(
//        _ from: ProtocolInstanceReference,
//        remote: Endpoint?,
//        local: Endpoint?,
//        parameters: Parameters?,
//        path: PathProperties?
//    ) throws(NetworkError) -> Self {
//        return .init()
//        // TODO: TFPDEBUG Hook this up
////        try reference.attachUpperStreamProtocol(from, remote: remote, local: local, parameters: parameters, path: path)
//    }
//
//    public func invokeReceiveMessage(_ from: ProtocolInstanceReference) throws(NetworkError) -> HTTPProtocol.HTTPMessage? {
//        return nil
//    }
//
//    public func invokeSendMessage(_ from: ProtocolInstanceReference, message: consuming HTTPProtocol.HTTPMessage) throws(NetworkError) {
//
//    }
//
//    public func invokeReceiveStreamData(
//        _ from: ProtocolInstanceReference,
//        minimumBytes: Int,
//        maximumBytes: Int
//    ) throws(NetworkError) -> FrameArray? {
//        try reference.receiveStreamData(from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
//    }
//    public func invokeGetOutboundStreamDataRoomAvailable(_ from: ProtocolInstanceReference) throws(NetworkError) -> Int
//    {
//        try reference.getOutboundStreamDataRoomAvailable(from)
//    }
//    public func invokeSendStreamData(
//        _ from: ProtocolInstanceReference,
//        streamData: consuming FrameArray
//    ) throws(NetworkError) {
//        try reference.sendStreamData(from, streamData: streamData)
//    }
//
//    public func invokeSendEarlyStreamData(
//        _ from: ProtocolInstanceReference,
//        streamData: consuming FrameArray
//    ) throws(NetworkError) {
//        try reference.sendEarlyStreamData(from, streamData: streamData)
//    }
//
//    public func invokeAbortInbound(_ from: ProtocolInstanceReference, error: NetworkError?) throws(NetworkError) {
//        try reference.abortInbound(from, error: error)
//    }
//    public func invokeAbortOutbound(_ from: ProtocolInstanceReference, error: NetworkError?) throws(NetworkError) {
//        try reference.abortOutbound(from, error: error)
//    }
//}

@available(Network 0.1.0, *)
protocol DatagramProtocolLinkageFamily: ~Copyable {
    associatedtype UpperDatagram: InboundDatagramLinkage
    associatedtype LowerDatagram: OutboundDatagramLinkage
}
//
//protocol StreamProtocolLinkageFamily: ~Copyable {
//    associatedtype UpperStream: InboundStreamLinkage
//    associatedtype LowerStream: OutboundStreamLinkage
//}
