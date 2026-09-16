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
public struct BaseStreamLinkageFamily: StreamLinkageFamily {
    public typealias Upper = BaseNetworkProtocolStorage.BaseInboundStreamLinkage
    public typealias Lower = BaseNetworkProtocolStorage.BaseOutboundStreamLinkage
    public typealias Listener = BaseNetworkProtocolStorage.BaseStreamListenerLinkage
    public typealias InboundFlow = BaseNetworkProtocolStorage.BaseInboundStreamFlowLinkage
}

@available(Network 0.1.0, *)
internal struct ProtocolInstanceBox<Instance: AnyObject>: Hashable {
    let instance: Instance

    init(_ instance: Instance) {
        self.instance = instance
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.instance === rhs.instance
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(instance))
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
open class BaseNetworkProtocolStorage {

    let context: NetworkContext

    public init(context: NetworkContext) {
        self.context = context
    }

    public struct BaseInboundDatagramLinkage: InboundDatagramLinkage, @unchecked Sendable {
        enum ProtocolType: Hashable {
            case unknown
            case udp(NetworkStateIndex)
            case ip(NetworkStateIndex)
            case tcp(NetworkStateIndex)
            case datagramUpperHarness(NetworkStateIndex)
            case demux(NetworkStateIndex)
            case datagramEndpointFlow(ProtocolInstanceBox<DatagramEndpointFlowProtocol<BaseDatagramLinkageFamily>>)
            case quicPath(ProtocolInstanceBox<QUICPath<BaseQUICLinkageFamilies>>)
        }

        public func invokeAttachLowerProtocol(_ lowerProtocol: BaseNetworkProtocolStorage.BaseOutboundDatagramLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            let overrideUpperLinkage: Self?
            switch protocolType {
            case .udp(let index): overrideUpperLinkage = try storage!.udpInstances[index].attachLowerProtocol(lowerProtocol)
            case .demux(let index): overrideUpperLinkage = try storage!.demuxInstances[index].attachLowerProtocol(lowerProtocol)
            case .ip(let index): overrideUpperLinkage = try storage!.ipInstances[index].attachLowerProtocol(lowerProtocol)
            case .tcp(let index): overrideUpperLinkage = try storage!.tcpInstances[index].attachLowerProtocol(lowerProtocol)
            case .datagramUpperHarness(let index): overrideUpperLinkage = try storage!.datagramUpperHarnesses[index].attachLowerProtocol(lowerProtocol)
            case .datagramEndpointFlow(let box):
                var flow = box.instance
                overrideUpperLinkage = try flow.attachLowerProtocol(lowerProtocol)
            case .quicPath(let box):
                var path = box.instance
                overrideUpperLinkage = try path.attachLowerProtocol(lowerProtocol)
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
            let upperLinkage = overrideUpperLinkage ?? self
            try lowerProtocol.invokeAttachUpperProtocol(upperLinkage, remote: remote, local: local, parameters: parameters, path: path)
        }

        public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .udp(let index): storage!.udpInstances[index].handleConnectedEvent(state: &state, from)
            case .demux(let index): storage!.demuxInstances[index].handleConnectedEvent(state: &state, from)
            case .ip(let index): storage!.ipInstances[index].handleConnectedEvent(state: &state, from)
            case .tcp(let index): storage!.tcpInstances[index].handleConnectedEvent(state: &state, from)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleConnectedEvent(state: &state, from)
            case .datagramEndpointFlow(let box):
                box.instance.handleConnectedEvent(state: &state, from)
            case .quicPath(let box):
                box.instance.handleConnectedEvent(state: &state, from)
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
            case .demux(let index):
                storage!.demuxInstances[index].handleDisconnectedEvent(state: &state, from, error: error)
            case .ip(let index):
                storage!.ipInstances[index].handleDisconnectedEvent(state: &state, from, error: error)
            case .tcp(let index):
                storage!.tcpInstances[index].handleDisconnectedEvent(state: &state, from, error: error)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleDisconnectedEvent(state: &state, from, error: error)
            case .datagramEndpointFlow(let box):
                box.instance.handleDisconnectedEvent(state: &state, from, error: error)
            case .quicPath(let box):
                box.instance.handleDisconnectedEvent(state: &state, from, error: error)
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
            case .demux(let index):
                storage!.demuxInstances[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            case .ip(let index):
                storage!.ipInstances[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            case .tcp(let index):
                storage!.tcpInstances[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            case .datagramEndpointFlow(let box):
                box.instance.handleNetworkProtocolEvent(state: &state, from, event: event)
            case .quicPath(let box):
                var instance = box.instance
                instance.handleNetworkProtocolEvent(state: &state, from, event: event)
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
            case .demux(let index):
                storage!.demuxInstances[index].handleInboundDataAvailableEvent(state: &state, from)
            case .ip(let index):
                storage!.ipInstances[index].handleInboundDataAvailableEvent(state: &state, from)
            case .tcp(let index):
                storage!.tcpInstances[index].handleInboundDataAvailableEvent(state: &state, from)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleInboundDataAvailableEvent(state: &state, from)
            case .datagramEndpointFlow(let box):
                box.instance.handleInboundDataAvailableEvent(state: &state, from)
            case .quicPath(let box):
                var instance = box.instance
                instance.handleInboundDataAvailableEvent(state: &state, from)
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
            case .demux(let index):
                storage!.demuxInstances[index].handleOutboundRoomAvailableEvent(state: &state, from)
            case .ip(let index):
                storage!.ipInstances[index].handleOutboundRoomAvailableEvent(state: &state, from)
            case .tcp(let index):
                storage!.tcpInstances[index].handleOutboundRoomAvailableEvent(state: &state, from)
            case .datagramUpperHarness(let index):
                storage!.datagramUpperHarnesses[index].handleOutboundRoomAvailableEvent(state: &state, from)
            case .datagramEndpointFlow(let box):
                box.instance.handleOutboundRoomAvailableEvent(state: &state, from)
            case .quicPath(let box):
                var instance = box.instance
                instance.handleOutboundRoomAvailableEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleOutboundRoomAvailableEvent call")
            }
        }

        public typealias PairedLowerLinkage = BaseOutboundDatagramLinkage

        public init() {
            self.reference = .init()
            self.storage = nil
            self.protocolType = .unknown
        }

        init(reference: ProtocolInstanceReference, storage: BaseNetworkProtocolStorage?, protocolType: ProtocolType) {
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

    public struct BaseOutboundDatagramLinkage: OutboundDatagramLinkage, @unchecked Sendable {
        enum ProtocolType: Hashable {
            case unknown
            case udp(NetworkStateIndex)
            case ip(NetworkStateIndex)
            case datagramLowerHarness(NetworkStateIndex)
            case demux(NetworkStateIndex)
            case bridgeDatagram(NetworkStateIndex)
            case quicDatagramFlow(ProtocolInstanceBox<QUICDatagramFlow<BaseQUICLinkageFamilies>>)
        }

        public func receiveDatagrams(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, maximumDatagramCount: Int) throws(NetworkError) -> FrameArray? {
            switch protocolType {
            case .udp(let index):
                return try storage!.udpInstances[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
            case .demux(let index):
                return try storage!.demuxInstances[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
            case .ip(let index):
                return try storage!.ipInstances[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
            case .datagramLowerHarness(let index):
                return try storage!.datagramLowerHarnesses[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
            case .bridgeDatagram(let index):
                return try storage!.bridgeDatagramInstances[index].receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
            case .quicDatagramFlow(let box):
                var instance = box.instance
                return try instance.receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
            default:
                return nil
            }
        }
        
        public func getDatagramsToSend(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, maximumDatagramCount: Int, minimumDatagramSize: Int) throws(NetworkError) -> FrameArray? {
            switch protocolType {
            case .udp(let index):
                return try storage!.udpInstances[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
            case .demux(let index):
                return try storage!.demuxInstances[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
            case .ip(let index):
                return try storage!.ipInstances[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
            case .datagramLowerHarness(let index):
                return try storage!.datagramLowerHarnesses[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
            case .bridgeDatagram(let index):
                return try storage!.bridgeDatagramInstances[index].getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
            case .quicDatagramFlow(let box):
                return try box.instance.getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
            default:
                return nil
            }
        }
        
        public func sendDatagrams(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, datagrams: consuming FrameArray) throws(NetworkError) {
            switch protocolType {
            case .udp(let index):
                try storage!.udpInstances[index].sendDatagrams(state: &state, from, datagrams: datagrams)
            case .demux(let index):
                try storage!.demuxInstances[index].sendDatagrams(state: &state, from, datagrams: datagrams)
            case .ip(let index):
                try storage!.ipInstances[index].sendDatagrams(state: &state, from, datagrams: datagrams)
            case .datagramLowerHarness(let index):
                try storage!.datagramLowerHarnesses[index].sendDatagrams(state: &state, from, datagrams: datagrams)
            case .bridgeDatagram(let index):
                try storage!.bridgeDatagramInstances[index].sendDatagrams(state: &state, from, datagrams: datagrams)
            case .quicDatagramFlow(let box):
                var instance = box.instance
                try instance.sendDatagrams(state: &state, from, datagrams: datagrams)
            default:
                return
            }
        }

        public func isConnected(state: inout NetworkContext.State) -> Bool {
            reference.isConnected(state: &state)
        }

        public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .udp(let index): storage!.udpInstances[index].connect(state: &state, from)
            case .demux(let index): storage!.demuxInstances[index].connect(state: &state, from)
            case .ip(let index): storage!.ipInstances[index].connect(state: &state, from)
            case .datagramLowerHarness(let index): storage!.datagramLowerHarnesses[index].connect(state: &state, from)
            case .bridgeDatagram(let index): storage!.bridgeDatagramInstances[index].connect(state: &state, from)
            case .quicDatagramFlow(let box): box.instance.connect(state: &state, from)
            default: fatalError("Protocol cannot accept connect call")
            }
        }

        public func disconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?) {
            switch protocolType {
            case .udp(let index): storage!.udpInstances[index].disconnect(state: &state, from, error: error)
            case .demux(let index): storage!.demuxInstances[index].disconnect(state: &state, from, error: error)
            case .ip(let index): storage!.ipInstances[index].disconnect(state: &state, from, error: error)
            case .datagramLowerHarness(let index): storage!.datagramLowerHarnesses[index].disconnect(state: &state, from, error: error)
            case .bridgeDatagram(let index): storage!.bridgeDatagramInstances[index].disconnect(state: &state, from, error: error)
            case .quicDatagramFlow(let box): box.instance.disconnect(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept disconnect call")
            }
        }

        public func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError) {
            switch protocolType {
            case .udp(let index):
                try storage!.udpInstances[index].detach(state: &state, from)
            case .demux(let index):
                try storage!.demuxInstances[index].detach(state: &state, from)
            case .ip(let index):
                try storage!.ipInstances[index].detach(state: &state, from)
            case .datagramLowerHarness(let index):
                try storage!.datagramLowerHarnesses[index].detach(state: &state, from)
            case .bridgeDatagram(let index):
                try storage!.bridgeDatagramInstances[index].detach(state: &state, from)
            case .quicDatagramFlow(let box):
                var instance = box.instance
                try instance.detach(state: &state, from)
            default: fatalError("Protocol cannot accept detach call")
            }
        }

        public func teardown(state: inout NetworkContext.State) {
            switch protocolType {
            case .udp(let index):
                storage!.udpInstances[index].eventManager.unregister(state: &state)
                storage!.udpInstances.remove(index: index)
            case .demux(let index):
                // A demux instance is shared by its default upper and one upper per pattern set,
                // which detach separately. Only release the storage once the last one has gone.
                guard storage!.demuxInstances[index].isFullyDetached else { return }
                storage!.demuxInstances[index].eventManager.unregister(state: &state)
                storage!.demuxInstances.remove(index: index)
            case .ip(let index):
                storage!.ipInstances[index].eventManager.unregister(state: &state)
                storage!.ipInstances.remove(index: index)
            case .datagramLowerHarness(let index):
                storage!.datagramLowerHarnesses[index].eventManager.unregister(state: &state)
                storage!.datagramLowerHarnesses.remove(index: index)
            case .bridgeDatagram(let index):
                storage!.bridgeDatagramInstances[index].eventManager.unregister(state: &state)
                storage!.bridgeDatagramInstances.remove(index: index)
            case .quicDatagramFlow(let box):
                box.instance.eventManager.unregister(state: &state)
            default: break
            }
        }

        public func handleApplicationEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, event: ApplicationEvent) {
            switch protocolType {
            case .udp(let index): storage!.udpInstances[index].handleApplicationEvent(state: &state, from, event: event)
            case .demux(let index): storage!.demuxInstances[index].handleApplicationEvent(state: &state, from, event: event)
            case .ip(let index): storage!.ipInstances[index].handleApplicationEvent(state: &state, from, event: event)
            case .datagramLowerHarness(let index): storage!.datagramLowerHarnesses[index].handleApplicationEvent(state: &state, from, event: event)
            case .bridgeDatagram(let index): storage!.bridgeDatagramInstances[index].handleApplicationEvent(state: &state, from, event: event)
            case .quicDatagramFlow(let box): box.instance.handleApplicationEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleApplicationEvent call")
            }
        }

        public func getMetadata<P: NetworkProtocol>(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
            switch protocolType {
            case .udp(let index): return storage!.udpInstances[index].getMetadata(state: &state, from)
            case .demux(let index): return storage!.demuxInstances[index].getMetadata(state: &state, from)
            case .ip(let index): return storage!.ipInstances[index].getMetadata(state: &state, from)
            case .datagramLowerHarness(let index): return storage!.datagramLowerHarnesses[index].getMetadata(state: &state, from)
            case .bridgeDatagram(let index): return storage!.bridgeDatagramInstances[index].getMetadata(state: &state, from)
            case .quicDatagramFlow(let box): return box.instance.getMetadata(state: &state, from)
            default: fatalError("Protocol cannot accept getMetadata call")
            }
        }

        public func getMetrics(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            requestedNetworkMetric: RequestedNetworkMetrics
        ) -> NetworkMetrics? {
            switch protocolType {
            case .udp(let index): return storage!.udpInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .demux(let index): return storage!.demuxInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .ip(let index): return storage!.ipInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .datagramLowerHarness(let index): return storage!.datagramLowerHarnesses[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .bridgeDatagram(let index): return storage!.bridgeDatagramInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .quicDatagramFlow(let box): return box.instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            default: fatalError("Protocol cannot accept getMetrics call")
            }
        }

        public func invokeAttachUpperProtocol(_ upperProtocol: BaseNetworkProtocolStorage.BaseInboundDatagramLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            switch protocolType {
            case .udp(let index): try storage!.udpInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .demux(let index): try storage!.demuxInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .ip(let index): try storage!.ipInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .datagramLowerHarness(let index): try storage!.datagramLowerHarnesses[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .bridgeDatagram(let index): try storage!.bridgeDatagramInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .quicDatagramFlow(let box):
                var instance = box.instance
                try instance.attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
        }
        
        public typealias PairedUpperLinkage = BaseInboundDatagramLinkage

        public init() {
            self.reference = .init()
            self.storage = nil
            self.protocolType = .unknown
        }

        init(reference: ProtocolInstanceReference, storage: BaseNetworkProtocolStorage?, protocolType: ProtocolType) {
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
        enum ProtocolType: Hashable {
            case unknown
            case quic(NetworkStateIndex)
        }

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

        public typealias PairedUpperLinkage = BaseInboundDatagramFlowLinkage

        public func invokeAttachUpperProtocol(_ upperProtocol: PairedUpperLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            switch protocolType {
            case .quic(let index): try storage!.quicInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
        }

        public func invokeAttachUpperProtocolToNewFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            let lowerProtocol: PairedUpperLinkage.DataLinkage
            switch protocolType {
            case .quic(let index): lowerProtocol = try storage!.quicInstances[index].attachUpperProtocolToNewFlow(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            default: fatalError("Protocol cannot accept invokeAttachUpperProtocolToNewFlow call")
            }
            try upperProtocol.invokeAttachLowerProtocol(lowerProtocol, remote: remote, local: local, parameters: parameters, path: path)
        }

        public func invokeAttachUpperProtocolToExistingFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, existingFlowReference: ProtocolInstanceReference) throws(NetworkError) -> PairedUpperLinkage.DataLinkage {
            switch protocolType {
            case .quic(let index): return try storage!.quicInstances[index].attachUpperProtocolToExistingFlow(upperProtocol, existingFlowReference: existingFlowReference)
            default: fatalError("Protocol cannot accept invokeAttachUpperProtocolToExistingFlow call")
            }
        }

        public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .quic(let index): storage!.quicInstances[index].connect(state: &state, from)
            default: fatalError("Protocol cannot accept connect call")
            }
        }

        public func disconnect(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .quic(let index): storage!.quicInstances[index].disconnect(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept disconnect call")
            }
        }

        public func detach(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) throws(NetworkError) {
            switch protocolType {
            case .quic(let index): try storage!.quicInstances[index].detach(state: &state, from)
            default: fatalError("Protocol cannot accept detach call")
            }
        }

        public func teardown(state: inout NetworkContext.State) {
            switch protocolType {
            case .quic(let index):
                guard storage!.quicInstances[index].isFullyDetached else { return }
                storage!.quicInstances[index].eventManager.unregister(state: &state)
                storage!.quicInstances.remove(index: index)
            default: break
            }
        }

        public func handleApplicationEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            event: ApplicationEvent
        ) {
            switch protocolType {
            case .quic(let index): storage!.quicInstances[index].handleApplicationEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleApplicationEvent call")
            }
        }

        public func getMetadata<P: NetworkProtocol>(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) -> ProtocolMetadata<P>? {
            switch protocolType {
            case .quic(let index): return storage!.quicInstances[index].getMetadata(state: &state, from)
            default: return nil
            }
        }

        public func getMetrics(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            requestedNetworkMetric: RequestedNetworkMetrics
        ) -> NetworkMetrics? {
            switch protocolType {
            case .quic(let index):
                return storage!.quicInstances[index].getMetrics(
                    state: &state,
                    from,
                    requestedNetworkMetric: requestedNetworkMetric
                )
            default: return nil
            }
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

    public struct BaseInboundDatagramFlowLinkage: InboundDatagramFlowLinkage {
        enum ProtocolType: Hashable {
            case unknown
            case newDatagramFlowHarness(NetworkStateIndex)
        }

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

        public typealias DataLinkage = BaseOutboundDatagramLinkage
        public typealias PairedLowerLinkage = BaseDatagramListenerLinkage

        public func invokeAttachLowerProtocol(_ lowerProtocol: BaseNetworkProtocolStorage.BaseDatagramListenerLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            let overrideUpperLinkage: Self?
            switch protocolType {
            case .newDatagramFlowHarness(let index):
                overrideUpperLinkage = try storage!.newDatagramFlowHarnesses[index].attachLowerProtocol(lowerProtocol)
            default: fatalError("Protocol cannot accept invokeAttachLowerProtocol call")
            }
            let upperLinkage = overrideUpperLinkage ?? self
            try lowerProtocol.invokeAttachUpperProtocol(upperLinkage, remote: remote, local: local, parameters: parameters, path: path)
        }

        public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .newDatagramFlowHarness(let index):
                storage!.newDatagramFlowHarnesses[index].handleConnectedEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleConnectedEvent call")
            }
        }

        public func handleDisconnectedEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .newDatagramFlowHarness(let index):
                storage!.newDatagramFlowHarnesses[index].handleDisconnectedEvent(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept handleDisconnectedEvent call")
            }
        }

        public func handleNetworkProtocolEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            event: NetworkProtocolEvent
        ) {
            switch protocolType {
            case .newDatagramFlowHarness(let index):
                storage!.newDatagramFlowHarnesses[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleNetworkProtocolEvent call")
            }
        }

        public func handleNewInboundFlowEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            flowReference: ProtocolInstanceReference,
            flowMetadata: AbstractProtocolMetadata?
        ) {
            switch protocolType {
            case .newDatagramFlowHarness(let index):
                storage!.newDatagramFlowHarnesses[index].handleNewInboundFlowEvent(
                    state: &state,
                    from,
                    flowReference: flowReference,
                    flowMetadata: flowMetadata
                )
            default: fatalError("Protocol cannot accept handleNewInboundFlowEvent call")
            }
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

    // A multipath linkage lets a protocol that spans several paths accept a new lower
    // protocol for each one. QUIC is currently the only such protocol.
    public struct BaseDatagramMultipathLinkage: DatagramMultipathLinkage, @unchecked Sendable {
        enum ProtocolType: Hashable {
            case unknown
            case quic(NetworkStateIndex)
        }

        public typealias MultipathLowerProtocol = BaseOutboundDatagramLinkage

        public init() {
            self.reference = .init()
            self.storage = nil
            self.protocolType = .unknown
        }

        init(reference: ProtocolInstanceReference, storage: BaseNetworkProtocolStorage?, protocolType: ProtocolType) {
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

        public func invokeAttachLowerProtocolForNewPath(
            _ lowerProtocol: MultipathLowerProtocol,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            // This is an external entry point, so acquire the context state here and thread it
            // into the protocol below.
            try reference.fromExternal(state: &storage!.context.state) { state throws(NetworkError) in
                let upperLinkage: MultipathLowerProtocol.PairedUpperLinkage

                switch protocolType {
                case .quic(let index):
                    upperLinkage = try storage!.quicInstances[index].attachLowerProtocolForNewPath(
                        state: &state,
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                default: fatalError("Protocol cannot accept attachLowerProtocolForNewPath call")
                }
                try lowerProtocol.invokeAttachUpperProtocol(upperLinkage, remote: remote, local: local, parameters: parameters, path: path)
            }
        }
    }

    // MARK: - Stream Linkages

    public struct BaseInboundStreamLinkage: InboundStreamLinkage {
        enum ProtocolType: Hashable {
            case unknown
            case streamUpperHarness(NetworkStateIndex)
            case streamEndpointFlow(ProtocolInstanceBox<StreamEndpointFlowProtocol<BaseStreamLinkageFamily>>)
        }

        public func invokeAttachLowerProtocol(
            _ lowerProtocol: BaseNetworkProtocolStorage.BaseOutboundStreamLinkage,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            let overrideUpperLinkage: Self?
            switch protocolType {
            case .streamUpperHarness(let index): overrideUpperLinkage = try storage!.streamUpperHarnesses[index].attachLowerProtocol(lowerProtocol)
            case .streamEndpointFlow(let box):
                var flow = box.instance
                overrideUpperLinkage = try flow.attachLowerProtocol(lowerProtocol)
            default: fatalError("Protocol cannot accept attachLowerProtocol call")
            }
            let upperLinkage = overrideUpperLinkage ?? self
            try lowerProtocol.invokeAttachUpperProtocol(upperLinkage, remote: remote, local: local, parameters: parameters, path: path)
        }

        public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .streamUpperHarness(let index):
                storage!.streamUpperHarnesses[index].handleConnectedEvent(state: &state, from)
            case .streamEndpointFlow(let box):
                box.instance.handleConnectedEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleConnectedEvent call")
            }
        }

        public func handleDisconnectedEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .streamUpperHarness(let index):
                storage!.streamUpperHarnesses[index].handleDisconnectedEvent(state: &state, from, error: error)
            case .streamEndpointFlow(let box):
                box.instance.handleDisconnectedEvent(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept handleDisconnectedEvent call")
            }
        }

        public func handleNetworkProtocolEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            event: NetworkProtocolEvent
        ) {
            switch protocolType {
            case .streamUpperHarness(let index):
                storage!.streamUpperHarnesses[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            case .streamEndpointFlow(let box):
                box.instance.handleNetworkProtocolEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleNetworkProtocolEvent call")
            }
        }

        public func handleInboundDataAvailableEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) {
            switch protocolType {
            case .streamUpperHarness(let index):
                storage!.streamUpperHarnesses[index].handleInboundDataAvailableEvent(state: &state, from)
            case .streamEndpointFlow(let box):
                box.instance.handleInboundDataAvailableEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleInboundDataAvailableEvent call")
            }
        }

        public func handleOutboundRoomAvailableEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) {
            switch protocolType {
            case .streamUpperHarness(let index):
                storage!.streamUpperHarnesses[index].handleOutboundRoomAvailableEvent(state: &state, from)
            case .streamEndpointFlow(let box):
                box.instance.handleOutboundRoomAvailableEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleOutboundRoomAvailableEvent call")
            }
        }

        public func handleInboundAbortedEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .streamUpperHarness(let index):
                storage!.streamUpperHarnesses[index].handleInboundAbortedEvent(state: &state, from, error: error)
            case .streamEndpointFlow(let box):
                box.instance.handleInboundAbortedEvent(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept handleInboundAbortedEvent call")
            }
        }

        public func handleOutboundAbortedEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .streamUpperHarness(let index):
                storage!.streamUpperHarnesses[index].handleOutboundAbortedEvent(state: &state, from, error: error)
            case .streamEndpointFlow(let box):
                box.instance.handleOutboundAbortedEvent(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept handleOutboundAbortedEvent call")
            }
        }

        public typealias PairedLowerLinkage = BaseOutboundStreamLinkage

        public init() {
            self.reference = .init()
            self.storage = nil
            self.protocolType = .unknown
        }

        init(reference: ProtocolInstanceReference, storage: BaseNetworkProtocolStorage?, protocolType: ProtocolType) {
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

    public struct BaseOutboundStreamLinkage: OutboundStreamLinkage, @unchecked Sendable {
        enum ProtocolType: Hashable {
            case unknown
            case tcp(NetworkStateIndex)
            case streamLowerHarness(NetworkStateIndex)
            case bridgeStream(NetworkStateIndex)
            case quicStream(ProtocolInstanceBox<QUICStreamInstance<BaseQUICLinkageFamilies>>)
        }

        public func receiveStreamData(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            minimumBytes: Int,
            maximumBytes: Int
        ) throws(NetworkError) -> FrameArray? {
            switch protocolType {
            case .tcp(let index):
                return try storage!.tcpInstances[index].receiveStreamData(state: &state, from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
            case .streamLowerHarness(let index):
                return try storage!.streamLowerHarnesses[index].receiveStreamData(state: &state, from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
            case .bridgeStream(let index):
                return try storage!.bridgeStreamInstances[index].receiveStreamData(state: &state, from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
            case .quicStream(let box):
                var instance = box.instance
                return try instance.receiveStreamData(state: &state, from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
            default:
                return nil
            }
        }

        public func getOutboundStreamDataRoomAvailable(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) throws(NetworkError) -> Int {
            switch protocolType {
            case .tcp(let index):
                return try storage!.tcpInstances[index].getOutboundStreamDataRoomAvailable(state: &state, from)
            case .streamLowerHarness(let index):
                return try storage!.streamLowerHarnesses[index].getOutboundStreamDataRoomAvailable(state: &state, from)
            case .bridgeStream(let index):
                return try storage!.bridgeStreamInstances[index].getOutboundStreamDataRoomAvailable(state: &state, from)
            case .quicStream(let box):
                return try box.instance.getOutboundStreamDataRoomAvailable(state: &state, from)
            default:
                return 0
            }
        }

        public func sendStreamData(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            streamData: consuming FrameArray
        ) throws(NetworkError) {
            switch protocolType {
            case .tcp(let index):
                try storage!.tcpInstances[index].sendStreamData(state: &state, from, streamData: streamData)
            case .streamLowerHarness(let index):
                try storage!.streamLowerHarnesses[index].sendStreamData(state: &state, from, streamData: streamData)
            case .bridgeStream(let index):
                try storage!.bridgeStreamInstances[index].sendStreamData(state: &state, from, streamData: streamData)
            case .quicStream(let box):
                var instance = box.instance
                try instance.sendStreamData(state: &state, from, streamData: streamData)
            default:
                var streamData = streamData
                streamData.finalizeAllFramesAsFailed()
                return
            }
        }

        public func sendEarlyStreamData(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            streamData: consuming FrameArray
        ) throws(NetworkError) {
            switch protocolType {
            case .quicStream(let box):
                var instance = box.instance
                try instance.sendEarlyStreamData(state: &state, from, streamData: streamData)
            default:
                // Only QUIC supports sending data before the handshake completes.
                var streamData = streamData
                streamData.finalizeAllFramesAsFailed()
                throw NetworkError.posix(ENOTSUP)
            }
        }

        public func abortInbound(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) throws(NetworkError) {
            switch protocolType {
            case .quicStream(let box):
                box.instance.abortInbound(state: &state, from, error: error)
            default:
                throw NetworkError.posix(ENOTSUP)
            }
        }

        public func abortOutbound(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) throws(NetworkError) {
            switch protocolType {
            case .quicStream(let box):
                box.instance.abortOutbound(state: &state, from, error: error)
            default:
                throw NetworkError.posix(ENOTSUP)
            }
        }

        public func isConnected(state: inout NetworkContext.State) -> Bool {
            reference.isConnected(state: &state)
        }

        public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .tcp(let index): storage!.tcpInstances[index].connect(state: &state, from)
            case .streamLowerHarness(let index): storage!.streamLowerHarnesses[index].connect(state: &state, from)
            case .bridgeStream(let index): storage!.bridgeStreamInstances[index].connect(state: &state, from)
            case .quicStream(let box): box.instance.connect(state: &state, from)
            default: fatalError("Protocol cannot accept connect call")
            }
        }

        public func disconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?) {
            switch protocolType {
            case .tcp(let index): storage!.tcpInstances[index].disconnect(state: &state, from, error: error)
            case .streamLowerHarness(let index):
                storage!.streamLowerHarnesses[index].disconnect(state: &state, from, error: error)
            case .bridgeStream(let index):
                storage!.bridgeStreamInstances[index].disconnect(state: &state, from, error: error)
            case .quicStream(let box):
                box.instance.disconnect(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept disconnect call")
            }
        }

        public func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError) {
            switch protocolType {
            case .tcp(let index):
                try storage!.tcpInstances[index].detach(state: &state, from)
            case .streamLowerHarness(let index):
                try storage!.streamLowerHarnesses[index].detach(state: &state, from)
            case .bridgeStream(let index):
                try storage!.bridgeStreamInstances[index].detach(state: &state, from)
            case .quicStream(let box):
                var instance = box.instance
                try instance.detach(state: &state, from)
            default: fatalError("Protocol cannot accept detach call")
            }
        }

        public func teardown(state: inout NetworkContext.State) {
            switch protocolType {
            case .tcp(let index):
                storage!.tcpInstances[index].eventManager.unregister(state: &state)
                storage!.tcpInstances.remove(index: index)
            case .streamLowerHarness(let index):
                storage!.streamLowerHarnesses[index].eventManager.unregister(state: &state)
                storage!.streamLowerHarnesses.remove(index: index)
            case .bridgeStream(let index):
                storage!.bridgeStreamInstances[index].eventManager.unregister(state: &state)
                storage!.bridgeStreamInstances.remove(index: index)
            case .quicStream(let box):
                box.instance.eventManager.unregister(state: &state)
            default: break
            }
        }

        public func handleApplicationEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, event: ApplicationEvent) {
            switch protocolType {
            case .tcp(let index): storage!.tcpInstances[index].handleApplicationEvent(state: &state, from, event: event)
            case .streamLowerHarness(let index):
                storage!.streamLowerHarnesses[index].handleApplicationEvent(state: &state, from, event: event)
            case .bridgeStream(let index):
                storage!.bridgeStreamInstances[index].handleApplicationEvent(state: &state, from, event: event)
            case .quicStream(let box):
                box.instance.handleApplicationEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleApplicationEvent call")
            }
        }

        public func getMetadata<P: NetworkProtocol>(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
            switch protocolType {
            case .tcp(let index): return storage!.tcpInstances[index].getMetadata(state: &state, from)
            case .streamLowerHarness(let index):
                return storage!.streamLowerHarnesses[index].getMetadata(state: &state, from)
            case .bridgeStream(let index):
                return storage!.bridgeStreamInstances[index].getMetadata(state: &state, from)
            case .quicStream(let box):
                return box.instance.getMetadata(state: &state, from)
            default: fatalError("Protocol cannot accept getMetadata call")
            }
        }

        public func getMetrics(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            requestedNetworkMetric: RequestedNetworkMetrics
        ) -> NetworkMetrics? {
            switch protocolType {
            case .tcp(let index):
                return storage!.tcpInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .streamLowerHarness(let index):
                return storage!.streamLowerHarnesses[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .bridgeStream(let index):
                return storage!.bridgeStreamInstances[index].getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .quicStream(let box):
                return box.instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            default: fatalError("Protocol cannot accept getMetrics call")
            }
        }

        public func invokeAttachUpperProtocol(
            _ upperProtocol: BaseNetworkProtocolStorage.BaseInboundStreamLinkage,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            switch protocolType {
            case .tcp(let index): try storage!.tcpInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .streamLowerHarness(let index): try storage!.streamLowerHarnesses[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .bridgeStream(let index): try storage!.bridgeStreamInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            case .quicStream(let box):
                var instance = box.instance
                try instance.attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
        }

        public typealias PairedUpperLinkage = BaseInboundStreamLinkage

        public init() {
            self.reference = .init()
            self.storage = nil
            self.protocolType = .unknown
        }

        init(reference: ProtocolInstanceReference, storage: BaseNetworkProtocolStorage?, protocolType: ProtocolType) {
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

    public struct BaseStreamListenerLinkage: StreamListenerLinkage {
        enum ProtocolType: Hashable {
            case unknown
            case quic(NetworkStateIndex)
        }

        public typealias PairedUpperLinkage = BaseInboundStreamFlowLinkage

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

        public func invokeAttachUpperProtocol(
            _ upperProtocol: PairedUpperLinkage,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            switch protocolType {
            case .quic(let index): try storage!.quicInstances[index].attachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
        }

        public func invokeAttachUpperProtocolToNewFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
            let lowerProtocol: PairedUpperLinkage.DataLinkage
            switch protocolType {
            case .quic(let index): lowerProtocol = try storage!.quicInstances[index].attachUpperProtocolToNewFlow(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
            default: fatalError("Protocol cannot accept invokeAttachUpperProtocolToNewFlow call")
            }
            try upperProtocol.invokeAttachLowerProtocol(lowerProtocol, remote: remote, local: local, parameters: parameters, path: path)
        }

        public func invokeAttachUpperProtocolToExistingFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, existingFlowReference: ProtocolInstanceReference) throws(NetworkError) -> PairedUpperLinkage.DataLinkage {
            switch protocolType {
            case .quic(let index): return try storage!.quicInstances[index].attachUpperProtocolToExistingFlow(upperProtocol, existingFlowReference: existingFlowReference)
            default: fatalError("Protocol cannot accept invokeAttachUpperProtocolToExistingFlow call")
            }
        }

        public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .quic(let index): storage!.quicInstances[index].connect(state: &state, from)
            default: fatalError("Protocol cannot accept connect call")
            }
        }

        public func disconnect(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .quic(let index): storage!.quicInstances[index].disconnect(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept disconnect call")
            }
        }

        public func detach(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) throws(NetworkError) {
            switch protocolType {
            case .quic(let index): try storage!.quicInstances[index].detach(state: &state, from)
            default: fatalError("Protocol cannot accept detach call")
            }
        }

        public func teardown(state: inout NetworkContext.State) {
            switch protocolType {
            case .quic(let index):
                guard storage!.quicInstances[index].isFullyDetached else { return }
                storage!.quicInstances[index].eventManager.unregister(state: &state)
                storage!.quicInstances.remove(index: index)
            default: break
            }
        }

        public func handleApplicationEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            event: ApplicationEvent
        ) {
            switch protocolType {
            case .quic(let index): storage!.quicInstances[index].handleApplicationEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleApplicationEvent call")
            }
        }

        public func getMetadata<P: NetworkProtocol>(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) -> ProtocolMetadata<P>? {
            switch protocolType {
            case .quic(let index): return storage!.quicInstances[index].getMetadata(state: &state, from)
            default: return nil
            }
        }

        public func getMetrics(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            requestedNetworkMetric: RequestedNetworkMetrics
        ) -> NetworkMetrics? {
            switch protocolType {
            case .quic(let index):
                return storage!.quicInstances[index].getMetrics(
                    state: &state,
                    from,
                    requestedNetworkMetric: requestedNetworkMetric
                )
            default: return nil
            }
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

    public struct BaseInboundStreamFlowLinkage: InboundStreamFlowLinkage {
        enum ProtocolType: Hashable {
            case unknown
            case newStreamFlowHarness(NetworkStateIndex)
        }

        public typealias DataLinkage = BaseOutboundStreamLinkage
        public typealias PairedLowerLinkage = BaseStreamListenerLinkage

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

        public func invokeAttachLowerProtocol(
            _ lowerProtocol: BaseNetworkProtocolStorage.BaseStreamListenerLinkage,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            let overrideUpperLinkage: Self?
            switch protocolType {
            case .newStreamFlowHarness(let index):
                overrideUpperLinkage = try storage!.newStreamFlowHarnesses[index].attachLowerProtocol(lowerProtocol)
            default: fatalError("Protocol cannot accept invokeAttachLowerProtocol call")
            }
            let upperLinkage = overrideUpperLinkage ?? self
            try lowerProtocol.invokeAttachUpperProtocol(upperLinkage, remote: remote, local: local, parameters: parameters, path: path)
        }

        public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            switch protocolType {
            case .newStreamFlowHarness(let index):
                storage!.newStreamFlowHarnesses[index].handleConnectedEvent(state: &state, from)
            default: fatalError("Protocol cannot accept handleConnectedEvent call")
            }
        }

        public func handleDisconnectedEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            switch protocolType {
            case .newStreamFlowHarness(let index):
                storage!.newStreamFlowHarnesses[index].handleDisconnectedEvent(state: &state, from, error: error)
            default: fatalError("Protocol cannot accept handleDisconnectedEvent call")
            }
        }

        public func handleNetworkProtocolEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            event: NetworkProtocolEvent
        ) {
            switch protocolType {
            case .newStreamFlowHarness(let index):
                storage!.newStreamFlowHarnesses[index].handleNetworkProtocolEvent(state: &state, from, event: event)
            default: fatalError("Protocol cannot accept handleNetworkProtocolEvent call")
            }
        }

        public func handleNewInboundFlowEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            flowReference: ProtocolInstanceReference,
            flowMetadata: AbstractProtocolMetadata?
        ) {
            switch protocolType {
            case .newStreamFlowHarness(let index):
                storage!.newStreamFlowHarnesses[index].handleNewInboundFlowEvent(
                    state: &state,
                    from,
                    flowReference: flowReference,
                    flowMetadata: flowMetadata
                )
            default: fatalError("Protocol cannot accept handleNewInboundFlowEvent call")
            }
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

    internal var udpInstances = NetworkGappyArray<UDPProtocol.UDPInstance<BaseDatagramLinkageFamily>>()

    public func createUDPInstance() -> (BaseInboundDatagramLinkage, BaseOutboundDatagramLinkage) {
        let instance = UDPProtocol.UDPInstance<BaseDatagramLinkageFamily>(context: context)

        let instanceIndex = udpInstances.insert(instance)

        let reference = udpInstances[instanceIndex].reference
        let inbound = BaseInboundDatagramLinkage(reference: reference, storage: self, protocolType: .udp(instanceIndex))
        let outbound = BaseOutboundDatagramLinkage(reference: reference, storage: self, protocolType: .udp(instanceIndex))

        return (inbound, outbound)
    }

    internal var demuxInstances = NetworkGappyArray<DemuxProtocol.DemuxInstance<BaseDatagramLinkageFamily>>()

    public func createDemuxInstance() -> (BaseInboundDatagramLinkage, BaseOutboundDatagramLinkage) {
        let instance = DemuxProtocol.DemuxInstance<BaseDatagramLinkageFamily>(context: context)

        let instanceIndex = demuxInstances.insert(instance)

        let reference = demuxInstances[instanceIndex].reference
        let inbound = BaseInboundDatagramLinkage(reference: reference, storage: self, protocolType: .demux(instanceIndex))
        let outbound = BaseOutboundDatagramLinkage(reference: reference, storage: self, protocolType: .demux(instanceIndex))

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

    internal var bridgeDatagramInstances = NetworkGappyArray< BridgeDatagramProtocol.BridgeInstance>()

    public func createBridgeDatagramInstance() -> BaseOutboundDatagramLinkage {
        let instance = BridgeDatagramProtocol.BridgeInstance(context: context)
        let instanceIndex = bridgeDatagramInstances.insert(instance)

        return BaseOutboundDatagramLinkage(
            reference: instance.reference,
            storage: self,
            protocolType: .bridgeDatagram(instanceIndex)
        )
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

    /// Creates a datagram upper harness using a context state the caller already holds.
    func createDatagramUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext,
        state: inout NetworkContext.State
    ) -> (DatagramUpperHarness<BaseDatagramLinkageFamily>, BaseInboundDatagramLinkage) {
        let instance = DatagramUpperHarness<BaseDatagramLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context,
            state: &state
        )
        let instanceIndex = datagramUpperHarnesses.insert(instance)

        let reference = instance.reference
        let inbound = BaseInboundDatagramLinkage(
            reference: reference,
            storage: self,
            protocolType: .datagramUpperHarness(instanceIndex)
        )

        return (instance, inbound)
    }

    internal var newDatagramFlowHarnesses = NetworkGappyArray<NewDatagramFlowHarness<BaseDatagramLinkageFamily>>()

    public func createNewDatagramFlowHarness(identifier: String = "",
                                             local: Endpoint,
                                             remote: Endpoint,
                                             parameters: Parameters,
                                             path: PathProperties,
                                             context: NetworkContext) -> (NewDatagramFlowHarness<BaseDatagramLinkageFamily>, BaseInboundDatagramFlowLinkage) {
        let instance = NewDatagramFlowHarness<BaseDatagramLinkageFamily>(identifier: identifier,
                                                                         local: local,
                                                                         remote: remote,
                                                                         parameters: parameters,
                                                                         path: path,
                                                                         context: context) { state in
            self.createDatagramUpperHarness(
                identifier: "Inbound",
                local: local,
                remote: remote,
                parameters: parameters,
                path: path,
                context: context,
                state: &state
            )
        }
        let instanceIndex = newDatagramFlowHarnesses.insert(instance)

        let reference = instance.reference
        let inboundFlow = BaseInboundDatagramFlowLinkage(reference: reference, storage: self, protocolType: .newDatagramFlowHarness(instanceIndex))

        return (instance, inboundFlow)
    }

    // Endpoint flows are referenced directly by the linkage rather than stored here: the
    // flow owns its own lifetime, so there is nothing for the storage to keep track of.
    internal static func linkage(
        for flow: DatagramEndpointFlowProtocol<BaseDatagramLinkageFamily>
    ) -> BaseInboundDatagramLinkage {
        BaseInboundDatagramLinkage(
            reference: flow.reference,
            storage: nil,
            protocolType: .datagramEndpointFlow(.init(flow))
        )
    }

    // MARK: - Stream Protocol Instances

    internal var tcpInstances = NetworkGappyArray<
        TCPProtocol.TCPInstance<BaseStreamLinkageFamily, BaseDatagramLinkageFamily>
    >()

    // TCP straddles the two families: stream data above, datagrams below. The returned
    // inbound linkage is therefore a *datagram* linkage, for lower protocols to attach
    // below TCP, while the outbound linkage is a *stream* linkage, for upper protocols
    // to attach above it.
    public func createTCPInstance() -> (BaseInboundDatagramLinkage, BaseOutboundStreamLinkage) {
        let instance = TCPProtocol.TCPInstance<BaseStreamLinkageFamily, BaseDatagramLinkageFamily>(
            context: context
        )

        let instanceIndex = tcpInstances.insert(instance)

        let reference = tcpInstances[instanceIndex].reference
        let inbound = BaseInboundDatagramLinkage(
            reference: reference,
            storage: self,
            protocolType: .tcp(instanceIndex)
        )
        let outbound = BaseOutboundStreamLinkage(reference: reference, storage: self, protocolType: .tcp(instanceIndex))

        return (inbound, outbound)
    }

    internal var streamLowerHarnesses = NetworkGappyArray<StreamLowerHarness<BaseStreamLinkageFamily>>()

    public func createStreamLowerHarness(
        identifier: String = "",
        context: NetworkContext
    ) -> (StreamLowerHarness<BaseStreamLinkageFamily>, BaseOutboundStreamLinkage) {
        let instance = StreamLowerHarness<BaseStreamLinkageFamily>(identifier: identifier, context: context)
        let instanceIndex = streamLowerHarnesses.insert(instance)

        let reference = instance.reference
        let outbound = BaseOutboundStreamLinkage(
            reference: reference,
            storage: self,
            protocolType: .streamLowerHarness(instanceIndex)
        )

        return (instance, outbound)
    }

    internal var bridgeStreamInstances = NetworkGappyArray<BridgeStreamProtocol.BridgeInstance>()

    public func createBridgeStreamInstance() -> BaseOutboundStreamLinkage {
        let instance = BridgeStreamProtocol.BridgeInstance(context: context)
        let instanceIndex = bridgeStreamInstances.insert(instance)

        return BaseOutboundStreamLinkage(
            reference: instance.reference,
            storage: self,
            protocolType: .bridgeStream(instanceIndex)
        )
    }

    internal var streamUpperHarnesses = NetworkGappyArray<StreamUpperHarness<BaseStreamLinkageFamily>>()

    public func createStreamUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) -> (StreamUpperHarness<BaseStreamLinkageFamily>, BaseInboundStreamLinkage) {
        let instance = StreamUpperHarness<BaseStreamLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context
        )
        let instanceIndex = streamUpperHarnesses.insert(instance)

        let reference = instance.reference
        let inbound = BaseInboundStreamLinkage(
            reference: reference,
            storage: self,
            protocolType: .streamUpperHarness(instanceIndex)
        )

        return (instance, inbound)
    }

    fileprivate func createStreamUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext,
        state: inout NetworkContext.State
    ) -> (StreamUpperHarness<BaseStreamLinkageFamily>, BaseInboundStreamLinkage) {
        let instance = StreamUpperHarness<BaseStreamLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context,
            state: &state
        )
        let instanceIndex = streamUpperHarnesses.insert(instance)

        let reference = instance.reference
        let inbound = BaseInboundStreamLinkage(
            reference: reference,
            storage: self,
            protocolType: .streamUpperHarness(instanceIndex)
        )

        return (instance, inbound)
    }


    internal var newStreamFlowHarnesses = NetworkGappyArray<NewStreamFlowHarness<BaseStreamLinkageFamily>>()

    public func createNewStreamFlowHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) -> (NewStreamFlowHarness<BaseStreamLinkageFamily>, BaseInboundStreamFlowLinkage) {
        let instance = NewStreamFlowHarness<BaseStreamLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context
        ) { state in
            self.createStreamUpperHarness(identifier: "Inbound", local: local, remote: remote,
                                          parameters: parameters, path: path, context: context,
                                          state: &state)
        }
        let instanceIndex = newStreamFlowHarnesses.insert(instance)

        let reference = instance.reference
        let inboundFlow = BaseInboundStreamFlowLinkage(
            reference: reference,
            storage: self,
            protocolType: .newStreamFlowHarness(instanceIndex)
        )

        return (instance, inboundFlow)
    }

    // Endpoint flows are referenced directly by the linkage rather than stored here: the
    // flow owns its own lifetime, so there is nothing for the storage to keep track of.
    internal static func linkage(
        for flow: StreamEndpointFlowProtocol<BaseStreamLinkageFamily>
    ) -> BaseInboundStreamLinkage {
        BaseInboundStreamLinkage(
            reference: flow.reference,
            storage: nil,
            protocolType: .streamEndpointFlow(.init(flow))
        )
    }

    internal var quicInstances = NetworkGappyArray<QUICConnection<BaseQUICLinkageFamilies>>()

    public func createQUICInstance() -> (BaseStreamListenerLinkage, BaseDatagramListenerLinkage, BaseDatagramMultipathLinkage) {
        let instance = QUICConnection<BaseQUICLinkageFamilies>(context: context)

        let instanceIndex = quicInstances.insert(instance)

        let reference = instance.reference
        let stream = BaseStreamListenerLinkage(reference: reference, storage: self, protocolType: .quic(instanceIndex))
        let datagram = BaseDatagramListenerLinkage(reference: reference, storage: self, protocolType: .quic(instanceIndex))
        let multipath = BaseDatagramMultipathLinkage(reference: reference, storage: self, protocolType: .quic(instanceIndex))

        return (stream, datagram, multipath)
    }

    public func quicInstance(for linkage: BaseStreamListenerLinkage) -> QUICConnection<BaseQUICLinkageFamilies>? {
        switch linkage.protocolType {
        case .quic(let index): return quicInstances[index]
        default: return nil
        }
    }

    public func quicInstance(for linkage: BaseDatagramListenerLinkage) -> QUICConnection<BaseQUICLinkageFamilies>? {
        switch linkage.protocolType {
        case .quic(let index): return quicInstances[index]
        default: return nil
        }
    }

    public func quicInstance(for linkage: BaseDatagramMultipathLinkage) -> QUICConnection<BaseQUICLinkageFamilies>? {
        switch linkage.protocolType {
        case .quic(let index): return quicInstances[index]
        default: return nil
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseQUICLinkageFamilies: QUICLinkageFamilies {
    public typealias StreamFlowLinkageFamily = BaseStreamLinkageFamily
    public typealias DatagramFlowLinkageFamily = BaseDatagramLinkageFamily
    public typealias PathLinkageFamily = BaseDatagramLinkageFamily
    public typealias MultipathLinkageType = BaseNetworkProtocolStorage.BaseDatagramMultipathLinkage
}

// MARK: - Stub "default" types to be removed

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
public struct DefaultInboundDatagramLinkage: InboundDatagramLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = DefaultOutboundDatagramLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) { self.reference = reference }
    public init() { self.reference = .init() }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLowerLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
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
public struct DefaultOutboundDatagramLinkage: OutboundDatagramLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = DefaultInboundDatagramLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) {
        self.reference = reference
    }
    public init() {
        reference = .init()
    }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: PairedUpperLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
    }

    public func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
    }

    public func teardown(state: inout NetworkContext.State) {
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        return nil
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        return nil
    }

    public func receiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        return nil
    }
    public func getDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        return nil
    }
    public func sendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        var datagrams = datagrams
        datagrams.finalizeAllFramesAsFailed()
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultInboundDatagramFlowLinkage: InboundDatagramFlowLinkage {
    public typealias PairedLowerLinkage = DefaultDatagramListenerLinkage
    public typealias DataLinkage = DefaultOutboundDatagramLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) { self.reference = reference }
    public init() { self.reference = .init() }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLowerLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
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
    public typealias PairedUpperLinkage = DefaultInboundDatagramFlowLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init(reference: ProtocolInstanceReference) { self.reference = reference }
    public init() { self.reference = .init() }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: PairedUpperLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
    }

    public func invokeAttachUpperProtocolToNewFlow(_ upperProtocol: DefaultInboundDatagramLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
    }

    public func invokeAttachUpperProtocolToExistingFlow(_ upperProtocol: DefaultInboundDatagramLinkage, existingFlowReference: ProtocolInstanceReference) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
        throw .posix(ENOTSUP)
    }
    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
    }

    public func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
    }

    public func teardown(state: inout NetworkContext.State) {
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        return nil
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        return nil
    }
}

/// A stub outbound stream linkage, for protocols that haven't yet moved over to a
/// concrete stream linkage family.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultOutboundStreamLinkage: OutboundStreamLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = DefaultInboundStreamLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init() { self.reference = .init() }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: PairedUpperLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
    }

    public func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
    }

    public func teardown(state: inout NetworkContext.State) {
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        return nil
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        return nil
    }

    public func receiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        return nil
    }
    public func getOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        return 0
    }
    public func sendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        var streamData = streamData
        streamData.finalizeAllFramesAsFailed()
    }

    public func sendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        var streamData = streamData
        streamData.finalizeAllFramesAsFailed()
    }

    public func abortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
    }
    public func abortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
    }
}


/// A stub inbound stream linkage, for protocols that haven't yet moved over to a
/// concrete stream linkage family.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultInboundStreamLinkage: InboundStreamLinkage {
    public typealias PairedLowerLinkage = DefaultOutboundStreamLinkage
    private(set) public var reference: ProtocolInstanceReference
    public init() { self.reference = .init() }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: PairedLowerLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
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

// MARK: - QUIC Linkage Construction

// A protocol stack that supports QUIC needs to be able to wrap a QUIC stream, datagram flow,
// or path in a linkage knowing only the QUIC linkage family. The Base linkages carry the
// instance directly in their protocol type, so they can satisfy these initializers.

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension BaseNetworkProtocolStorage.BaseOutboundStreamLinkage: QUICStreamLowerLinkage {
    public typealias QUICFamilies = BaseQUICLinkageFamilies

    public init(_ quicStream: QUICStreamInstance<BaseQUICLinkageFamilies>) {
        self.init(
            reference: quicStream.reference,
            storage: nil,
            protocolType: .quicStream(.init(quicStream))
        )
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension BaseNetworkProtocolStorage.BaseOutboundDatagramLinkage: QUICDatagramFlowLowerLinkage {
    public typealias QUICFamilies = BaseQUICLinkageFamilies

    public init(_ quicDatagramFlow: QUICDatagramFlow<BaseQUICLinkageFamilies>) {
        self.init(
            reference: quicDatagramFlow.reference,
            storage: nil,
            protocolType: .quicDatagramFlow(.init(quicDatagramFlow))
        )
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension BaseNetworkProtocolStorage.BaseInboundDatagramLinkage: QUICPathUpperLinkage {
    public typealias QUICFamilies = BaseQUICLinkageFamilies

    public init(_ quicPath: QUICPath<BaseQUICLinkageFamilies>) {
        self.init(
            reference: quicPath.reference,
            storage: nil,
            protocolType: .quicPath(.init(quicPath))
        )
    }
}
