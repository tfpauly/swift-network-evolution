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

// A linkage family defined outside the main package.
//
// This demonstrates the extension point the base linkages are designed for: a client of the
// framework can define its own protocols and wire them into a stack without the framework
// knowing about them. Each `Test*` linkage wraps the matching `Base*` linkage and adds cases
// for the protocols only this module knows about. Anything the enum doesn't name falls through
// to the wrapped base linkage, so all the protocols the framework provides keep working.
//
// The storage subclasses `BaseNetworkProtocolStorageParent<TestLinkageFamilyGroup>`, so it owns the framework's protocol
// instances as well as the test-only ones.

@_spi(TestHarness)
@available(Network 0.1.0, *)
public final class TestNetworkProtocolStorage:
    BaseNetworkProtocolStorageParent<TestLinkageFamilyGroup> {

    // A true subclass: every framework protocol is inherited, so this only adds the factories for
    // the test-only protocols -- the harnesses and the test multiplexing protocol.


    // Test-only protocol instances. These are held by the storage the same way the base storage
    // holds the framework's instances.
    private var multiplexingInstances = [ObjectIdentifier: TestMultiplexingProtocol]()


    // Harnesses for the test family. The base storage's factories are hard-coded to the base
    // family, so these build the same harnesses against `TestDatagramLinkageFamily`. The
    // instances are held here to keep them alive for the lifetime of the storage.
    private var datagramUpperHarnessesForTest = [DatagramUpperHarness<TestDatagramLinkageFamily>]()
    private var datagramLowerHarnessesForTest = [DatagramLowerHarness<TestDatagramLinkageFamily>]()
    private var newDatagramFlowHarnessesForTest = [NewDatagramFlowHarness<TestDatagramLinkageFamily>]()

    public func createTestDatagramUpperHarness(
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
    public func createTestDatagramUpperHarness(
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

    public func createTestDatagramLowerHarness(
        identifier: String = ""
    ) -> DatagramLowerHarness<TestDatagramLinkageFamily> {
        let instance = DatagramLowerHarness<TestDatagramLinkageFamily>(
            identifier: identifier,
            context: context
        )
        datagramLowerHarnessesForTest.append(instance)
        return instance
    }

    public func createTestNewDatagramFlowHarness(
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

    public func createTestMultiplexingInstance() -> (
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

    // MARK: - Stream harnesses

    private var streamUpperHarnessesForTest = [StreamUpperHarness<TestStreamLinkageFamily>]()
    private var streamLowerHarnessesForTest = [StreamLowerHarness<TestStreamLinkageFamily>]()
    private var newStreamFlowHarnessesForTest = [NewStreamFlowHarness<TestStreamLinkageFamily>]()

    public func createTestStreamUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties
    ) -> StreamUpperHarness<TestStreamLinkageFamily> {
        let instance = StreamUpperHarness<TestStreamLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context
        )
        streamUpperHarnessesForTest.append(instance)
        return instance
    }

    /// Creates an upper harness using a context state the caller already holds. The new-inbound-
    /// flow event runs inline with the state held, so registering there has to use this.
    public func createTestStreamUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        state: inout NetworkContext.State
    ) -> StreamUpperHarness<TestStreamLinkageFamily> {
        let instance = StreamUpperHarness<TestStreamLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context,
            state: &state
        )
        streamUpperHarnessesForTest.append(instance)
        return instance
    }

    public func createTestStreamLowerHarness(
        identifier: String = ""
    ) -> StreamLowerHarness<TestStreamLinkageFamily> {
        let instance = StreamLowerHarness<TestStreamLinkageFamily>(
            identifier: identifier,
            context: context
        )
        streamLowerHarnessesForTest.append(instance)
        return instance
    }

    public func createTestNewStreamFlowHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties
    ) -> NewStreamFlowHarness<TestStreamLinkageFamily> {
        let instance = NewStreamFlowHarness<TestStreamLinkageFamily>(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            context: context
        ) { [self] state in
            let inbound = createTestStreamUpperHarness(
                identifier: "Inbound",
                local: local,
                remote: remote,
                parameters: parameters,
                path: path,
                state: &state
            )
            return (inbound, TestInboundStreamLinkage(harness: inbound))
        }
        newStreamFlowHarnessesForTest.append(instance)
        return instance
    }


}

// MARK: - Datagram linkage families

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestDatagramLinkageFamily: DatagramLinkageFamily {
    public typealias Upper = TestInboundDatagramLinkage
    public typealias Lower = TestOutboundDatagramLinkage
    public typealias Listener = TestDatagramListenerLinkage
    public typealias InboundFlow = TestInboundDatagramFlowLinkage
}

// MARK: - Inbound datagram linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestInboundDatagramLinkage: InboundDatagramLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = TestOutboundDatagramLinkage

    // Protocols this module knows about. `base` is the fall-through for everything the
    // framework provides.
    public enum ProtocolType {
        case base
        case datagramUpperHarness(DatagramUpperHarness<TestDatagramLinkageFamily>)
        // A path on the multiplexing protocol: this is what the path hands back from
        // `asUpperLinkage()` so its lower protocol can deliver events to it.
        case multiplexingPath(TestDatagramPath)
        // Framework protocols, held by the test storage and typed to the test families so a
        // harness can be their upper. Reached by index, like the base storage does.
    }

    public let base: BaseInboundDatagramLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(base: BaseInboundDatagramLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(harness: DatagramUpperHarness<TestDatagramLinkageFamily>) {
        self.base = .init()
        self.protocolType = .datagramUpperHarness(harness)
        self.harnessReference = harness.reference
    }

    public init(path: TestDatagramPath) {
        self.base = .init()
        self.protocolType = .multiplexingPath(path)
        self.harnessReference = path.reference
    }


    public var reference: ProtocolInstanceReference { harnessReference ?? base.reference }

    public func invokeAttachLowerProtocol(
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
            // Not a test protocol, so hand the whole call to the wrapped base linkage. Both sides
            // are base linkages here, so it completes the pairing itself.
            try base.invokeAttachLowerProtocol(
                lowerProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .multiplexingPath(let path):
            path.handleConnectedEvent(state: &state, from)
        case .datagramUpperHarness(let harness): harness.handleConnectedEvent(state: &state, from)
        default: base.handleConnectedEvent(state: &state, from)
        }
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .multiplexingPath(let path):
            path.handleDisconnectedEvent(state: &state, from, error: error)
        case .datagramUpperHarness(let harness):
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
        case .multiplexingPath(let path):
            var path = path
            path.handleNetworkProtocolEvent(state: &state, from, event: event)
        case .datagramUpperHarness(let harness):
            _ = harness.handleNetworkProtocolEvent(state: &state, from, event: event)
        default: base.handleNetworkProtocolEvent(state: &state, from, event: event)
        }
    }

    public func handleInboundDataAvailableEvent(
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

    public func handleOutboundRoomAvailableEvent(
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

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Outbound datagram linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestOutboundDatagramLinkage: OutboundDatagramLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = TestInboundDatagramLinkage

    public enum ProtocolType {
        case base
        case datagramLowerHarness(DatagramLowerHarness<TestDatagramLinkageFamily>)
        // A flow on the multiplexing protocol: this is what the flow hands back from
        // `asLowerLinkage()` so its upper protocol can talk to it.
        case multiplexedFlow(TestDatagramFlow)
    }

    public let base: BaseOutboundDatagramLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(base: BaseOutboundDatagramLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(harness: DatagramLowerHarness<TestDatagramLinkageFamily>) {
        self.base = .init()
        self.protocolType = .datagramLowerHarness(harness)
        self.harnessReference = harness.reference
    }

    public init(flow: TestDatagramFlow) {
        self.base = .init()
        self.protocolType = .multiplexedFlow(flow)
        self.harnessReference = flow.reference
    }


    public var reference: ProtocolInstanceReference {
        harnessReference ?? base.reference
    }

    public func protocolIsConnected(state: inout NetworkContext.State) -> Bool {
        switch protocolType {
        case .datagramLowerHarness, .multiplexedFlow:
            return reference.isConnected(state: &state)
        default: return base.protocolIsConnected(state: &state)
        }
    }

    public func invokeAttachUpperProtocol(
        _ upperProtocol: TestInboundDatagramLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .multiplexedFlow:
            // `attachUpperProtocolToNewFlow` binds the upper when it creates the flow, so there
            // is nothing more to do here.
            break
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
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func receiveDatagrams(
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

    public func getDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        switch protocolType {
        case .multiplexedFlow(let flow):
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

    public func sendDatagrams(
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

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        switch protocolType {
        case .multiplexedFlow(let flow): flow.connect(state: &state, from)
        case .datagramLowerHarness(let harness): harness.connect(state: &state, from)
        default: base.connect(state: &state, from)
        }
    }

    public func disconnect(
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

    public func detach(
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

    public func teardown(state: inout NetworkContext.State) {
        switch protocolType {
        case .datagramLowerHarness, .multiplexedFlow: break
        default: base.teardown(state: &state)
        }
    }

    public func handleApplicationEvent(
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

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        switch protocolType {
        case .multiplexedFlow(let flow): return flow.getMetadata(state: &state, from)
        case .datagramLowerHarness(let harness): return harness.getMetadata(state: &state, from)
        default: return base.getMetadata(state: &state, from)
        }
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        switch protocolType {
        case .datagramLowerHarness, .multiplexedFlow:
            // These hold their instance here rather than in `base`, whose linkage is empty, so
            // they must not fall through: the base implementation force-unwraps its storage.
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

// MARK: - Inbound datagram flow linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestInboundDatagramFlowLinkage: InboundDatagramFlowLinkage, @unchecked Sendable {
    public typealias PairedLowerLinkage = TestDatagramListenerLinkage
    public typealias DataLinkage = TestOutboundDatagramLinkage

    public enum ProtocolType {
        case base
        case newDatagramFlowHarness(NewDatagramFlowHarness<TestDatagramLinkageFamily>)
    }

    public let base: BaseInboundDatagramFlowLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let harnessReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(base: BaseInboundDatagramFlowLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.harnessReference = nil
    }

    public init(harness: NewDatagramFlowHarness<TestDatagramLinkageFamily>) {
        self.base = .init()
        self.protocolType = .newDatagramFlowHarness(harness)
        self.harnessReference = harness.reference
    }

    public var reference: ProtocolInstanceReference { harnessReference ?? base.reference }

    public func invokeAttachLowerProtocol(
        _ lowerProtocol: TestDatagramListenerLinkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        switch protocolType {
        case .newDatagramFlowHarness(let harness):
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
        case .newDatagramFlowHarness(let harness): harness.handleConnectedEvent(state: &state, from)
        default: base.handleConnectedEvent(state: &state, from)
        }
    }

    public func handleDisconnectedEvent(
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

    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        switch protocolType {
        case .newDatagramFlowHarness(let harness):
            harness.handleNetworkProtocolEvent(state: &state, from, event: event)
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

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Datagram listener linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestDatagramListenerLinkage: DatagramListenerLinkage, @unchecked Sendable {
    public typealias PairedUpperLinkage = TestInboundDatagramFlowLinkage

    public enum ProtocolType {
        case base
        case multiplexing(TestMultiplexingProtocol)
    }

    public let base: BaseDatagramListenerLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let multiplexingReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    public init(base: BaseDatagramListenerLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    public init(multiplexing instance: TestMultiplexingProtocol) {
        self.base = .init()
        self.protocolType = .multiplexing(instance)
        self.multiplexingReference = instance.reference
    }

    public var reference: ProtocolInstanceReference {
        multiplexingReference ?? base.reference
    }

    // Binds an inbound-flow observer to the listener. Called from the upper linkage so both
    // directions end up bound.
    public func attachInboundFlow(
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
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func protocolIsConnected(state: inout NetworkContext.State) -> Bool {
        switch protocolType {
        case .multiplexing(let instance): return instance.isConnected(state: &state)
        default: return base.protocolIsConnected(state: &state)
        }
    }

    public func invokeAttachUpperProtocol(
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

    public func invokeAttachUpperProtocolToNewFlow(
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
                upperProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }
    }

    public func invokeAttachUpperProtocolToExistingFlow(
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
        case .multiplexing(let instance): instance.connect(state: &state, from)
        default: base.connect(state: &state, from)
        }
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        switch protocolType {
        case .multiplexing(let instance): instance.disconnect(state: &state, from, error: error)
        default: base.disconnect(state: &state, from, error: error)
        }
    }

    public func detach(
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

    public func teardown(state: inout NetworkContext.State) {
        switch protocolType {
        case .multiplexing: break
        default: base.teardown(state: &state)
        }
    }

    public func handleApplicationEvent(
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

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        switch protocolType {
        case .multiplexing(let instance): return instance.getMetadata(state: &state, from)
        default: return base.getMetadata(state: &state, from)
        }
    }

    public func getMetrics(
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

    public static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
        lhs.reference == rhs.reference
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}

// MARK: - Datagram multipath linkage

@_spi(TestHarness)
@available(Network 0.1.0, *)
public struct TestDatagramMultipathLinkage: DatagramMultipathLinkage, @unchecked Sendable {
    public typealias MultipathLowerProtocol = TestOutboundDatagramLinkage

    public enum ProtocolType {
        case base
        case multiplexing(TestMultiplexingProtocol)
    }

    public let base: BaseDatagramMultipathLinkage<TestLinkageFamilyGroup>
    public let protocolType: ProtocolType
    private let multiplexingReference: ProtocolInstanceReference?

    public init() {
        self.base = .init()
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    public init(base: BaseDatagramMultipathLinkage<TestLinkageFamilyGroup>) {
        self.base = base
        self.protocolType = .base
        self.multiplexingReference = nil
    }

    public init(multiplexing instance: TestMultiplexingProtocol) {
        self.base = .init()
        self.protocolType = .multiplexing(instance)
        self.multiplexingReference = instance.reference
    }

    public var reference: ProtocolInstanceReference {
        multiplexingReference ?? base.reference
    }

    public mutating func invokeAttachLowerProtocolForNewPath(
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
            try base.invokeAttachLowerProtocolForNewPath(
                lowerProtocol,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
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

// MARK: - Harness factories

// These mirror the factories the framework's storage used to provide, so call sites read the same
// as before the harnesses moved out of the package. Each returns the instance together with the
// linkage that reaches it, and takes `context:` for source compatibility even though the storage
// already holds the context it was built with.
@_spi(TestHarness)
@available(Network 0.1.0, *)
extension TestNetworkProtocolStorage {

    public func createDatagramUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) -> (DatagramUpperHarness<TestDatagramLinkageFamily>, TestInboundDatagramLinkage) {
        let instance = createTestDatagramUpperHarness(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path
        )
        return (instance, TestInboundDatagramLinkage(harness: instance))
    }

    public func createDatagramUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext,
        state: inout NetworkContext.State
    ) -> (DatagramUpperHarness<TestDatagramLinkageFamily>, TestInboundDatagramLinkage) {
        let instance = createTestDatagramUpperHarness(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path,
            state: &state
        )
        return (instance, TestInboundDatagramLinkage(harness: instance))
    }

    public func createDatagramLowerHarness(
        identifier: String = "",
        context: NetworkContext
    ) -> (DatagramLowerHarness<TestDatagramLinkageFamily>, TestOutboundDatagramLinkage) {
        let instance = createTestDatagramLowerHarness(identifier: identifier)
        return (instance, TestOutboundDatagramLinkage(harness: instance))
    }

    public func createNewDatagramFlowHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) -> (NewDatagramFlowHarness<TestDatagramLinkageFamily>, TestInboundDatagramFlowLinkage) {
        let instance = createTestNewDatagramFlowHarness(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path
        )
        return (instance, TestInboundDatagramFlowLinkage(harness: instance))
    }

    public func createStreamUpperHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) -> (StreamUpperHarness<TestStreamLinkageFamily>, TestInboundStreamLinkage) {
        let instance = createTestStreamUpperHarness(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path
        )
        return (instance, TestInboundStreamLinkage(harness: instance))
    }

    public func createStreamLowerHarness(
        identifier: String = "",
        context: NetworkContext
    ) -> (StreamLowerHarness<TestStreamLinkageFamily>, TestOutboundStreamLinkage) {
        let instance = createTestStreamLowerHarness(identifier: identifier)
        return (instance, TestOutboundStreamLinkage(harness: instance))
    }

    public func createNewStreamFlowHarness(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) -> (NewStreamFlowHarness<TestStreamLinkageFamily>, TestInboundStreamFlowLinkage) {
        let instance = createTestNewStreamFlowHarness(
            identifier: identifier,
            local: local,
            remote: remote,
            parameters: parameters,
            path: path
        )
        return (instance, TestInboundStreamFlowLinkage(harness: instance))
    }
}

