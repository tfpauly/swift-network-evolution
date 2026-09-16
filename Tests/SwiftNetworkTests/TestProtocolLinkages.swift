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
@_spi(Essentials) @_spi(ProtocolProvider) @testable import SwiftNetwork
#elseif canImport(Network)
@_spi(Essentials) @_spi(ProtocolProvider) import Network
#endif

// A linkage family defined outside the main package.
//
// This demonstrates the extension point the base linkages are designed for: a client of the
// framework can define its own protocols and wire them into a stack without the framework
// knowing about them. Each `Test*` linkage wraps the matching `Base*` linkage and adds cases
// for the protocols only this module knows about. Anything the enum doesn't name falls through
// to the wrapped base linkage, so all the protocols the framework provides keep working.
//
// The storage subclasses `BaseNetworkProtocolStorage`, so it owns the framework's protocol
// instances as well as the test-only ones.

@available(Network 0.1.0, *)
final class TestNetworkProtocolStorage: BaseNetworkProtocolStorage {

    // Test-only protocol instances. These are held by the storage the same way the base storage
    // holds the framework's instances.
    private var multiplexingInstances = [ObjectIdentifier: TestMultiplexingProtocol]()

    // Harnesses for the test family. The base storage's factories are hard-coded to the base
    // family, so these build the same harnesses against `TestDatagramLinkageFamily`. The
    // instances are held here to keep them alive for the lifetime of the storage.
    private var datagramUpperHarnessesForTest = [DatagramUpperHarness<TestDatagramLinkageFamily>]()
    private var datagramLowerHarnessesForTest = [DatagramLowerHarness<TestDatagramLinkageFamily>]()
    private var newDatagramFlowHarnessesForTest = [NewDatagramFlowHarness<TestDatagramLinkageFamily>]()

    func createTestDatagramUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties
    ) -> DatagramUpperHarness<TestDatagramLinkageFamily> {
        let instance = DatagramUpperHarness<TestDatagramLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context
        )
        datagramUpperHarnessesForTest.append(instance)
        return instance
    }

    /// Creates an upper harness using a context state the caller already holds. The new-inbound-
    /// flow event runs inline with the state held, so registering there has to use this.
    func createTestDatagramUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        state: inout NetworkContext.State
    ) -> DatagramUpperHarness<TestDatagramLinkageFamily> {
        let instance = DatagramUpperHarness<TestDatagramLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context,
            state: &state
        )
        datagramUpperHarnessesForTest.append(instance)
        return instance
    }

    func createTestDatagramLowerHarness(
        identifier: String = ""
    ) -> DatagramLowerHarness<TestDatagramLinkageFamily> {
        let instance = DatagramLowerHarness<TestDatagramLinkageFamily>(
            identifier: identifier,
            context: context
        )
        datagramLowerHarnessesForTest.append(instance)
        return instance
    }

    func createTestNewDatagramFlowHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties
    ) -> NewDatagramFlowHarness<TestDatagramLinkageFamily> {
        let instance = NewDatagramFlowHarness<TestDatagramLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context
        ) { [self] state in
            let inbound = createTestDatagramUpperHarness(
                identifier: "Inbound",
                local: local,
                remote: remote,
                parameters: parameters,
                path: path,
                state: &state
            )
            return (inbound, TestInboundDatagramLinkage(harness: inbound))
        }
        newDatagramFlowHarnessesForTest.append(instance)
        return instance
    }

    func createTestMultiplexingInstance() -> (
        listener: TestDatagramListenerLinkage,
        multipath: TestDatagramMultipathLinkage,
        instance: TestMultiplexingProtocol
    ) {
        let instance = TestMultiplexingProtocol(context: context)
        multiplexingInstances[ObjectIdentifier(instance)] = instance
        return (
            listener: TestDatagramListenerLinkage(multiplexing: instance),
            multipath: TestDatagramMultipathLinkage(multiplexing: instance),
            instance: instance
        )
    }
}

// MARK: - Datagram linkage families

@available(Network 0.1.0, *)
struct TestDatagramLinkageFamily: DatagramLinkageFamily {
    typealias Upper = TestInboundDatagramLinkage
    typealias Lower = TestOutboundDatagramLinkage
    typealias Listener = TestDatagramListenerLinkage
    typealias InboundFlow = TestInboundDatagramFlowLinkage
}

// MARK: - Inbound datagram linkage

@available(Network 0.1.0, *)
struct TestInboundDatagramLinkage: InboundDatagramLinkage, @unchecked Sendable {
    typealias PairedLowerLinkage = TestOutboundDatagramLinkage

    // Protocols this module knows about. `base` is the fall-through for everything the
    // framework provides.
    enum ProtocolType {
        case base
        case datagramUpperHarness(DatagramUpperHarness<TestDatagramLinkageFamily>)
        // A path on the multiplexing protocol: this is what the path hands back from
        // `asUpperLinkage()` so its lower protocol can deliver events to it.
        case multiplexingPath(TestDatagramPath)
    }

    let base: BaseNetworkProtocolStorage.BaseInboundDatagramLinkage
    let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    init(base: BaseNetworkProtocolStorage.BaseInboundDatagramLinkage) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    init(harness: DatagramUpperHarness<TestDatagramLinkageFamily>) {
        self.base = .init()
        self.protocolType = .datagramUpperHarness(harness)
        self.harnessReference = harness.reference
    }

    init(path: TestDatagramPath) {
        self.base = .init()
        self.protocolType = .multiplexingPath(path)
        self.harnessReference = path.reference
    }

    var reference: ProtocolInstanceReference { harnessReference ?? base.reference }

    func invokeAttachLowerProtocol(
        _ lowerProtocol: TestOutboundDatagramLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexingPath(let path):
            // The path's lower is bound when the path is created, so there is nothing more to do.
            _ = path
        case .datagramUpperHarness(let harness):
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

    func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .multiplexingPath(let path):
            var path = path
            path.handleConnectedEvent(state: &state, from)
        case .datagramUpperHarness(let harness): harness.handleConnectedEvent(state: &state, from)
        default: base.handleConnectedEvent(state: &state, from)
        }
    }

    func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .multiplexingPath(let path):
            var path = path
            path.handleDisconnectedEvent(state: &state, from, error: error)
        case .datagramUpperHarness(let harness):
            harness.handleDisconnectedEvent(state: &state, from, error: error)
        default: base.handleDisconnectedEvent(state: &state, from, error: error)
        }
    }

    func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        switch protocolType {
        case .multiplexingPath(let path):
            var path = path
            path.handleNetworkProtocolEvent(state: &state, from, event: event)
        case .datagramUpperHarness(let harness):
            _ = harness.handleNetworkProtocolEvent(state: &state, from, event: event)
        default: base.handleNetworkProtocolEvent(state: &state, from, event: event)
        }
    }

    func handleInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        switch protocolType {
        case .multiplexingPath(let path):
            var path = path
            path.handleInboundDataAvailableEvent(state: &state, from)
        case .datagramUpperHarness(let harness): harness.handleInboundDataAvailableEvent(state: &state, from)
        default: base.handleInboundDataAvailableEvent(state: &state, from)
        }
    }

    func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        switch protocolType {
        case .multiplexingPath(let path):
            var path = path
            path.handleOutboundRoomAvailableEvent(state: &state, from)
        case .datagramUpperHarness(let harness): harness.handleOutboundRoomAvailableEvent(state: &state, from)
        default: base.handleOutboundRoomAvailableEvent(state: &state, from)
        }
    }

    static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Outbound datagram linkage

@available(Network 0.1.0, *)
struct TestOutboundDatagramLinkage: OutboundDatagramLinkage, @unchecked Sendable {
    typealias PairedUpperLinkage = TestInboundDatagramLinkage

    enum ProtocolType {
        case base
        case datagramLowerHarness(DatagramLowerHarness<TestDatagramLinkageFamily>)
        // A flow on the multiplexing protocol: this is what the flow hands back from
        // `asLowerLinkage()` so its upper protocol can talk to it.
        case multiplexedFlow(TestDatagramFlow)
    }

    let base: BaseNetworkProtocolStorage.BaseOutboundDatagramLinkage
    let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    init(base: BaseNetworkProtocolStorage.BaseOutboundDatagramLinkage) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    init(harness: DatagramLowerHarness<TestDatagramLinkageFamily>) {
        self.base = .init()
        self.protocolType = .datagramLowerHarness(harness)
        self.harnessReference = harness.reference
    }

    init(flow: TestDatagramFlow) {
        self.base = .init()
        self.protocolType = .multiplexedFlow(flow)
        self.harnessReference = flow.reference
    }

    var reference: ProtocolInstanceReference {
        harnessReference ?? base.reference
    }

    func protocolIsConnected(state: inout NetworkContext.State) -> Bool {
        switch protocolType {
        case .datagramLowerHarness, .multiplexedFlow: return reference.isConnected(state: &state)
        default: return base.protocolIsConnected(state: &state)
        }
    }

    func invokeAttachUpperProtocol(
        _ upperProtocol: TestInboundDatagramLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexedFlow(let flow):
            // Binding the upper here is what lets the flow accept calls from it: the flow
            // validates every inbound call against `upper.reference`.
            var flow = flow
            try flow.attachUpperProtocol(
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        case .datagramLowerHarness(let harness):
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
                upperProtocol.base,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    func receiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        switch protocolType {
        case .multiplexedFlow(let flow):
            var flow = flow
            return try flow.receiveDatagrams(
                state: &state,
                from,
                maximumDatagramCount: maximumDatagramCount
            )
        case .datagramLowerHarness(let harness):
            var harness = harness
            return try harness.receiveDatagrams(
                state: &state,
                from,
                maximumDatagramCount: maximumDatagramCount
            )
        default:
            return try base.receiveDatagrams(
                state: &state,
                from,
                maximumDatagramCount: maximumDatagramCount
            )
        }
    }

    func getDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        switch protocolType {
        case .multiplexedFlow(let flow):
            var flow = flow
            return try flow.getDatagramsToSend(
                state: &state,
                from,
                maximumDatagramCount: maximumDatagramCount,
                minimumDatagramSize: minimumDatagramSize
            )
        case .datagramLowerHarness(let harness):
            var harness = harness
            return try harness.getDatagramsToSend(
                state: &state,
                from,
                maximumDatagramCount: maximumDatagramCount,
                minimumDatagramSize: minimumDatagramSize
            )
        default:
            return try base.getDatagramsToSend(
                state: &state,
                from,
                maximumDatagramCount: maximumDatagramCount,
                minimumDatagramSize: minimumDatagramSize
            )
        }
    }

    func sendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexedFlow(let flow):
            var flow = flow
            try flow.sendDatagrams(state: &state, from, datagrams: datagrams)
        case .datagramLowerHarness(let harness):
            var harness = harness
            try harness.sendDatagrams(state: &state, from, datagrams: datagrams)
        default: try base.sendDatagrams(state: &state, from, datagrams: datagrams)
        }
    }

    func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .multiplexedFlow(let flow): flow.connect(state: &state, from)
        case .datagramLowerHarness(let harness): harness.connect(state: &state, from)
        default: base.connect(state: &state, from)
        }
    }

    func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .multiplexedFlow(let flow): flow.disconnect(state: &state, from, error: error)
        case .datagramLowerHarness(let harness):
            harness.disconnect(state: &state, from, error: error)
        default: base.disconnect(state: &state, from, error: error)
        }
    }

    func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexedFlow(let flow):
            var flow = flow
            try flow.detach(state: &state, from)
        case .datagramLowerHarness(let harness):
            var harness = harness
            try harness.detach(state: &state, from)
        default: try base.detach(state: &state, from)
        }
    }

    func teardown(state: inout NetworkContext.State) {
        switch protocolType {
        case .datagramLowerHarness, .multiplexedFlow: break
        default: base.teardown(state: &state)
        }
    }

    func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        switch protocolType {
        case .multiplexedFlow(let flow):
            flow.handleApplicationEvent(state: &state, from, event: event)
        case .datagramLowerHarness(let harness):
            harness.handleApplicationEvent(state: &state, from, event: event)
        default: base.handleApplicationEvent(state: &state, from, event: event)
        }
    }

    func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        switch protocolType {
        case .multiplexedFlow(let flow): return flow.getMetadata(state: &state, from)
        case .datagramLowerHarness(let harness): return harness.getMetadata(state: &state, from)
        default: return base.getMetadata(state: &state, from)
        }
    }

    func getMetrics(
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

    static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Inbound datagram flow linkage

@available(Network 0.1.0, *)
struct TestInboundDatagramFlowLinkage: InboundDatagramFlowLinkage, @unchecked Sendable {
    typealias PairedLowerLinkage = TestDatagramListenerLinkage
    typealias DataLinkage = TestOutboundDatagramLinkage

    enum ProtocolType {
        case base
        case newDatagramFlowHarness(NewDatagramFlowHarness<TestDatagramLinkageFamily>)
    }

    let base: BaseNetworkProtocolStorage.BaseInboundDatagramFlowLinkage
    let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    init(base: BaseNetworkProtocolStorage.BaseInboundDatagramFlowLinkage) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    init(harness: NewDatagramFlowHarness<TestDatagramLinkageFamily>) {
        self.base = .init()
        self.protocolType = .newDatagramFlowHarness(harness)
        self.harnessReference = harness.reference
    }

    var reference: ProtocolInstanceReference { harnessReference ?? base.reference }

    func invokeAttachLowerProtocol(
        _ lowerProtocol: TestDatagramListenerLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .newDatagramFlowHarness(let harness):
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

    func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .newDatagramFlowHarness(let harness): harness.handleConnectedEvent(state: &state, from)
        default: base.handleConnectedEvent(state: &state, from)
        }
    }

    func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .newDatagramFlowHarness(let harness):
            harness.handleDisconnectedEvent(state: &state, from, error: error)
        default: base.handleDisconnectedEvent(state: &state, from, error: error)
        }
    }

    func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        switch protocolType {
        case .newDatagramFlowHarness(let harness):
            _ = harness.handleNetworkProtocolEvent(state: &state, from, event: event)
        default: base.handleNetworkProtocolEvent(state: &state, from, event: event)
        }
    }

    func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        switch protocolType {
        case .newDatagramFlowHarness(let harness):
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

    static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Datagram listener linkage

@available(Network 0.1.0, *)
struct TestDatagramListenerLinkage: DatagramListenerLinkage, @unchecked Sendable {
    typealias PairedUpperLinkage = TestInboundDatagramFlowLinkage

    enum ProtocolType {
        case base
        case multiplexing(TestMultiplexingProtocol)
    }

    let base: BaseNetworkProtocolStorage.BaseDatagramListenerLinkage
    let protocolType: ProtocolType
    private let multiplexingReference: ProtocolInstanceReference?

    init() {
        self.base = .init()
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    init(base: BaseNetworkProtocolStorage.BaseDatagramListenerLinkage) {
        self.base = base
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    init(multiplexing instance: TestMultiplexingProtocol) {
        self.base = .init()
        self.protocolType = .multiplexing(instance)
        self.multiplexingReference = instance.reference
    }

    var reference: ProtocolInstanceReference {
        multiplexingReference ?? base.reference
    }

    // Binds an inbound-flow observer to the listener. Called from the upper linkage so both
    // directions end up bound.
    func attachInboundFlow(
        _ upperProtocol: TestInboundDatagramFlowLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexing(let instance):
            var instance = instance
            try instance.attachUpperProtocol(
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        default:
            try base.invokeAttachUpperProtocol(
                upperProtocol.base,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    func protocolIsConnected(state: inout NetworkContext.State) -> Bool {
        switch protocolType {
        case .multiplexing(let instance): return instance.isConnected(state: &state)
        default: return base.protocolIsConnected(state: &state)
        }
    }

    func invokeAttachUpperProtocol(
        _ upperProtocol: TestInboundDatagramFlowLinkage,
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

    func invokeAttachUpperProtocolToNewFlow(
        _ upperProtocol: TestInboundDatagramLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexing(let instance):
            var instance = instance
            let flowLower = try instance.attachUpperProtocolToNewFlow(
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
            try upperProtocol.invokeAttachLowerProtocol(
                flowLower,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        default:
            try base.invokeAttachUpperProtocolToNewFlow(
                upperProtocol.base,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    func invokeAttachUpperProtocolToExistingFlow(
        _ upperProtocol: TestInboundDatagramLinkage,
        existingFlowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> TestOutboundDatagramLinkage {
        switch protocolType {
        case .multiplexing(let instance):
            var instance = instance
            return try instance.attachUpperProtocolToExistingFlow(
                upperProtocol,
                existingFlowReference: existingFlowReference
            )
        default:
            return TestOutboundDatagramLinkage(
                base: try base.invokeAttachUpperProtocolToExistingFlow(
                    upperProtocol.base,
                    existingFlowReference: existingFlowReference
                )
            )
        }
    }

    func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .multiplexing(let instance): instance.connect(state: &state, from)
        default: base.connect(state: &state, from)
        }
    }

    func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .multiplexing(let instance): instance.disconnect(state: &state, from, error: error)
        default: base.disconnect(state: &state, from, error: error)
        }
    }

    func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexing(let instance):
            var instance = instance
            try instance.detach(state: &state, from)
        default: try base.detach(state: &state, from)
        }
    }

    func teardown(state: inout NetworkContext.State) {
        switch protocolType {
        case .multiplexing: break
        default: base.teardown(state: &state)
        }
    }

    func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        switch protocolType {
        case .multiplexing(let instance):
            instance.handleApplicationEvent(state: &state, from, event: event)
        default: base.handleApplicationEvent(state: &state, from, event: event)
        }
    }

    func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        switch protocolType {
        case .multiplexing(let instance): return instance.getMetadata(state: &state, from)
        default: return base.getMetadata(state: &state, from)
        }
    }

    func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        switch protocolType {
        case .multiplexing: return nil
        default:
            return base.getMetrics(
                state: &state,
                from,
                requestedNetworkMetric: requestedNetworkMetric
            )
        }
    }

    static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Datagram multipath linkage

@available(Network 0.1.0, *)
struct TestDatagramMultipathLinkage: DatagramMultipathLinkage, @unchecked Sendable {
    typealias MultipathLowerProtocol = TestOutboundDatagramLinkage

    enum ProtocolType {
        case base
        case multiplexing(TestMultiplexingProtocol)
    }

    let base: BaseNetworkProtocolStorage.BaseDatagramMultipathLinkage
    let protocolType: ProtocolType
    private let multiplexingReference: ProtocolInstanceReference?

    init() {
        self.base = .init()
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    init(base: BaseNetworkProtocolStorage.BaseDatagramMultipathLinkage) {
        self.base = base
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    init(multiplexing instance: TestMultiplexingProtocol) {
        self.base = .init()
        self.protocolType = .multiplexing(instance)
        self.multiplexingReference = instance.reference
    }

    var reference: ProtocolInstanceReference {
        multiplexingReference ?? base.reference
    }

    mutating func invokeAttachLowerProtocolForNewPath(
        _ lowerProtocol: TestOutboundDatagramLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexing(let instance):
            // The handler creates the path and returns the linkage representing it, which is then
            // bound as the lower protocol's upper side so both directions are connected.
            var instance = instance
            let pathUpper = try instance.fromExternal { state throws(NetworkError) in
                try instance.attachLowerProtocolForNewPath(
                    state: &state,
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            }
            try lowerProtocol.invokeAttachUpperProtocol(
                pathUpper,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        default:
            var base = base
            try base.invokeAttachLowerProtocolForNewPath(
                lowerProtocol.base,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}
