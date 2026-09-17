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

#if canImport(SwiftNetwork)
@_spi(Essentials) @_spi(ProtocolProvider) import SwiftNetwork
#elseif canImport(Network)
@_spi(Essentials) @_spi(ProtocolProvider) import Network
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// The stream half of the out-of-package linkage family, and the QUIC families that go with it.
//
// This mirrors `TestProtocolLinkages.swift`: each `Test*` linkage wraps the matching `Base*`
// linkage, adds cases for the protocols only this module knows about -- here, the stream
// harnesses -- and falls through to the wrapped base linkage for everything the framework
// provides.
//
// The QUIC families exist because a harness has to be able to sit directly on top of a QUIC
// stream or datagram flow. QUIC hands its upper protocol a linkage built from
// `Families.StreamFamily.Lower`, so that lower linkage needs both a harness case and
// a `quicStream` case. Wrapping the base linkage is not enough on its own: the base linkage's
// `quicStream` case carries a `QUICStreamInstance<BaseLinkageFamilyGroup>`, whose flows are
// typed to the *base* family, so a harness in the test family could never be attached to it.
// These families are the test-family equivalents, carrying QUIC instances parameterized on
// `TestLinkageFamilyGroup` instead.

// MARK: - Stream linkage family

// MARK: - The test linkage family group

// The test stack uses the framework's own linkages, specialized on this group. Nothing needs to be
// wrapped: a `Base*Linkage<TestLinkageFamilyGroup>` already carries every framework protocol, and
// the test-only protocols are reached through the same linkages.
@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestLinkageFamilyGroup: LinkageFamilyGroup {
    public typealias StreamFamily = TestStreamLinkageFamily
    public typealias DatagramFamily = TestDatagramLinkageFamily
    public typealias MultipathLinkageType = TestDatagramMultipathLinkage

    public static func linkage(
        for quicStream: QUICStreamInstance<TestLinkageFamilyGroup>
    ) -> TestOutboundStreamLinkage {
        .init(base: baseLinkage(forQUICStream: quicStream))
    }

    public static func linkage(
        for quicDatagramFlow: QUICDatagramFlow<TestLinkageFamilyGroup>
    ) -> TestOutboundDatagramLinkage {
        .init(base: baseLinkage(forQUICDatagramFlow: quicDatagramFlow))
    }

    public static func linkage(
        for quicPath: QUICPath<TestLinkageFamilyGroup>
    ) -> TestInboundDatagramLinkage {
        .init(base: baseLinkage(forQUICPath: quicPath))
    }
}

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestStreamLinkageFamily: StreamLinkageFamily {
    public typealias Upper = TestInboundStreamLinkage
    public typealias Lower = TestOutboundStreamLinkage
    public typealias Listener = TestStreamListenerLinkage
    public typealias InboundFlow = TestInboundStreamFlowLinkage
}

// MARK: - Inbound stream linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestInboundStreamLinkage: InboundStreamLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = TestOutboundStreamLinkage

    public enum ProtocolType {
        case base
        case streamUpperHarness(StreamUpperHarness<TestStreamLinkageFamily>)
    }

    public let base: BaseInboundStreamLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(base: BaseInboundStreamLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(harness: StreamUpperHarness<TestStreamLinkageFamily>) {
        self.base = .init()
        self.protocolType = .streamUpperHarness(harness)
        self.harnessReference = harness.reference
    }

    public var reference: ProtocolInstanceReference { harnessReference ?? base.reference }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: TestOutboundStreamLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .streamUpperHarness(let harness):
            var harness = harness
            let overrideUpper = try harness.attachLowerProtocol(lowerProtocol)
            try lowerProtocol.invokeAttachUpperProtocol(
                overrideUpper ?? self,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        default:
            // The base linkage binds its own upper side, so the test linkage has to complete the
            // pairing itself: it attaches the lower protocol, then hands this linkage back up.
            try lowerProtocol.invokeAttachUpperProtocol(
                self,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .streamUpperHarness(let harness): harness.handleConnectedEvent(state: &state, from)
        default: base.handleConnectedEvent(state: &state, from)
        }
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .streamUpperHarness(let harness):
            harness.handleDisconnectedEvent(state: &state, from, error: error)
        default: base.handleDisconnectedEvent(state: &state, from, error: error)
        }
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        switch protocolType {
        case .streamUpperHarness(let harness):
            harness.handleNetworkProtocolEvent(state: &state, from, event: event)
        default: base.handleNetworkProtocolEvent(state: &state, from, event: event)
        }
    }

    public func handleInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        switch protocolType {
        case .streamUpperHarness(let harness):
            harness.handleInboundDataAvailableEvent(state: &state, from)
        default: base.handleInboundDataAvailableEvent(state: &state, from)
        }
    }

    public func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        switch protocolType {
        case .streamUpperHarness(let harness):
            harness.handleOutboundRoomAvailableEvent(state: &state, from)
        default: base.handleOutboundRoomAvailableEvent(state: &state, from)
        }
    }

    public func handleInboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .streamUpperHarness(let harness):
            harness.handleInboundAbortedEvent(state: &state, from, error: error)
        default: base.handleInboundAbortedEvent(state: &state, from, error: error)
        }
    }

    public func handleOutboundAbortedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .streamUpperHarness(let harness):
            harness.handleOutboundAbortedEvent(state: &state, from, error: error)
        default: base.handleOutboundAbortedEvent(state: &state, from, error: error)
        }
    }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Outbound stream linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestOutboundStreamLinkage: OutboundStreamLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = TestInboundStreamLinkage

    public enum ProtocolType {
        case base
        case streamLowerHarness(StreamLowerHarness<TestStreamLinkageFamily>)
    }

    public let base: BaseOutboundStreamLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let localReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.localReference = nil
    }

    public init(base: BaseOutboundStreamLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.localReference = nil
    }

    public init(harness: StreamLowerHarness<TestStreamLinkageFamily>) {
        self.base = .init()
        self.protocolType = .streamLowerHarness(harness)
        self.localReference = harness.reference
    }


    public var reference: ProtocolInstanceReference { localReference ?? base.reference }

    public func protocolIsConnected(state: inout NetworkContext.State) -> Bool {
        switch protocolType {
        case .streamLowerHarness: return reference.isConnected(state: &state)
        default: return base.protocolIsConnected(state: &state)
        }
    }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: TestInboundStreamLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .streamLowerHarness(let harness):
            var harness = harness
            try harness.attachUpperProtocol(
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        default:
            try base.invokeAttachUpperProtocol(
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func receiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        switch protocolType {
        case .streamLowerHarness(let harness):
            var harness = harness
            return try harness.receiveStreamData(
                state: &state,
                from,
                minimumBytes: minimumBytes,
                maximumBytes: maximumBytes
            )
        default:
            return try base.receiveStreamData(
                state: &state,
                from,
                minimumBytes: minimumBytes,
                maximumBytes: maximumBytes
            )
        }
    }

    public func getOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        switch protocolType {
        case .streamLowerHarness(let harness):
            var harness = harness
            return try harness.getOutboundStreamDataRoomAvailable(state: &state, from)
        default:
            return try base.getOutboundStreamDataRoomAvailable(state: &state, from)
        }
    }

    public func sendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        switch protocolType {
        case .streamLowerHarness(let harness):
            var harness = harness
            try harness.sendStreamData(state: &state, from, streamData: streamData)
        default: try base.sendStreamData(state: &state, from, streamData: streamData)
        }
    }

    public func sendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        switch protocolType {
        case .streamLowerHarness:
            // The harness has no early-data path, matching what the framework's own linkage
            // reported for every non-QUIC protocol.
            throw NetworkError.posix(ENOTSUP)
        default: try base.sendEarlyStreamData(state: &state, from, streamData: streamData)
        }
    }

    public func abortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
        switch protocolType {
        case .streamLowerHarness:
            // Not supported by the harness, matching the framework's own linkage.
            throw NetworkError.posix(ENOTSUP)
        default: try base.abortInbound(state: &state, from, error: error)
        }
    }

    public func abortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) throws(NetworkError) {
        switch protocolType {
        case .streamLowerHarness:
            // Not supported by the harness, matching the framework's own linkage.
            throw NetworkError.posix(ENOTSUP)
        default: try base.abortOutbound(state: &state, from, error: error)
        }
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .streamLowerHarness(let harness): harness.connect(state: &state, from)
        default: base.connect(state: &state, from)
        }
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .streamLowerHarness(let harness):
            harness.disconnect(state: &state, from, error: error)
        default: base.disconnect(state: &state, from, error: error)
        }
    }

    public func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        switch protocolType {
        case .streamLowerHarness(let harness):
            var harness = harness
            try harness.detach(state: &state, from)
        default: try base.detach(state: &state, from)
        }
    }

    public func teardown(state: inout NetworkContext.State) {
        switch protocolType {
        case .streamLowerHarness: break
        default: base.teardown(state: &state)
        }
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        switch protocolType {
        case .streamLowerHarness(let harness):
            harness.handleApplicationEvent(state: &state, from, event: event)
        default: base.handleApplicationEvent(state: &state, from, event: event)
        }
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        switch protocolType {
        case .streamLowerHarness(let harness): return harness.getMetadata(state: &state, from)
        default: return base.getMetadata(state: &state, from)
        }
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        switch protocolType {
        case .streamLowerHarness:
            // Held here rather than in `base`, whose linkage is empty; see the datagram
            // equivalent. Falling through would force-unwrap a nil storage.
            return nil
        default:
            return base.getMetrics(
                state: &state,
                from,
                requestedNetworkMetric: requestedNetworkMetric
            )
        }
    }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Inbound stream flow linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestInboundStreamFlowLinkage: InboundStreamFlowLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = TestStreamListenerLinkage
    public typealias DataLinkage = TestOutboundStreamLinkage

    public enum ProtocolType {
        case base
        case newStreamFlowHarness(NewStreamFlowHarness<TestStreamLinkageFamily>)
    }

    public let base: BaseInboundStreamFlowLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(base: BaseInboundStreamFlowLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(harness: NewStreamFlowHarness<TestStreamLinkageFamily>) {
        self.base = .init()
        self.protocolType = .newStreamFlowHarness(harness)
        self.harnessReference = harness.reference
    }

    public var reference: ProtocolInstanceReference { harnessReference ?? base.reference }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: TestStreamListenerLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .newStreamFlowHarness(let harness):
            var harness = harness
            _ = try harness.attachLowerProtocol(lowerProtocol)
            try lowerProtocol.attachInboundFlow(
                self,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        default:
            try lowerProtocol.attachInboundFlow(
                self,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .newStreamFlowHarness(let harness): harness.handleConnectedEvent(state: &state, from)
        default: base.handleConnectedEvent(state: &state, from)
        }
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .newStreamFlowHarness(let harness):
            harness.handleDisconnectedEvent(state: &state, from, error: error)
        default: base.handleDisconnectedEvent(state: &state, from, error: error)
        }
    }

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        switch protocolType {
        case .newStreamFlowHarness(let harness):
            _ = harness.handleNetworkProtocolEvent(state: &state, from, event: event)
        default: base.handleNetworkProtocolEvent(state: &state, from, event: event)
        }
    }

    public func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        switch protocolType {
        case .newStreamFlowHarness(let harness):
            harness.handleNewInboundFlowEvent(
                state: &state,
                from,
                flowReference: flowReference,
                flowMetadata: flowMetadata
            )
        default:
            base.handleNewInboundFlowEvent(
                state: &state,
                from,
                flowReference: flowReference,
                flowMetadata: flowMetadata
            )
        }
    }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Stream listener linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestStreamListenerLinkage: StreamListenerLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = TestInboundStreamFlowLinkage

    public enum ProtocolType {
        case base
    }

    public let base: BaseStreamListenerLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let localReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.localReference = nil
    }

    public init(base: BaseStreamListenerLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.localReference = nil
    }

    public var reference: ProtocolInstanceReference { localReference ?? base.reference }

    // Binds an inbound-flow observer to the listener. Called from the upper linkage so both
    // directions end up bound.
    public func attachInboundFlow(
        _ upperProtocol: TestInboundStreamFlowLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        default:
            try base.invokeAttachUpperProtocol(
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: TestInboundStreamFlowLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try attachInboundFlow(
            upperProtocol,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeAttachUpperProtocolToNewFlow(
        _ upperProtocol: TestInboundStreamLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        let lowerProtocol: TestOutboundStreamLinkage
        switch protocolType {
        default:
            try base.invokeAttachUpperProtocolToNewFlow(
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
            return
        }
        try upperProtocol.invokeAttachLowerProtocol(
            lowerProtocol,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeAttachUpperProtocolToExistingFlow(
        _ upperProtocol: TestInboundStreamLinkage,
        existingFlowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> TestOutboundStreamLinkage {
        switch protocolType {
        default:
            // The wrapped base linkage is specialized on this group, so it already hands back the
            // test family's own linkage -- no re-wrapping needed.
            return try base.invokeAttachUpperProtocolToExistingFlow(
                upperProtocol,
                existingFlowReference: existingFlowReference
            )
        }
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        default: base.connect(state: &state, from)
        }
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        default: base.disconnect(state: &state, from, error: error)
        }
    }

    public func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        switch protocolType {
        default: try base.detach(state: &state, from)
        }
    }

    public func teardown(state: inout NetworkContext.State) {
        switch protocolType {
        default: base.teardown(state: &state)
        }
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        switch protocolType {
        default: base.handleApplicationEvent(state: &state, from, event: event)
        }
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        switch protocolType {
        default: return base.getMetadata(state: &state, from)
        }
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        switch protocolType {
        default:
            return base.getMetrics(
                state: &state,
                from,
                requestedNetworkMetric: requestedNetworkMetric
            )
        }
    }

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - QUIC linkage construction

// QUIC needs to be able to wrap a stream, datagram flow, or path in a linkage knowing only the
// linkage family, so each of these carries the instance directly in its protocol type.

@_spi(TestHarness)
@available(Network 0.1.0, *)
extension TestOutboundStreamLinkage {
}
