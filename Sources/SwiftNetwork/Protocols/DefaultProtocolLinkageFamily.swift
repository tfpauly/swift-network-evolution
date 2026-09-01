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


// TODO: TFPDEBUG Should a linkage throw/abort if it is created with a reference for a protocol
// it doesn't understand?
// TODO: TFPDEBUG does the reference even need to know about the protocol type at all? Can that just
// be the linkages? If the reference is to a class type, it can just hold a ref count.
// TODO: TFPDEBUG Reference maybe can just be the tuple of context and event manager index + parent.

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultDatagramLinkageFamily: DatagramLinkageFamily {
    public typealias Upper = DefaultInboundDatagramLinkage
    public typealias Lower = DefaultOutboundDatagramLinkage
    public typealias Listener = DefaultDatagramListenerLinkage
    public typealias InboundFlow = DefaultInboundDatagramFlowLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultStreamLinkageFamily: StreamLinkageFamily {
    public typealias Upper = InboundStreamLinkage
    public typealias Lower = OutboundStreamLinkage
    public typealias Listener = StreamListenerLinkage
    public typealias InboundFlow = InboundStreamFlowLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultInboundDatagramLinkage: InboundDatagramLinkage {
    public typealias PairedLinkage = DefaultOutboundDatagramLinkage
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
        /*
        try reference.fromExternal(state: &reference.context.state) { state throws(NetworkError) in
            switch reference.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .udp(let index):
                try state.udpInstances[index].attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .ip(let index):
                try state.ipInstances[index].attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tcp(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .datagramEndpointFlow(let instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicPath(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .datagramUpperHarness(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            default: fatalError("Protocol cannot accept attachLowerProtocol call")
            }
        }
         */
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
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultOutboundDatagramLinkage: OutboundDatagramLinkage {
    public typealias PairedLinkage = DefaultInboundDatagramLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) {
        self.reference = reference
        /*
        if let protocolIdentifier = reference.protocolIdentifier {
            switch protocolIdentifier {
            case UDPProtocol.identifier:
                knownType = .udp
            case IPProtocol.identifier:
                knownType = .ip
                // TODO: TFPDEBUG All protocols need identifiers?
//            #if !NETWORK_NO_SWIFT_QUIC
//            case QUICDatagramFlow.identifier:
//                knownType = .quicDatagram
//            #endif
//            #if !NETWORK_NO_TESTING_HARNESS
//            case DatagramLowerHarness.identifier:
//                knownType = .datagramLowerHarness
//            #endif
            default:
                knownType = .none
            }
        } else {
            knownType = .none
        }
         */
        knownType = .none

    }
    public init() {
        reference = .init()
        knownType = .none
    }

    // TODO: TFPDEBUG Add enum of known types here

    enum KnownType {
        case none
        case udp
        case ip
        #if !NETWORK_NO_SWIFT_QUIC
        case quicDatagram
        #endif
        #if !NETWORK_NO_TESTING_HARNESS
        case datagramLowerHarness
        #endif
    }
    var knownType: KnownType

    public func invokeAttachUpperProtocol(
        _ upperProtocol: PairedLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG avoid switching on reference.reference
        /*
        try reference.handleCallFromUpperProtocol(state: &reference.context.state) { state throws(NetworkError) in
            switch reference.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .udp(let index):
                try state.udpInstances[index].attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .ip(let index):
                try state.ipInstances[index].attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicDatagram(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #endif
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
        }
         */
    }

    public func invokeReceiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
//        try reference.receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
        return nil
    }
    public func invokeGetDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
//        try reference.getDatagramsToSend(
//            state: &state,
//            from,
//            maximumDatagramCount: maximumDatagramCount,
//            minimumDatagramSize: minimumDatagramSize
//        )
        return nil
    }
    public func invokeSendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
//        try reference.sendDatagrams(state: &state, from, datagrams: datagrams)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultInboundDatagramFlowLinkage: InboundDatagramFlowLinkage {
    public typealias PairedLinkage = DefaultDatagramListenerLinkage
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

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultDatagramListenerLinkage: DatagramListenerLinkage {
    public typealias PairedLinkage = DefaultInboundDatagramFlowLinkage
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
//        try reference.attachNewDatagramFlowProtocol(
//            from,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
        return .init(reference: from)
    }

    public func invokeAttachUpperDatagramProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
//        try reference.attachUpperDatagramProtocolToNewFlow(
//            from,
//            remote: remote,
//            local: local,
//            parameters: parameters,
//            path: path
//        )
        return .init(reference: from)
    }

    public func invokeAttachUpperDatagramProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
//        try reference.attachUpperDatagramProtocolToExistingFlow(
//            from,
//            flowReference: flowReference
//        )
        return .init(reference: from)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseDatagramLinkageFamily: DatagramLinkageFamily {
    public typealias Upper = BaseNetworkProtocolStorage.BaseInboundDatagramLinkage
    public typealias Lower = BaseNetworkProtocolStorage.BaseOutboundDatagramLinkage
    public typealias Listener = BaseNetworkProtocolStorage.BaseDatagramListenerLinkage
    public typealias InboundFlow = BaseNetworkProtocolStorage.BaseInboundDatagramFlowLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
open class BaseNetworkProtocolStorage {

    let context: NetworkContext

    public init(context: NetworkContext) {
        self.context = context
    }

    public struct BaseInboundDatagramLinkage: InboundDatagramLinkage {
        enum ProtocolType: Hashable {
            case unknown
            case udp(NetworkStateIndex)
            case ip(NetworkStateIndex)
            case datagramUpperHarness(NetworkStateIndex)
        }

        public func invokeAttachLowerProtocol(_ lowerProtocol: BaseNetworkProtocolStorage.BaseOutboundDatagramLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            let overrideUpperLinkage: Self?
            switch protocolType {
            case .udp(let index): overrideUpperLinkage = try storage!.udpInstances[index].attachLowerProtocol(lowerProtocol)
            case .ip(let index): overrideUpperLinkage = try storage!.ipInstances[index].attachLowerProtocol(lowerProtocol)
            case .datagramUpperHarness(let index): overrideUpperLinkage = try storage!.datagramUpperHarnesses[index].attachLowerProtocol(lowerProtocol)
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
            let upperLinkage = overrideUpperLinkage ?? self
            try lowerProtocol.invokeAttachUpperProtocol(upperLinkage, remote: remote, local: local, parameters: parameters, path: path)
        }

        public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .udp(let index): storage!.udpInstances[index].handleConnectedEvent(state: &state, from)
            case .ip(let index): storage!.ipInstances[index].handleConnectedEvent(state: &state, from)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleConnectedEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleConnectedEvent call")
            }
        }

        public func handleDisconnectedEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .udp(let index):
                storage!.udpInstances[index].handleDisconnectedEvent(state: &state, from, error: error)
            case .ip(let index):
                storage!.ipInstances[index].handleDisconnectedEvent(state: &state, from, error: error)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleDisconnectedEvent(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept handleDisconnectedEvent call")
            }
        }

        public func handleNetworkProtocolEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            event: NetworkProtocolEvent
        ) {
            switch protocolType {
            case .udp(let index):
                storage!.udpInstances[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            case .ip(let index):
                storage!.ipInstances[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleNetworkProtocolEvent call")
            }
        }

        public func handleInboundDataAvailableEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) {
            switch protocolType {
            case .udp(let index):
                storage!.udpInstances[index].handleInboundDataAvailableEvent(state: &state, from)
            case .ip(let index):
                storage!.ipInstances[index].handleInboundDataAvailableEvent(state: &state, from)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleInboundDataAvailableEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleInboundDataAvailableEvent call")
            }
        }

        public func handleOutboundRoomAvailableEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) {
            switch protocolType {
            case .udp(let index):
                storage!.udpInstances[index].handleOutboundRoomAvailableEvent(state: &state, from)
            case .ip(let index):
                storage!.ipInstances[index].handleOutboundRoomAvailableEvent(state: &state, from)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleOutboundRoomAvailableEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleOutboundRoomAvailableEvent call")
            }
        }

        public typealias PairedLinkage = BaseOutboundDatagramLinkage

        public init() {
            self.reference = .init()
            self.storage = nil
            self.protocolType = .unknown
        }

        init(reference: ProtocolInstanceReference, storage: BaseNetworkProtocolStorage, protocolType: ProtocolType) {
            self.reference = reference
            self.storage = storage
            self.protocolType = protocolType
        }
        
        public let reference: ProtocolInstanceReference
        public let storage: BaseNetworkProtocolStorage?
        let protocolType: ProtocolType

        public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
            lhs.reference == rhs.reference
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(reference)
        }
    }

    public struct BaseOutboundDatagramLinkage: OutboundDatagramLinkage {
        enum ProtocolType: Hashable {
            case unknown
            case udp(NetworkStateIndex)
            case ip(NetworkStateIndex)
            case datagramLowerHarness(NetworkStateIndex)
        }

        // TODO: TFPDEBUG: Is it the responsibility of every "subclass" of linkage to call into handleCallFromUpperProtocol? Can we make that more automatic?
        public func invokeReceiveDatagrams(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, maximumDatagramCount: Int) throws(NetworkError) -> FrameArray? {
            return try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
                switch protocolType {
                case .udp(let index):
                    return try storage!.udpInstances[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
                case .ip(let index):
                    return try storage!.ipInstances[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
                case .datagramLowerHarness(let index):
                    return try storage!.datagramLowerHarnesses[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
                default:
                    return nil
                }
            }
        }
        
        public func invokeGetDatagramsToSend(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, maximumDatagramCount: Int, minimumDatagramSize: Int) throws(NetworkError) -> FrameArray? {
            return try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
                switch protocolType {
                case .udp(let index):
                    return try storage!.udpInstances[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
                case .ip(let index):
                    return try storage!.ipInstances[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
                case .datagramLowerHarness(let index):
                    return try storage!.datagramLowerHarnesses[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
                default:
                    return nil
                }
            }
        }
        
        public func invokeSendDatagrams(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, datagrams: consuming FrameArray) throws(NetworkError) {
            try reference.handleCallFromUpperProtocol(state: &state, datagrams) { state, datagrams throws(NetworkError) in
                switch protocolType {
                case .udp(let index):
                    try storage!.udpInstances[index].sendDatagrams(state: &state, from, datagrams: datagrams)
                case .ip(let index):
                    try storage!.ipInstances[index].sendDatagrams(state: &state, from, datagrams: datagrams)
                case .datagramLowerHarness(let index):
                    try storage!.datagramLowerHarnesses[index].sendDatagrams(state: &state, from, datagrams: datagrams)
                default:
                    return
                }
            }
        }

        public func isConnected(state: inout NetworkContext.State) -> Bool {
            reference.isConnected(state: &state)
        }

        public func invokeConnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            guard !reference.isNone else { return }
            reference.handleCallFromUpperProtocol(state: &state) { state in
                switch protocolType {
                case .udp(let index): storage!.udpInstances[index].connect(state: &state, from)
                case .ip(let index): storage!.ipInstances[index].connect(state: &state, from)
                case .datagramLowerHarness(let index): storage!.datagramLowerHarnesses[index].connect(state: &state, from)
                default: fatalError("Protocol cannot accept connect call")
                }
            }
        }

        public func invokeDisconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError? = nil) {
            guard !reference.isNone else { return }
            reference.handleCallFromUpperProtocol(state: &state) { state in
                switch protocolType {
                case .udp(let index): storage!.udpInstances[index].disconnect(state: &state, from, error: error)
                case .ip(let index): storage!.ipInstances[index].disconnect(state: &state, from, error: error)
                case .datagramLowerHarness(let index): storage!.datagramLowerHarnesses[index].disconnect(state: &state, from, error: error)
                default: fatalError("Protocol cannot accept disconnect call")
                }
            }
        }

        public func invokeDetach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError) {
            guard !reference.isNone else { return }
            try reference.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
                switch protocolType {
                case .udp(let index):
                    try storage!.udpInstances[index].detach(state: &state, from)
                case .ip(let index):
                    try storage!.ipInstances[index].detach(state: &state, from)
                case .datagramLowerHarness(let index):
                    try storage!.datagramLowerHarnesses[index].detach(state: &state, from)
                default: fatalError("Protocol cannot accept detach call")
                }
            }
            switch protocolType {
            case .udp(let index):
                storage!.udpInstances[index].eventManager.unregister(state: &state)
                storage!.udpInstances.remove(index: index)
            case .ip(let index):
                storage!.ipInstances[index].eventManager.unregister(state: &state)
                storage!.ipInstances.remove(index: index)
            case .datagramLowerHarness(let index):
                storage!.datagramLowerHarnesses[index].eventManager.unregister(state: &state)
                storage!.datagramLowerHarnesses.remove(index: index)
            default: break
            }
        }

        public func invokeApplicationEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, event: ApplicationEvent) {
            reference.handleCallFromUpperProtocol(state: &state) { state in
                switch protocolType {
                case .udp(let index): storage!.udpInstances[index].handleApplicationEvent(state: &state, from, event: event)
                case .ip(let index): storage!.ipInstances[index].handleApplicationEvent(state: &state, from, event: event)
                case .datagramLowerHarness(let index): storage!.datagramLowerHarnesses[index].handleApplicationEvent(state: &state, from, event: event)
                default: fatalError("Protocol cannot accept handleApplicationEvent call")
                }
            }
        }

        public func invokeGetMetadata<P: NetworkProtocol>(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
            return reference.handleCallFromUpperProtocol(state: &state) { state -> ProtocolMetadata<P>? in
                switch protocolType {
                case .udp(let index): return storage!.udpInstances[index].getMetadata(state: &state, from)
                case .ip(let index): return storage!.ipInstances[index].getMetadata(state: &state, from)
                case .datagramLowerHarness(let index): return storage!.datagramLowerHarnesses[index].getMetadata(state: &state, from)
                default: fatalError("Protocol cannot accept getMetadata call")
                }
            }
        }

        public func invokeGetMetrics(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            requestedNetworkMetric: RequestedNetworkMetrics
        ) -> NetworkMetrics? {
            return reference.handleCallFromUpperProtocol(state: &state) { state -> NetworkMetrics? in
                switch protocolType {
                case .udp(let index): return storage!.udpInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
                case .ip(let index): return storage!.ipInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
                case .datagramLowerHarness(let index): return storage!.datagramLowerHarnesses[index].getMetricsgetMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
                default: fatalError("Protocol cannot accept getMetrics call")
                }
            }
        }

        public func invokeAttachUpperProtocol(_ upperProtocol: BaseNetworkProtocolStorage.BaseInboundDatagramLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            switch protocolType {
            case .udp(let index): try storage!.udpInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .ip(let index): try storage!.ipInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .datagramLowerHarness(let index): try storage!.datagramLowerHarnesses[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
        }
        
        public typealias PairedLinkage = BaseInboundDatagramLinkage

        public init() {
            self.reference = .init()
            self.storage = nil
            self.protocolType = .unknown
        }

        init(reference: ProtocolInstanceReference, storage: BaseNetworkProtocolStorage, protocolType: ProtocolType) {
            self.reference = reference
            self.storage = storage
            self.protocolType = protocolType
        }

        public let reference: ProtocolInstanceReference
        public let storage: BaseNetworkProtocolStorage?
        let protocolType: ProtocolType

        public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
            lhs.reference == rhs.reference
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(reference)
        }
    }

    public struct BaseDatagramListenerLinkage: DatagramListenerLinkage {
        public typealias PairedLinkage = BaseInboundDatagramFlowLinkage

        public let reference: ProtocolInstanceReference

        public init() {
            self.reference = .init()
        }

        public func invokeAttachUpperProtocol(_ upperProtocol: BaseNetworkProtocolStorage.BaseInboundDatagramFlowLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {

        }

        public func invokeAttachUpperDatagramProtocolToNewFlow(
            _ from: ProtocolInstanceReference,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) -> PairedLinkage.DataLinkage {
            throw NetworkError.posix(1)
        }

        public func invokeAttachNewDatagramFlowProtocol(
            _ from: ProtocolInstanceReference,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) -> Self {
            throw NetworkError.posix(1)
        }

        public func invokeAttachUpperDatagramProtocolToExistingFlow(
            _ from: ProtocolInstanceReference,
            flowReference: ProtocolInstanceReference
        ) throws(NetworkError) -> PairedLinkage.DataLinkage {
            throw NetworkError.posix(1)
        }
    }

    public struct BaseInboundDatagramFlowLinkage: InboundDatagramFlowLinkage {
        public typealias DataLinkage = BaseOutboundDatagramLinkage
        public typealias PairedLinkage = BaseDatagramListenerLinkage

        public let reference: ProtocolInstanceReference

        public init() {
            self.reference = .init()
        }

        public func invokeAttachLowerProtocol(_ lowerProtocol: BaseNetworkProtocolStorage.BaseDatagramListenerLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {

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


    // TODO: TFPDEBUG Move this to an inner non-copyable struct to avoid taking references
    internal var udpInstances = NetworkGappyArray<UDPProtocol.UDPInnerInstance<BaseInboundDatagramLinkage, BaseOutboundDatagramLinkage>>()

    public func createUDPInstance() -> (BaseInboundDatagramLinkage, BaseOutboundDatagramLinkage) {
        let instance = UDPProtocol.UDPInnerInstance<BaseInboundDatagramLinkage, BaseOutboundDatagramLinkage>(context: context)

        let instanceIndex = udpInstances.insert(instance)

        let reference = udpInstances[instanceIndex].reference
        let inbound = BaseInboundDatagramLinkage(reference: reference, storage: self, protocolType: .udp(instanceIndex))
        let outbound = BaseOutboundDatagramLinkage(reference: reference, storage: self, protocolType: .udp(instanceIndex))

        return (inbound, outbound)
    }

    internal var ipInstances = NetworkGappyArray<IPProtocol.IPInstance<BaseDatagramLinkageFamily>>()

    public func createIPInstance() -> (BaseInboundDatagramLinkage, BaseOutboundDatagramLinkage) {
        let instance = IPProtocol.IPInstance<BaseDatagramLinkageFamily>(context: context)

        let instanceIndex = ipInstances.insert(instance)

        let reference = ipInstances[instanceIndex].reference
        let inbound = BaseInboundDatagramLinkage(reference: reference, storage: self, protocolType: .ip(instanceIndex))
        let outbound = BaseOutboundDatagramLinkage(reference: reference, storage: self, protocolType: .ip(instanceIndex))

        return (inbound, outbound)
    }

    internal var datagramLowerHarnesses = NetworkGappyArray<DatagramLowerHarness<BaseDatagramLinkageFamily>>()

    public func createDatagramLowerHarness(identifier: String = "",
                                           context: NetworkContext) -> (DatagramLowerHarness<BaseDatagramLinkageFamily>, BaseOutboundDatagramLinkage) {
        let instance = DatagramLowerHarness<BaseDatagramLinkageFamily>(identifier: identifier,
                                                                       context: context)
        let instanceIndex = datagramLowerHarnesses.insert(instance)

        let reference = instance.reference
        let outbound = BaseOutboundDatagramLinkage(reference: reference, storage: self, protocolType: .datagramLowerHarness(instanceIndex))

        return (instance, outbound)
    }

    internal var datagramUpperHarnesses = NetworkGappyArray<DatagramUpperHarness<BaseDatagramLinkageFamily>>()

    public func createDatagramUpperHarness(identifier: String = "",
                                           local: Endpoint,
                                           remote: Endpoint,
                                           parameters: Parameters,
                                           path: PathProperties,
                                           context: NetworkContext) -> (DatagramUpperHarness<BaseDatagramLinkageFamily>, BaseInboundDatagramLinkage) {
        let instance = DatagramUpperHarness<BaseDatagramLinkageFamily>(identifier: identifier,
                                                                       local: local,
                                                                       remote: remote,
                                                                       parameters: parameters,
                                                                       path: path,
                                                                       context: context)
        let instanceIndex = datagramUpperHarnesses.insert(instance)

        let reference = instance.reference
        let inbound = BaseInboundDatagramLinkage(reference: reference, storage: self, protocolType: .datagramUpperHarness(instanceIndex))

        return (instance, inbound)
    }
}
