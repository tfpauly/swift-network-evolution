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

/// A strongly typed structure that holds a reference to another protocol and dispatches functions to it.
///
/// Each linkage is paired with a matching linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ProtocolLinkage: Hashable {
    associatedtype PairedLinkage: ProtocolLinkage
    init(reference: ProtocolInstanceReference)
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
    func deliverConnectedEvent(_ from: ProtocolInstanceReference)
    func deliverDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?)
    func deliverNetworkProtocolEvent(
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
    public func deliverConnectedEvent(_ from: ProtocolInstanceReference) {
        from.deliverEventToUpperProtocol(event: .connected(from, self.reference))
    }
    public func deliverDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        from.deliverEventToUpperProtocol(event: .disconnected(from, self.reference, error: error))
    }
    public func deliverNetworkProtocolEvent(
        originalReference: ProtocolInstanceReference,
        selfReference: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        selfReference.deliverEventToUpperProtocol(
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
    func deliverInboundDataAvailableEvent(_ from: ProtocolInstanceReference)
    func deliverOutboundRoomAvailableEvent(_ from: ProtocolInstanceReference)
}

@available(Network 0.1.0, *)
extension InboundDataLinkage {
    public func deliverInboundDataAvailableEvent(_ from: ProtocolInstanceReference) {
        from.deliverEventToUpperProtocol(event: .inboundDataAvailable(from, self.reference))
    }
    public func deliverOutboundRoomAvailableEvent(_ from: ProtocolInstanceReference) {
        from.deliverEventToUpperProtocol(event: .outboundRoomAvailable(from, self.reference))
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundFlowLinkage: UpperProtocolLinkage where PairedLinkage: ListenerLinkage {
    associatedtype DataLinkage: OutboundDataLinkage
    func deliverNewInboundFlowEvent(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    )
}

@available(Network 0.1.0, *)
extension InboundFlowLinkage {
    public func deliverNewInboundFlowEvent(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        from.deliverEventToUpperProtocol(
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
        try reference.attachUpperProtocolToNewFlow(
            from,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeAttachUpperProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> Self.PairedLinkage.DataLinkage {
        try reference.attachUpperProtocolToExistingFlow(
            from,
            flowReference: flowReference
        )
    }
    #endif
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundDataLinkage: LowerProtocolLinkage where PairedLinkage: InboundDataLinkage {}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol LowerProtocolLinkage: ProtocolLinkage where PairedLinkage: UpperProtocolLinkage {
    var isConnected: Bool { get }
    func invokeConnect(_ from: ProtocolInstanceReference)
    func invokeDisconnect(_ from: ProtocolInstanceReference, error: NetworkError?)
    func invokeAttachUpperProtocol(
        _ upperProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)
    func invokeDetach(_ from: ProtocolInstanceReference) throws(NetworkError)
    func invokeApplicationEvent(_ from: ProtocolInstanceReference, event: ApplicationEvent)
    func invokeGetMetadata<P: NetworkProtocol>(_ from: ProtocolInstanceReference) -> ProtocolMetadata<P>?
}

@available(Network 0.1.0, *)
extension LowerProtocolLinkage {
    public var isConnected: Bool {
        reference.isConnected
    }

    public func invokeConnect(_ from: ProtocolInstanceReference) {
        reference.connect(from)
    }

    public func invokeDisconnect(_ from: ProtocolInstanceReference, error: NetworkError? = nil) {
        reference.disconnect(from, error: error)
    }

    public func invokeDetach(_ from: ProtocolInstanceReference) throws(NetworkError) {
        try reference.detach(from)
    }

    public func invokeApplicationEvent(_ from: ProtocolInstanceReference, event: ApplicationEvent) {
        reference.handleApplicationEvent(from, event: event)
    }

    public func invokeGetMetadata<P: NetworkProtocol>(_ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
        reference.getMetadata(from)
    }

    public func invokeGetMetrics(
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        reference.getMetrics(from, requestedNetworkMetric: requestedNetworkMetric)
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
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray?

    func invokeGetDatagramsToSend(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?

    func invokeSendDatagrams(
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

    public func deliverInboundAbortedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        from.deliverEventToUpperProtocol(event: .inboundAborted(from, self.reference, error: error))
    }
    public func deliverOutboundAbortedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        from.deliverEventToUpperProtocol(event: .outboundAborted(from, self.reference, error: error))
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
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray?
    func invokeGetOutboundStreamDataRoomAvailable(_ from: ProtocolInstanceReference) throws(NetworkError) -> Int
    func invokeSendStreamData(
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError)

    func invokeSendEarlyStreamData(
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError)

    func invokeAbortInbound(_ from: ProtocolInstanceReference, error: NetworkError?) throws(NetworkError)
    func invokeAbortOutbound(_ from: ProtocolInstanceReference, error: NetworkError?) throws(NetworkError)
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
        try reference.attachUpperStreamProtocol(from, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func invokeReceiveStreamData(
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        try reference.receiveStreamData(from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }
    public func invokeGetOutboundStreamDataRoomAvailable(_ from: ProtocolInstanceReference) throws(NetworkError) -> Int
    {
        try reference.getOutboundStreamDataRoomAvailable(from)
    }
    public func invokeSendStreamData(
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        try reference.sendStreamData(from, streamData: streamData)
    }

    public func invokeSendEarlyStreamData(
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        try reference.sendEarlyStreamData(from, streamData: streamData)
    }

    public func invokeAbortInbound(_ from: ProtocolInstanceReference, error: NetworkError?) throws(NetworkError) {
        try reference.abortInbound(from, error: error)
    }
    public func invokeAbortOutbound(_ from: ProtocolInstanceReference, error: NetworkError?) throws(NetworkError) {
        try reference.abortOutbound(from, error: error)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct InboundDatagramFlowLinkage: InboundFlowLinkage {
    public typealias PairedLinkage = DatagramListenerLinkage
    public typealias DataLinkage = DefaultOutboundDatagramLinkage
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
public struct DatagramListenerLinkage: ListenerLinkage {
    public typealias PairedLinkage = InboundDatagramFlowLinkage
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

    public func invokeAttachNewDatagramFlowProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Self {
        try reference.attachNewDatagramFlowProtocol(
            from,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeAttachUpperDatagramProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
        try reference.attachUpperDatagramProtocolToNewFlow(
            from,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeAttachUpperDatagramProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
        try reference.attachUpperDatagramProtocolToExistingFlow(
            from,
            flowReference: flowReference
        )
    }
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
        try reference.attachNewStreamFlowProtocol(
            from,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeAttachUpperStreamProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> OutboundStreamLinkage {
        try reference.attachUpperStreamProtocolToNewFlow(
            from,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeAttachUpperStreamProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> OutboundStreamLinkage {
        try reference.attachUpperStreamProtocolToExistingFlow(
            from,
            flowReference: flowReference
        )
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
