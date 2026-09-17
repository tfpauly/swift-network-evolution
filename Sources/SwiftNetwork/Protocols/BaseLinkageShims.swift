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

// The base linkages the framework's own stack is built from, to use when
// running the base protocols directly.

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
public struct BaseDatagramUpper: InboundDatagramLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = BaseDatagramLower

    var base: BaseInboundDatagramLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseInboundDatagramLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func invokeAttachLowerProtocol(_ lowerProtocol: BaseDatagramLower, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
        try base.invokeAttachLowerProtocol(lowerProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.handleConnectedEvent(state: &state, from)
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.handleDisconnectedEvent(state: &state, from, error: error)
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        base.handleNetworkProtocolEvent(state: &state, from, event: event)
    }

    public func handleInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        base.handleInboundDataAvailableEvent(state: &state, from)
    }

    public func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        base.handleOutboundRoomAvailableEvent(state: &state, from)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseDatagramLower: OutboundDatagramLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = BaseDatagramUpper

    var base: BaseOutboundDatagramLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseOutboundDatagramLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func receiveDatagrams(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, maximumDatagramCount: Int) throws(NetworkError) -> FrameArray? {
        return try base.receiveDatagrams(state: &state, from, maximumDatagramCount: maximumDatagramCount)
    }

    public func getDatagramsToSend(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, maximumDatagramCount: Int, minimumDatagramSize: Int) throws(NetworkError) -> FrameArray? {
        return try base.getDatagramsToSend(state: &state, from, maximumDatagramCount: maximumDatagramCount, minimumDatagramSize: minimumDatagramSize)
    }

    public func sendDatagrams(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, datagrams: consuming FrameArray) throws(NetworkError) {
        try base.sendDatagrams(state: &state, from, datagrams: datagrams)
    }

    public func isConnected(state: inout NetworkContext.State) -> Bool {
        return base.isConnected(state: &state)
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.connect(state: &state, from)
    }

    public func disconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?) {
        base.disconnect(state: &state, from, error: error)
    }

    public func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError) {
        try base.detach(state: &state, from)
    }

    public func teardown(state: inout NetworkContext.State) {
        base.teardown(state: &state)
    }

    public func handleApplicationEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, event: ApplicationEvent) {
        base.handleApplicationEvent(state: &state, from, event: event)
    }

    public func getMetadata<P: NetworkProtocol>(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
        return base.getMetadata(state: &state, from)
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        return base.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
    }

    public func invokeAttachUpperProtocol(_ upperProtocol: BaseDatagramUpper, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
        try base.invokeAttachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseDatagramListener: DatagramListenerLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = BaseDatagramInboundFlow

    var base: BaseDatagramListenerLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseDatagramListenerLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func invokeAttachUpperProtocol(_ upperProtocol: PairedUpperLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
        try base.invokeAttachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func invokeAttachUpperProtocolToNewFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
        try base.invokeAttachUpperProtocolToNewFlow(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func invokeAttachUpperProtocolToExistingFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, existingFlowReference: ProtocolInstanceReference) throws(NetworkError) -> PairedUpperLinkage.DataLinkage {
        return try base.invokeAttachUpperProtocolToExistingFlow(upperProtocol, existingFlowReference: existingFlowReference)
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.connect(state: &state, from)
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.disconnect(state: &state, from, error: error)
    }

    public func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        try base.detach(state: &state, from)
    }

    public func teardown(state: inout NetworkContext.State) {
        base.teardown(state: &state)
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        base.handleApplicationEvent(state: &state, from, event: event)
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        return base.getMetadata(state: &state, from)
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        return base.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseDatagramInboundFlow: InboundDatagramFlowLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = BaseDatagramListener
    public typealias DataLinkage = BaseDatagramLower

    var base: BaseInboundDatagramFlowLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseInboundDatagramFlowLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func invokeAttachLowerProtocol(_ lowerProtocol: BaseDatagramListener, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
        try base.invokeAttachLowerProtocol(lowerProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.handleConnectedEvent(state: &state, from)
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.handleDisconnectedEvent(state: &state, from, error: error)
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        base.handleNetworkProtocolEvent(state: &state, from, event: event)
    }

    public func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        base.handleNewInboundFlowEvent(state: &state, from, flowReference: flowReference, flowMetadata: flowMetadata)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseDatagramMultipath: DatagramMultipathLinkage, @unchecked Sendable {
    public typealias MultipathLowerProtocol = BaseDatagramLower

    var base: BaseDatagramMultipathLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseDatagramMultipathLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }


    public func invokeAttachLowerProtocolForNewPath(
        _ lowerProtocol: MultipathLowerProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try base.invokeAttachLowerProtocolForNewPath(lowerProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseStreamUpper: InboundStreamLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = BaseStreamLower

    var base: BaseInboundStreamLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseInboundStreamLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: BaseStreamLower,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try base.invokeAttachLowerProtocol(lowerProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.handleConnectedEvent(state: &state, from)
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.handleDisconnectedEvent(state: &state, from, error: error)
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        base.handleNetworkProtocolEvent(state: &state, from, event: event)
    }

    public func handleInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        base.handleInboundDataAvailableEvent(state: &state, from)
    }

    public func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        base.handleOutboundRoomAvailableEvent(state: &state, from)
    }

    public func handleInboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.handleInboundAbortedEvent(state: &state, from, error: error)
    }

    public func handleOutboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.handleOutboundAbortedEvent(state: &state, from, error: error)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseStreamLower: OutboundStreamLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = BaseStreamUpper

    var base: BaseOutboundStreamLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseOutboundStreamLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func receiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        return try base.receiveStreamData(state: &state, from, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }

    public func getOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        return try base.getOutboundStreamDataRoomAvailable(state: &state, from)
    }

    public func sendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        try base.sendStreamData(state: &state, from, streamData: streamData)
    }

    public func sendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        try base.sendEarlyStreamData(state: &state, from, streamData: streamData)
    }

    public func abortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
        try base.abortInbound(state: &state, from, error: error)
    }

    public func abortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
        try base.abortOutbound(state: &state, from, error: error)
    }

    public func isConnected(state: inout NetworkContext.State) -> Bool {
        return base.isConnected(state: &state)
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.connect(state: &state, from)
    }

    public func disconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?) {
        base.disconnect(state: &state, from, error: error)
    }

    public func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError) {
        try base.detach(state: &state, from)
    }

    public func teardown(state: inout NetworkContext.State) {
        base.teardown(state: &state)
    }

    public func handleApplicationEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, event: ApplicationEvent) {
        base.handleApplicationEvent(state: &state, from, event: event)
    }

    public func getMetadata<P: NetworkProtocol>(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
        return base.getMetadata(state: &state, from)
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        return base.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
    }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: BaseStreamUpper,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try base.invokeAttachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseStreamListener: StreamListenerLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = BaseStreamInboundFlow

    var base: BaseStreamListenerLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseStreamListenerLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: PairedUpperLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try base.invokeAttachUpperProtocol(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func invokeAttachUpperProtocolToNewFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) {
        try base.invokeAttachUpperProtocolToNewFlow(upperProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func invokeAttachUpperProtocolToExistingFlow(_ upperProtocol: PairedUpperLinkage.DataLinkage.PairedUpperLinkage, existingFlowReference: ProtocolInstanceReference) throws(NetworkError) -> PairedUpperLinkage.DataLinkage {
        return try base.invokeAttachUpperProtocolToExistingFlow(upperProtocol, existingFlowReference: existingFlowReference)
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.connect(state: &state, from)
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.disconnect(state: &state, from, error: error)
    }

    public func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        try base.detach(state: &state, from)
    }

    public func teardown(state: inout NetworkContext.State) {
        base.teardown(state: &state)
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        base.handleApplicationEvent(state: &state, from, event: event)
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        return base.getMetadata(state: &state, from)
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        return base.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct BaseStreamInboundFlow: InboundStreamFlowLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = BaseStreamListener
    public typealias DataLinkage = BaseStreamLower

    var base: BaseInboundStreamFlowLinkage<BaseLinkageFamilyGroup>

    public init() { base = .init() }

    init(base: BaseInboundStreamFlowLinkage<BaseLinkageFamilyGroup>) { self.base = base }

    public var reference: ProtocolInstanceReference { base.reference }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: BaseStreamListener,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try base.invokeAttachLowerProtocol(lowerProtocol, remote: remote, local: local, parameters: parameters, path: path)
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        base.handleConnectedEvent(state: &state, from)
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        base.handleDisconnectedEvent(state: &state, from, error: error)
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        base.handleNetworkProtocolEvent(state: &state, from, event: event)
    }

    public func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        base.handleNewInboundFlowEvent(state: &state, from, flowReference: flowReference, flowMetadata: flowMetadata)
    }
}
