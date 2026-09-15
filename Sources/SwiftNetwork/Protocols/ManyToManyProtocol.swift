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

// MARK: - Many-to-Many Protocol Adoption

/// A protocol that handles multiple flows over multiple paths.
///
/// Many-to-many protocols have associated types for flows that connect to upper protocols
/// and paths that connect to lower protocols.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ManyToManyProtocolHandler: ListenerHandler, LoggableProtocol where Flow: MultiplexedFlow {
    associatedtype Path: MultiplexingPath

    var inboundFlowLinkage: UpperProtocol { get set }

    var multiplexedFlows: [MultiplexedFlowIdentifier: Flow] { get set }
    var multiplexingPaths: [MultiplexingPathIdentifier: Path] { get set }

    // MARK: Connection-wide calls to implement
    func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    /// Requests that this protocol initiate its handshake, if any.
    ///
    /// Thread `state` into any calls made to other protocols so that the state is never
    /// re-derived from the context.
    func connect(state: inout NetworkContext.State)
    func disconnect(state: inout NetworkContext.State, error: NetworkError?)
    func teardown(state: inout NetworkContext.State)
    mutating func teardownIfPossible(state: inout NetworkContext.State)
    func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ event: ApplicationEvent
    ) -> HandleNetworkEventResult

    // MARK: Per-flow calls to implement
    func setup(
        flow: MultiplexedFlowIdentifier,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)
    func connect(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier)
    func disconnect(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier, error: NetworkError?)
    func teardown(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier)
    func handleApplicationEvent(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier, event: ApplicationEvent) -> HandleNetworkEventResult
    func getMetadata<P>(flow: MultiplexedFlowIdentifier) -> ProtocolMetadata<P>? where P: NetworkProtocol
    func updateDataTransferSnapshot(flow: MultiplexedFlowIdentifier, _ snapshot: inout DataTransferSnapshot)
    var protocolEstablishmentReport: ProtocolEstablishmentReport? { get }

    // MARK: Per-path events to implement
    func handleConnectedEvent(state: inout NetworkContext.State, path: MultiplexingPathIdentifier)
    func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        path: MultiplexingPathIdentifier,
        error: NetworkError?
    )
    func handlePathChanged(
        state: inout NetworkContext.State,
        path pathID: MultiplexingPathIdentifier,
        event: MultiplexingPathEvent,
        isPrimary: Bool
    )
    func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        path: MultiplexingPathIdentifier,
        event: NetworkProtocolEvent
    ) -> HandleNetworkEventResult

    mutating func attachLowerProtocolForNewPath(
        state: inout NetworkContext.State,
        _ lowerProtocol: Path.LowerProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Path.LowerProtocol.PairedUpperLinkage

    // MARK: Helper functions implemented by inheriting either HomogeneousManyToManyProtocolHandler or HeterogeneousManyToManyProtocolHandler
    mutating func performInitialSetupIfNeeded(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)
    func validate(
        inbound inboundProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError)
}

/// Declares that a many-to-many protocol supports only a single type of flow.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol HomogeneousManyToManyProtocolHandler: ManyToManyProtocolHandler {
}

/// Allows a many-to-many protocol to support a secondary type of flow, for example, both stream flows and datagram flows.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol HeterogeneousManyToManyProtocolHandler: HeterogeneousListenerHandler, ManyToManyProtocolHandler where SecondaryFlow: MultiplexedFlow {
    var multiplexedSecondaryFlows: [MultiplexedFlowIdentifier: SecondaryFlow] { get set }
    var secondaryInboundFlowLinkage: SecondaryUpperProtocol { get set }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ManyToManyDatapathProtocol: ManyToManyProtocolHandler
where Flow.UpperProtocol: InboundDataLinkage, Path.LowerProtocol: OutboundDataLinkage {
    func handleInboundDataAvailableEvent(state: inout NetworkContext.State, path: MultiplexingPathIdentifier)
    func handleOutboundRoomAvailableEvent(state: inout NetworkContext.State, path: MultiplexingPathIdentifier)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ManyToManyApplicationStreamProtocol: ManyToManyDatapathProtocol {
    func serviceStreamDataToSend(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ManyToManyApplicationDatagramProtocol: ManyToManyDatapathProtocol {
    func serviceDatagramsToSend(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ManyToManyOutboundDatagramProtocol: ManyToManyDatapathProtocol
where Path.LowerProtocol: OutboundDatagramLinkage {
    func serviceReceivedDatagrams(state: inout NetworkContext.State, path: MultiplexingPathIdentifier)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
@frozen public enum MultiplexedFlowIdentifier: Hashable, CustomDebugStringConvertible {
    case allFlows
    case outboundFlow(index: Int)
    case inboundFlow(index: Int)

    init(_ reference: ProtocolInstanceReference) {
        guard let index = reference.protocolEventStateIndex else {
            self = .allFlows
            return
        }
        self = .outboundFlow(index: index.rawValue)
    }

    init(inboundReference: ProtocolInstanceReference) {
        // Identify the flow by its own event state, not its parent's: every inbound flow on a
        // connection shares that parent, so allowing the parent index here would collapse them
        // all onto one identifier.
        guard let index = inboundReference.protocolEventStateIndex(allowParent: false) else {
            self = .allFlows
            return
        }
        self = .inboundFlow(index: index.rawValue)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawHashKey)
    }

    private var rawHashKey: UInt64 {
        // Use the bottom two bits as a discriminator for the different cases.
        switch self {
        case .allFlows:
            return 0
        case .outboundFlow(let index):
            return UInt64(bitPattern: Int64(index)) << 2 | 0b01
        case .inboundFlow(let index):
            return UInt64(bitPattern: Int64(index)) << 2 | 0b10
        }
    }

    public func _rawHashValue(seed: Int) -> Int {
        self.rawHashKey._rawHashValue(seed: seed)
    }

    public var debugDescription: String {
        switch self {
        case .allFlows: return "All Flows"
        #if !NETWORK_EMBEDDED
        case .outboundFlow(let index): return index.description
        case .inboundFlow(let index): return index.description
        #else
        case .outboundFlow: return "Outbound Flow"
        case .inboundFlow: return "Inbound Flow"
        #endif
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol MultiplexedFlow: LowerProtocolHandler, LoggableProtocol {
    associatedtype ParentProtocol: ManyToManyProtocolHandler
    var upper: UpperProtocol { get set }
    var parentProtocol: ParentProtocol { get set }
    var identifier: MultiplexedFlowIdentifier { get }
    init(parent: ParentProtocol, inbound: Bool)
    /// Creates a flow using a context state the caller already holds.
    ///
    /// Prefer this over `init(parent:inbound:)` anywhere the state is already in scope, so
    /// registering the flow's reference doesn't re-derive it from the context.
    init(parent: ParentProtocol, inbound: Bool, state: inout NetworkContext.State)
    var upperReceiveQueue: FrameArray { get set }
    var upperSendQueue: FrameArray { get set }
    func asLowerLinkage() -> UpperProtocol.PairedLowerLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol MultiplexedDatapathFlow<UpperProtocol>: MultiplexedFlow
where UpperProtocol: InboundDataLinkage, ParentProtocol: ManyToManyDatapathProtocol {}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public typealias MultiplexingPathIdentifier = Int
@available(Network 0.1.0, *)
extension MultiplexingPathIdentifier {
    static var none: Self {
        0
    }

    init() {
        self = Int.random(in: 1...Int.max)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
@frozen public enum MultiplexingPathEvent: CustomStringConvertible {
    case available
    case unavailable
    case established

    public var description: String {
        switch self {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .established: return "established"
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol MultiplexingPath: UpperProtocolHandler {
    associatedtype ParentProtocol: ManyToManyProtocolHandler
    var lower: LowerProtocol { get set }
    var parentProtocol: ParentProtocol { get }
    var identifier: MultiplexingPathIdentifier { get }
    init(state: inout NetworkContext.State, parent: ParentProtocol)
    var pathIsPrimary: Bool { get set }
    var pathHasMigrationInfo: Bool { get set }
    func asUpperLinkage() -> LowerProtocol.PairedUpperLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol MultiplexingDatapathPath<LowerProtocol>: MultiplexingPath
where LowerProtocol: OutboundDataLinkage, ParentProtocol: ManyToManyDatapathProtocol {}

// MARK: Implementations

@available(Network 0.1.0, *)
extension ManyToManyProtocolHandler {
    // Default implementations, to be overridden as necessary
    public func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {}

    public func teardown(state: inout NetworkContext.State) {}

    public func connect(state: inout NetworkContext.State) {}

    public func disconnect(state: inout NetworkContext.State, error: NetworkError?) {}

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ event: ApplicationEvent
    ) -> HandleNetworkEventResult { .unconsumed }

    public func setup(
        flow: MultiplexedFlowIdentifier,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {}

    public func connect(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier) {
        deliverConnectedEvent(state: &state, flow: flow)
    }

    public func disconnect(
        state: inout NetworkContext.State,
        flow: MultiplexedFlowIdentifier,
        error: NetworkError?
    ) {}
    public func teardown(state: inout NetworkContext.State, flow: MultiplexedFlowIdentifier) {}
    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        flow: MultiplexedFlowIdentifier,
        event: ApplicationEvent
    ) -> HandleNetworkEventResult { .unconsumed }

    public func getMetadata<P>(flow: MultiplexedFlowIdentifier) -> ProtocolMetadata<P>? where P: NetworkProtocol {
        nil
    }

    public func getMetadata<P>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? where P: NetworkProtocol {
        getMetadata(flow: .allFlows)
    }

    public func updateDataTransferSnapshot(flow: MultiplexedFlowIdentifier, _ snapshot: inout DataTransferSnapshot) {}
    public var protocolEstablishmentReport: ProtocolEstablishmentReport? { nil }

    public func getMetrics(
        flow: MultiplexedFlowIdentifier,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        switch requestedNetworkMetric {
        case .protocolEstablishmentReports:
            guard let report = protocolEstablishmentReport else { return nil }
            return .protocolEstablishmentReports([report])
        case .dataTransferSnapshot:
            var snapshot = DataTransferSnapshot()
            updateDataTransferSnapshot(flow: flow, &snapshot)
            return .dataTransferSnapshot(snapshot)
        }
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        getMetrics(flow: .allFlows, requestedNetworkMetric: requestedNetworkMetric)
    }

    public func handleInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        path: MultiplexingPathIdentifier
    ) {}
    public func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        path: MultiplexingPathIdentifier
    ) {}

    public func handleConnectedEvent(state: inout NetworkContext.State, path: MultiplexingPathIdentifier) {}
    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        path: MultiplexingPathIdentifier,
        error: NetworkError?
    ) {}
    public func handlePathChanged(
        state: inout NetworkContext.State,
        path pathID: MultiplexingPathIdentifier,
        event: MultiplexingPathEvent,
        isPrimary: Bool
    ) {}
    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        path: MultiplexingPathIdentifier,
        event: NetworkProtocolEvent
    ) -> HandleNetworkEventResult { .unconsumed }
}

@available(Network 0.1.0, *)
extension ManyToManyProtocolHandler {
    public mutating func attachLowerProtocolForNewPath(
        state: inout NetworkContext.State,
        _ lowerProtocol: Path.LowerProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Path.LowerProtocol.PairedUpperLinkage
    where Path.ParentProtocol == Self {
        var newPath = Path(state: &state, parent: self)
        _ = try newPath.attachLowerProtocol(lowerProtocol)
        let isFirstPath = multiplexingPaths.isEmpty
        if isFirstPath { newPath.pathIsPrimary = true }
        multiplexingPaths[newPath.identifier] = newPath
        if !isFirstPath {
            handlePathChanged(
                state: &state,
                path: newPath.identifier,
                event: .available,
                isPrimary: newPath.pathIsPrimary
            )
        }
        return newPath.asUpperLinkage()
    }

    fileprivate func connectInternal(state: inout NetworkContext.State) {
        if somePathIsConnected(state: &state) {
            if canCallConnect(state: &state, requested: true) {
                connect(state: &state)
            }
        } else {
            connectRequested(state: &state)
            for path in multiplexingPaths.values {
                path.invokeConnect(state: &state)
            }
        }
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        do { try validate(inbound: from, #function) } catch { return }
        connectInternal(state: &state)
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(inbound: from, #function) } catch { return }
        if canCallDisconnect(state: &state) {
            disconnect(state: &state, error: error)
        }
    }

    public func flow(for flowID: MultiplexedFlowIdentifier) -> Flow? {
        multiplexedFlows[flowID]
    }

    public var someFlow: Flow? {
        multiplexedFlows.first?.value
    }

    public var someFlowIdentifier: MultiplexedFlowIdentifier? {
        multiplexedFlows.first?.value.identifier
    }

    public func findFlow(where closure: (_ flow: Flow) -> Bool) -> MultiplexedFlowIdentifier? {
        var returnFlowID: MultiplexedFlowIdentifier?
        for (flowID, flow) in multiplexedFlows {
            if closure(flow) {
                returnFlowID = flowID
                break
            }
        }
        return returnFlowID
    }

    public func allFlowIdentifiers(_ closure: (MultiplexedFlowIdentifier) -> Void) {
        multiplexedFlows.keys.forEach(closure)
    }

    public func applyToAllFlows(_ closure: (Flow) -> Void) {
        multiplexedFlows.values.forEach(closure)
    }

    public func path(for pathID: MultiplexingPathIdentifier) -> Path? {
        multiplexingPaths[pathID]
    }

    public var somePath: Path? {
        multiplexingPaths.first?.value
    }

    public var somePathIdentifier: MultiplexingPathIdentifier? {
        multiplexingPaths.first?.value.identifier
    }

    public func allPathIdentifiers(_ closure: (MultiplexingPathIdentifier) -> Void) {
        multiplexingPaths.keys.forEach(closure)
    }

    public func applyToAllPaths(_ closure: (Path) -> Void) {
        multiplexingPaths.values.forEach(closure)
    }

    public func somePathIsConnected(state: inout NetworkContext.State) -> Bool {
        for path in multiplexingPaths.values {
            if path.lower.protocolIsConnected(state: &state) {
                return true
            }
        }
        return false
    }

    fileprivate mutating func resetPrimaryPath(newPrimary: MultiplexingPathIdentifier) {
        allPathIdentifiers { pathIdentifier in
            if pathIdentifier == newPrimary {
                multiplexingPaths[pathIdentifier]?.pathIsPrimary = true
            } else {
                multiplexingPaths[pathIdentifier]?.pathIsPrimary = false
            }
        }
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        // Don't validate upper, can pass through
        if self.handleApplicationEvent(state: &state, event) == .consumed { return }
        applyToAllPaths { path in
            path.lower.invokeApplicationEvent(state: &state, from, event: event)
        }
    }
}

@available(Network 0.1.0, *)
extension HomogeneousManyToManyProtocolHandler {

    public mutating func performInitialSetupIfNeeded(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard hasNoUpperLinkages else {
            // Already set up
            return
        }

        #if !NETWORK_EMBEDDED
        if let parameters, let options = getOptions(from: parameters, for: .allFlows) {
            self.log.logPrefix = options.logIDString ?? ""
        }
        #endif

        try self.setup(remote: remote, local: local, parameters: parameters, path: path)
    }

    public mutating func attachUpperProtocol(
        _ upperProtocol: UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard inboundFlowLinkage.isDetached else {
            throw NetworkError.posix(EALREADY)
        }

        try performInitialSetupIfNeeded(remote: remote, local: local, parameters: parameters, path: path)

        self.inboundFlowLinkage = upperProtocol
    }

    public mutating func attachUpperProtocolToNewFlow(
        _ upperProtocol: Flow.UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Flow.UpperProtocol.PairedLowerLinkage where Flow.ParentProtocol == Self {
        let flowID = MultiplexedFlowIdentifier(upperProtocol.reference)
        let existingFlow = flow(for: flowID)
        guard existingFlow == nil else {
            throw NetworkError.posix(EALREADY)
        }

        try performInitialSetupIfNeeded(remote: remote, local: local, parameters: parameters, path: path)

        var newFlow = Flow(parent: self, inbound: false)
        newFlow.log.logPrefix = self.log.logPrefix
        multiplexedFlows[flowID] = newFlow

        return newFlow.asLowerLinkage()
    }

    public mutating func attachUpperProtocolToExistingFlow(
        _ upperProtocol: Flow.UpperProtocol,
        existingFlowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> Flow.UpperProtocol.PairedLowerLinkage {
        let flowID = MultiplexedFlowIdentifier(inboundReference: existingFlowReference)
        guard var existingFlow = flow(for: flowID) else {
            throw NetworkError.posix(ENOENT)
        }
        existingFlow.upper = upperProtocol
        return existingFlow.asLowerLinkage()
    }

    public func validate(
        inbound inboundProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard inboundProtocol == inboundFlowLinkage.reference else {
            Logger.proto.fault("Received \'\(label)\' from incorrect inbound flow protocol")
            throw ProtocolInstanceError.invalidNewFlowLinkage
        }
        #endif
    }

    fileprivate var hasNoUpperLinkages: Bool {
        multiplexedFlows.isEmpty && inboundFlowLinkage.isDetached
    }

    public mutating func teardownIfPossible(state: inout NetworkContext.State) {
        guard hasNoUpperLinkages else {
            // Still has some flow
            return
        }
        teardown(state: &state)
        applyToAllPaths { $0.invokeDetach(state: &state) }
        multiplexingPaths.removeAll()
    }

    public mutating func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        do { try validate(inbound: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        inboundFlowLinkage = .init()
        teardownIfPossible(state: &state)
    }

    #if !NETWORK_EMBEDDED
    public func getOptions<T>(from parameters: Parameters, for flowID: MultiplexedFlowIdentifier) -> ProtocolOptions<T>?
    {
        if case .allFlows = flowID {
            if let options: ProtocolOptions<T> = parameters.protocolOptions(for: reference) {
                return options
            }
            if let someFlow = someFlow {
                return parameters.protocolOptions(for: someFlow.reference)
            }
            return nil
        }
        if let flow = flow(for: flowID) {
            if let options: ProtocolOptions<T> = parameters.protocolOptions(for: flow.reference) {
                return options
            }
        }
        return parameters.protocolOptions(for: reference)
    }
    public func getOptions(
        from parameters: Parameters,
        for flowID: MultiplexedFlowIdentifier
    ) -> AbstractProtocolOptions? {
        if case .allFlows = flowID {
            if let options = parameters.protocolOptions(for: reference) {
                return options
            }
            if let someFlow = someFlow {
                return parameters.protocolOptions(for: someFlow.reference)
            }
            return nil
        }
        if let flow = flow(for: flowID) {
            if let options = parameters.protocolOptions(for: flow.reference) {
                return options
            }
        }
        return parameters.protocolOptions(for: reference)
    }
    #endif
}

@available(Network 0.1.0, *)
extension HeterogeneousManyToManyProtocolHandler {
    fileprivate var hasNoUpperLinkages: Bool {
        multiplexedFlows.isEmpty && multiplexedSecondaryFlows.isEmpty && inboundFlowLinkage.isDetached
    }

    public mutating func teardownIfPossible(state: inout NetworkContext.State) {
        guard hasNoUpperLinkages else {
            // Still has some flow
            return
        }
        teardown(state: &state)
        applyToAllPaths { $0.invokeDetach(state: &state) }
        multiplexingPaths.removeAll()
    }

    public mutating func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        do { try validate(inbound: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        inboundFlowLinkage = .init()
        teardownIfPossible(state: &state)
    }

    public func validate(
        inbound inboundProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard
            inboundProtocol == inboundFlowLinkage.reference || inboundProtocol == secondaryInboundFlowLinkage.reference
        else {
            Logger.proto.fault("Received \'\(label)\' from incorrect inbound flow protocol")
            throw ProtocolInstanceError.invalidNewFlowLinkage
        }
        #endif
    }
}

@available(Network 0.1.0, *)
extension HeterogeneousManyToManyProtocolHandler {
    public mutating func performInitialSetupIfNeeded(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard hasNoUpperLinkages else {
            // Already set up
            return
        }

        #if !NETWORK_EMBEDDED
        if let parameters, let options = getOptions(from: parameters, for: .allFlows) {
            self.log.logPrefix = options.logIDString ?? ""
        }
        #endif

        try self.setup(remote: remote, local: local, parameters: parameters, path: path)
    }

    public mutating func attachUpperProtocol(
        _ upperProtocol: UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard inboundFlowLinkage.isDetached else {
            throw NetworkError.posix(EALREADY)
        }

        try performInitialSetupIfNeeded(remote: remote, local: local, parameters: parameters, path: path)

        self.inboundFlowLinkage = upperProtocol
    }

    public mutating func attachUpperProtocol(
        _ upperProtocol: SecondaryUpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard inboundFlowLinkage.isDetached else {
            throw NetworkError.posix(EALREADY)
        }

        try performInitialSetupIfNeeded(remote: remote, local: local, parameters: parameters, path: path)

        self.secondaryInboundFlowLinkage = upperProtocol
    }

    public mutating func attachUpperProtocolToNewFlow(
        _ upperProtocol: Flow.UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Flow.UpperProtocol.PairedLowerLinkage where Flow.ParentProtocol == Self {
        let flowID = MultiplexedFlowIdentifier(upperProtocol.reference)
        let existingFlow = flow(for: flowID)
        guard existingFlow == nil else {
            throw NetworkError.posix(EALREADY)
        }

        try performInitialSetupIfNeeded(remote: remote, local: local, parameters: parameters, path: path)

        var newFlow = Flow(parent: self, inbound: false)
        newFlow.log.logPrefix = self.log.logPrefix
        multiplexedFlows[flowID] = newFlow

        return newFlow.asLowerLinkage()
    }

    public mutating func attachUpperProtocolToNewFlow(
        _ upperProtocol: SecondaryFlow.UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> SecondaryFlow.UpperProtocol.PairedLowerLinkage where SecondaryFlow.ParentProtocol == Self {
        let flowID = MultiplexedFlowIdentifier(upperProtocol.reference)
        let existingFlow = secondaryFlow(for: flowID)
        guard existingFlow == nil else {
            throw NetworkError.posix(EALREADY)
        }

        try performInitialSetupIfNeeded(remote: remote, local: local, parameters: parameters, path: path)

        var newFlow = SecondaryFlow(parent: self, inbound: false)
        newFlow.log.logPrefix = self.log.logPrefix
        multiplexedSecondaryFlows[flowID] = newFlow

        return newFlow.asLowerLinkage()
    }

    public mutating func attachUpperProtocolToExistingFlow(
        _ upperProtocol: Flow.UpperProtocol,
        existingFlowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> Flow.UpperProtocol.PairedLowerLinkage {
        let flowID = MultiplexedFlowIdentifier(inboundReference: existingFlowReference)
        guard var existingFlow = flow(for: flowID) else {
            throw NetworkError.posix(ENOENT)
        }
        existingFlow.upper = upperProtocol
        return existingFlow.asLowerLinkage()
    }

    public mutating func attachUpperProtocolToExistingFlow(
        _ upperProtocol: SecondaryFlow.UpperProtocol,
        existingFlowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> SecondaryFlow.UpperProtocol.PairedLowerLinkage {
        let flowID = MultiplexedFlowIdentifier(inboundReference: existingFlowReference)
        guard var existingFlow = secondaryFlow(for: flowID) else {
            throw NetworkError.posix(ENOENT)
        }
        existingFlow.upper = upperProtocol
        return existingFlow.asLowerLinkage()
    }

    public mutating func addInboundSecondaryFlow(
        state: inout NetworkContext.State
    ) throws(NetworkError) -> MultiplexedFlowIdentifier
    where
        SecondaryFlow.ParentProtocol == Self,
        SecondaryUpperProtocol.DataLinkage.PairedUpperLinkage == SecondaryFlow.UpperProtocol,
        SecondaryUpperProtocol.DataLinkage == SecondaryFlow.UpperProtocol.PairedLowerLinkage
    {

        let newFlow = SecondaryFlow(parent: self, inbound: true, state: &state)
        multiplexedSecondaryFlows[newFlow.identifier] = newFlow
        deliverNewInboundFlowEvent(state: &state, newFlow.reference, flowMetadata: nil)

        return newFlow.identifier
    }

    public func deliverNewInboundSecondaryFlowEvent(
        state: inout NetworkContext.State,
        _ flowReference: ProtocolInstanceReference
    ) {
        secondaryInboundFlowLinkage.deliverNewInboundFlowEvent(
            state: &state,
            reference,
            flowReference: flowReference,
            flowMetadata: nil
        )
    }

    public func secondaryFlow(for flowID: MultiplexedFlowIdentifier) -> SecondaryFlow? {
        multiplexedSecondaryFlows[flowID]
    }

    public var someSecondaryFlow: SecondaryFlow? {
        multiplexedSecondaryFlows.first?.value
    }

    public var someSecondaryFlowIdentifier: MultiplexedFlowIdentifier? {
        multiplexedSecondaryFlows.first?.value.identifier
    }

    public func findSecondaryFlow(where closure: (_ flow: SecondaryFlow) -> Bool) -> MultiplexedFlowIdentifier? {
        var returnFlowID: MultiplexedFlowIdentifier?
        for (flowID, flow) in multiplexedSecondaryFlows {
            if closure(flow) {
                returnFlowID = flowID
                break
            }
        }
        return returnFlowID
    }

    public func allSecondaryFlowIdentifiers(_ closure: (MultiplexedFlowIdentifier) -> Void) {
        multiplexedSecondaryFlows.keys.forEach(closure)
    }

    public func applyToAllSecondaryFlows(_ closure: (SecondaryFlow) -> Void) {
        multiplexedSecondaryFlows.values.forEach(closure)
    }

    #if !NETWORK_NO_SWIFT_QUIC
    public func quicOptions(
        from parameters: Parameters,
        for flowID: MultiplexedFlowIdentifier
    ) -> ProtocolOptions<QUICProtocol>? {
        if case .allFlows = flowID {
            if let options = parameters.quicOptions(for: reference) {
                return options
            }
            if let someFlow = someFlow {
                return parameters.quicOptions(for: someFlow.reference)
            }
            if let someFlow = someSecondaryFlow {
                return parameters.quicOptions(for: someFlow.reference)
            }
            return nil
        }
        if let flow = flow(for: flowID) {
            if let options = parameters.quicOptions(for: flow.reference) {
                return options
            }
        }
        if let flow = secondaryFlow(for: flowID) {
            if let options = parameters.quicOptions(for: flow.reference) {
                return options
            }
        }
        return parameters.quicOptions(for: reference)
    }
    #endif

    #if !NETWORK_EMBEDDED
    public func getOptions<T>(from parameters: Parameters, for flowID: MultiplexedFlowIdentifier) -> ProtocolOptions<T>?
    {
        if case .allFlows = flowID {
            if let options: ProtocolOptions<T> = parameters.protocolOptions(for: reference) {
                return options
            }
            if let someFlow = someFlow {
                return parameters.protocolOptions(for: someFlow.reference)
            }
            if let someFlow = someSecondaryFlow {
                return parameters.protocolOptions(for: someFlow.reference)
            }
            return nil
        }
        if let flow = flow(for: flowID) {
            if let options: ProtocolOptions<T> = parameters.protocolOptions(for: flow.reference) {
                return options
            }
        }
        if let flow = secondaryFlow(for: flowID) {
            if let options: ProtocolOptions<T> = parameters.protocolOptions(for: flow.reference) {
                return options
            }
        }
        return parameters.protocolOptions(for: reference)
    }
    public func getOptions(
        from parameters: Parameters,
        for flowID: MultiplexedFlowIdentifier
    ) -> AbstractProtocolOptions? {
        if case .allFlows = flowID {
            if let options = parameters.protocolOptions(for: reference) {
                return options
            }
            if let someFlow = someFlow {
                return parameters.protocolOptions(for: someFlow.reference)
            }
            if let someFlow = someSecondaryFlow {
                return parameters.protocolOptions(for: someFlow.reference)
            }
            return nil
        }
        if let flow = flow(for: flowID) {
            if let options = parameters.protocolOptions(for: flow.reference) {
                return options
            }
        }
        if let flow = secondaryFlow(for: flowID) {
            if let options = parameters.protocolOptions(for: flow.reference) {
                return options
            }
        }
        return parameters.protocolOptions(for: reference)
    }
    #endif
}

@available(Network 0.1.0, *)
extension MultiplexedFlow {
    internal func validate(
        upper upperProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard upperProtocol == upper.reference else {
            Logger.proto.fault("Received \'\(label)\' from incorrect upper protocol")
            throw ProtocolInstanceError.invalidUpperProtocol
        }
        #endif
    }

    public var context: NetworkContext { parentProtocol.context }

    public mutating func attachUpperProtocol(
        _ upperProtocol: UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard upper.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        upper = upperProtocol

        do {
            try parentProtocol.setup(flow: identifier, remote: remote, local: local, parameters: parameters, path: path)
        } catch let error {
            upper = .init()
            throw error
        }
    }

    public mutating func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        parentProtocol.teardown(state: &state, flow: identifier)
        parentProtocol.multiplexedFlows.removeValue(forKey: identifier)
        upper = UpperProtocol()
        self.reference.discardPendingEventsForUpperProtocol(state: &state)
        upperReceiveQueue.finalizeAllFramesAsFailed()
        upperSendQueue.finalizeAllFramesAsFailed()
        parentProtocol.teardownIfPossible(state: &state)
    }

    public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        do { try validate(upper: from, #function) } catch { return }
        if parentProtocol.isConnected(state: &state) {
            if canCallConnect(state: &state, requested: true) {
                parentProtocol.connect(state: &state, flow: identifier)
            }
        } else {
            connectRequested(state: &state)
            parentProtocol.connectInternal(state: &state)
        }
    }

    public func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(upper: from, #function) } catch { return }
        if canCallDisconnect(state: &state) {
            parentProtocol.disconnect(state: &state, flow: identifier, error: error)
        }
    }

    public func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        // Don't validate upper, can pass through
        if parentProtocol.handleApplicationEvent(state: &state, flow: identifier, event: event) == .consumed { return }
        parentProtocol.applyToAllPaths { path in
            path.lower.invokeApplicationEvent(state: &state, from, event: event)
        }
    }

    public func getMetadata<P>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? where P: NetworkProtocol {
        do { try validate(upper: from, #function) } catch { return nil }
        return parentProtocol.getMetadata(flow: identifier)
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        do { try validate(upper: from, #function) } catch { return nil }
        return parentProtocol.getMetrics(flow: identifier, requestedNetworkMetric: requestedNetworkMetric)
    }

    fileprivate func deliverConnectedEvent() {
        fromExternal { state in
            deliverConnectedEvent(state: &state)
        }
    }

    fileprivate func deliverConnectedEvent(state: inout NetworkContext.State) {
        if upper.isDetached {
            // Enqueue pending event instead of delivering immediately.
            // Inbound multiplexed flows may get attached after creation.
            let selfReference = self.reference
            selfReference.enqueuePendingEventForUpperProtocol(state: &state, event: .connected(selfReference, upper.reference, { _, _ in

            }))
        } else {
            // Deliver connected event *followed by* any events which were buffered while detached
            upper.deliverConnectedEvent(state: &state, self.reference)
            self.reference.reassignQueuedPendingEventsForUpperProtocol(state: &state, to: upper.reference)
        }
    }

    fileprivate func deliverDisconnectedEvent(error: NetworkError?) {
        fromExternal { state in
            deliverDisconnectedEvent(state: &state, error: error)
        }
    }

    fileprivate func deliverDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?) {
        if upper.isDetached {
            // Enqueue pending event instead of delivering immediately.
            // Inbound multiplexed flows may get attached after creation.
            let selfReference = self.reference
            selfReference.enqueuePendingEventForUpperProtocol(
                state: &state,
                event: .disconnected(selfReference, upper.reference, error: error, { _, _, _ in

                })
            )
        } else {
            upper.deliverDisconnectedEvent(state: &state, self.reference, error: error)
        }
    }

    #if !NETWORK_EMBEDDED
    public func getOptions<T>(from parameters: Parameters) -> ProtocolOptions<T>? {
        parameters.protocolOptions(for: reference)
    }
    public func getOptions(from parameters: Parameters) -> AbstractProtocolOptions? {
        parameters.protocolOptions(for: reference)
    }
    #endif
}

@available(Network 0.1.0, *)
extension MultiplexedFlow where ParentProtocol: HeterogeneousManyToManyProtocolHandler {
    public mutating func detach(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        parentProtocol.teardown(state: &state, flow: identifier)
        parentProtocol.multiplexedFlows.removeValue(forKey: identifier)
        parentProtocol.multiplexedSecondaryFlows.removeValue(forKey: identifier)
        upper = UpperProtocol()
        self.reference.discardPendingEventsForUpperProtocol(state: &state)
        upperReceiveQueue.finalizeAllFramesAsFailed()
        upperSendQueue.finalizeAllFramesAsFailed()
        parentProtocol.teardownIfPossible(state: &state)
    }
}

@available(Network 0.1.0, *)
extension MultiplexedDatapathFlow where Self: AutomaticUpperStreamProcessing {
    public mutating func receiveStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        return try receiveStreamData(state: &state, minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }

    public func getOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected(state: &state) else { throw NetworkError.posix(ENOTCONN) }
        return try getOutboundStreamDataRoomAvailable(state: &state)
    }

    public mutating func sendStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(EINVAL)
        }
        guard isConnected(state: &state) else {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try sendStreamData(state: &state, streamData)
    }
}

@available(Network 0.1.0, *)
extension MultiplexedDatapathFlow where Self: AutomaticUpperStreamProcessing, Self: OutboundStreamEarlyDataHandler {
    public mutating func sendEarlyStreamData(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(EINVAL)
        }
        try sendEarlyStreamData(state: &state, streamData)
    }
}

@available(Network 0.1.0, *)
extension ManyToManyApplicationStreamProtocol where Flow: AutomaticUpperStreamProcessing {
    public func accessStreamDataToSend(flow flowID: MultiplexedFlowIdentifier, _ body: (inout FrameArray) -> Void) {
        guard var flow = self.flow(for: flowID) else { return }
        body(&flow.upperSendQueue)
    }

    public func blockSending(flow flowID: MultiplexedFlowIdentifier) {
        guard var flow = self.flow(for: flowID) else { return }
        flow.blockUpperSendQueue = true
    }

    public func unblockSending(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier
    ) {
        guard var flow = self.flow(for: flowID) else { return }
        flow.blockUpperSendQueue = false
        flow.upper.deliverOutboundRoomAvailableEvent(state: &state, flow.reference)
    }

    public func enqueueInboundStreamData(
        flow flowID: MultiplexedFlowIdentifier,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        guard var flow = self.flow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        return try flow.addToUpperReceiveQueue(streamData)
    }

    public func deliverEnqueuedInboundStreamData(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier
    ) throws(NetworkError) {
        guard let flow = self.flow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        flow.serviceUpperReceiveQueue(state: &state)
    }
    // Enqueue and delivery the stream data all in one shot
    public func deliverInboundStreamData(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        guard var flow = self.flow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        try deliverInboundStreamData(state: &state, flow: &flow, streamData: streamData)
    }

    // Enqueue and deliver the stream data directly to the flow
    public func deliverInboundStreamData(
        state: inout NetworkContext.State,
        flow existingFlow: inout Flow,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        try existingFlow.addToUpperReceiveQueue(streamData)
        existingFlow.serviceUpperReceiveQueue(state: &state)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
open class MultiplexedStreamFlow<ParentProtocol: ManyToManyApplicationStreamProtocol, LinkageType: InboundStreamLinkage>: MultiplexedDatapathFlow,
    AutomaticUpperStreamProcessing
{
    public typealias ParentProtocol = ParentProtocol
    public typealias UpperProtocol = LinkageType

    public var parentProtocol: ParentProtocol
    public var upper = UpperProtocol()
    public var eventManager = ProtocolEventManager()

    public var upperSendQueue = FrameArray()
    public var upperReceiveQueue = FrameArray()
    public var maximumStreamDataSize: Int = Int.max
    public var blockUpperSendQueue: Bool = false

    public var log = NetworkLoggerState()

    fileprivate var _identifier: MultiplexedFlowIdentifier?
    public var identifier: MultiplexedFlowIdentifier {
        if let _identifier { return _identifier }
        return .init(upper.reference)
    }

    public var reference: ProtocolInstanceReference

    public func serviceUpperSendQueue(state: inout NetworkContext.State) {
        parentProtocol.serviceStreamDataToSend(state: &state, flow: identifier)
    }

    public required init(parent: ParentProtocol, inbound: Bool) {
        self.parentProtocol = parent
        self._identifier = nil
        reference = .init(context: parent.context, eventManager: &self.eventManager)
        reference.setParentReference(parent.reference)

        if inbound {
            self._identifier = .init(inboundReference: reference)
        }
    }

    public required init(parent: ParentProtocol, inbound: Bool, state: inout NetworkContext.State) {
        self.parentProtocol = parent
        self._identifier = nil
        reference = .init(eventManager: &self.eventManager, context: parent.context, state: &state)
        reference.setParentReference(parent.reference)

        if inbound {
            self._identifier = .init(inboundReference: reference)
        }
    }

    public func upperReceiveQueueDrainedBytes(state: inout NetworkContext.State, _ bytes: Int) {
        // No-op by default
    }

    /// To be overridden by subclasses
    public func asLowerLinkage() -> UpperProtocol.PairedLowerLinkage {
        .init()
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol UnidirectionalAbortingStreamFlow: MultiplexedDatapathFlow, OutboundStreamUnidirectionalAbortHandler {
    func abortInbound(state: inout NetworkContext.State, error: NetworkError?)
    func abortOutbound(state: inout NetworkContext.State, error: NetworkError?)
}

@available(Network 0.1.0, *)
extension UnidirectionalAbortingStreamFlow {
    public func deliverInboundAbortedEvent(error: NetworkError?) {
        if upper.isDetached {
            // Enqueue pending event instead of delivering immediately.
            // Inbound multiplexed flows may get attached after creation.
            let selfReference = self.reference
            selfReference.enqueuePendingEventForUpperProtocol(
                state: &context.state,
                event: .inboundAborted(selfReference, upper.reference, error: error, { _, _, _ in

                })
            )
        } else {
            upper.deliverInboundAbortedEvent(state: &context.state, self.reference, error: error)
        }
    }

    public func deliverOutboundAbortedEvent(error: NetworkError?) {
        if upper.isDetached {
            // Enqueue pending event instead of delivering immediately.
            // Inbound multiplexed flows may get attached after creation.
            let selfReference = self.reference
            selfReference.enqueuePendingEventForUpperProtocol(
                state: &context.state,
                event: .outboundAborted(selfReference, upper.reference, error: error, { _, _, _ in

                })
            )
        } else {
            upper.deliverOutboundAbortedEvent(state: &context.state, self.reference, error: error)
        }
    }

    public func abortInbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(upper: from, #function) } catch { return }
        guard isConnected(state: &state) else { return }
        abortInbound(state: &state, error: error)
    }

    public func abortOutbound(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(upper: from, #function) } catch { return }
        guard isConnected(state: &state) else { return }
        abortOutbound(state: &state, error: error)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol EarlyDataStreamFlow: MultiplexedDatapathFlow, OutboundStreamEarlyDataHandler {}

@available(Network 0.1.0, *)
extension MultiplexedDatapathFlow where Self: AutomaticUpperDatagramProcessing {
    public mutating func receiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected(state: &state) else { throw NetworkError.posix(ENOTCONN) }
        return try receiveDatagrams(state: &state, maximumDatagramCount: maximumDatagramCount)
    }

    public func getDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected(state: &state) else { throw NetworkError.posix(ENOTCONN) }
        return try getDatagramsToSend(
            state: &state,
            maximumDatagramCount: maximumDatagramCount,
            minimumDatagramSize: minimumDatagramSize
        )
    }

    public mutating func sendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch {
            datagrams.finalizeAllFramesAsFailed()
            throw NetworkError.posix(EINVAL)
        }
        guard isConnected(state: &state) else {
            datagrams.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try sendDatagrams(state: &state, datagrams)
    }
}

@available(Network 0.1.0, *)
extension ManyToManyApplicationDatagramProtocol where Flow: AutomaticUpperDatagramProcessing {
    public func accessDatagramsToSend(flow flowID: MultiplexedFlowIdentifier, _ body: (inout FrameArray) -> Void) {
        guard var flow = self.flow(for: flowID) else { return }
        body(&flow.upperSendQueue)
    }

    public func blockSending(flow flowID: MultiplexedFlowIdentifier) {
        guard var flow = self.flow(for: flowID) else { return }
        flow.blockUpperSendQueue = true
    }

    public func unblockSending(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier
    ) {
        guard var flow = self.flow(for: flowID) else { return }
        flow.blockUpperSendQueue = false
        flow.upper.deliverOutboundRoomAvailableEvent(state: &state, flow.reference)
    }

    public func enqueueInboundDatagrams(
        flow flowID: MultiplexedFlowIdentifier,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        guard var flow = self.flow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        return try flow.addToUpperReceiveQueue(datagrams)
    }

    public func deliverEnqueuedInboundDatagrams(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier
    ) throws(NetworkError) {
        guard let flow = self.flow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        flow.serviceUpperReceiveQueue(state: &state)
    }

    // Enqueue and delivery the datagrams all in one shot
    public func deliverInboundDatagrams(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        guard var flow = self.flow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        try flow.addToUpperReceiveQueue(datagrams)
        flow.serviceUpperReceiveQueue(state: &state)
    }
}

@available(Network 0.1.0, *)
extension HeterogeneousManyToManyProtocolHandler where SecondaryFlow: AutomaticUpperDatagramProcessing {
    public func accessDatagramsToSend(flow flowID: MultiplexedFlowIdentifier, _ body: (inout FrameArray) -> Void) {
        guard var flow = self.secondaryFlow(for: flowID) else { return }
        body(&flow.upperSendQueue)
    }

    public func blockSending(flow flowID: MultiplexedFlowIdentifier) {
        guard var flow = self.secondaryFlow(for: flowID) else { return }
        flow.blockUpperSendQueue = true
    }

    public func unblockSending(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier
    ) {
        guard var flow = self.secondaryFlow(for: flowID) else { return }
        flow.blockUpperSendQueue = false
        flow.upper.deliverOutboundRoomAvailableEvent(state: &state, flow.reference)
    }

    public func enqueueInboundDatagrams(
        flow flowID: MultiplexedFlowIdentifier,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        guard var flow = self.secondaryFlow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        return try flow.addToUpperReceiveQueue(datagrams)
    }

    public func deliverEnqueuedInboundDatagrams(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier
    ) throws(NetworkError) {
        guard let flow = self.secondaryFlow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        flow.serviceUpperReceiveQueue(state: &state)
    }

    // Enqueue and delivery the datagrams all in one shot
    public func deliverInboundDatagrams(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        guard var flow = self.secondaryFlow(for: flowID) else { throw NetworkError.posix(EINVAL) }
        try deliverInboundDatagrams(state: &state, flow: &flow, datagrams: datagrams)
    }

    // Enqueue and deliver the datagrams directly to the flow
    public func deliverInboundDatagrams(
        state: inout NetworkContext.State,
        flow existingFlow: inout SecondaryFlow,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        try existingFlow.addToUpperReceiveQueue(datagrams)
        existingFlow.serviceUpperReceiveQueue(state: &state)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
open class MultiplexedDatagramFlow<ParentProtocol: ManyToManyApplicationDatagramProtocol, LinkageType: InboundDatagramLinkage>: MultiplexedDatapathFlow,
    AutomaticUpperDatagramProcessing
{
    public typealias ParentProtocol = ParentProtocol
    public typealias UpperProtocol = LinkageType

    public var parentProtocol: ParentProtocol
    public var upper = UpperProtocol()
    public var eventManager = ProtocolEventManager()

    public var upperSendQueue = FrameArray()
    public var upperReceiveQueue = FrameArray()
    public var maximumUpperDatagramSize: Int = 0
    public var blockUpperSendQueue: Bool = false

    public var log = NetworkLoggerState()

    var _identifier: MultiplexedFlowIdentifier?
    public var identifier: MultiplexedFlowIdentifier {
        if let _identifier { return _identifier }
        return .init(upper.reference)
    }

    public var reference: ProtocolInstanceReference

    public func serviceUpperSendQueue(state: inout NetworkContext.State) {
        parentProtocol.serviceDatagramsToSend(state: &state, flow: identifier)
    }

    public required init(parent: ParentProtocol, inbound: Bool) {
        self.parentProtocol = parent
        self._identifier = nil
        reference = .init(context: parent.context, eventManager: &self.eventManager)
        reference.setParentReference(parent.reference)
        if inbound {
            self._identifier = .init(inboundReference: reference)
        }
    }

    public required init(parent: ParentProtocol, inbound: Bool, state: inout NetworkContext.State) {
        self.parentProtocol = parent
        self._identifier = nil
        reference = .init(eventManager: &self.eventManager, context: parent.context, state: &state)
        reference.setParentReference(parent.reference)
        if inbound {
            self._identifier = .init(inboundReference: reference)
        }
    }

    /// To be overridden by subclasses
    public func asLowerLinkage() -> UpperProtocol.PairedLowerLinkage {
        .init()
    }
}

@available(Network 0.1.0, *)
extension MultiplexingPath {
    internal func validate(
        lower lowerProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard !lowerProtocol.isNone else {
            Logger.proto.fault("Received \'\(label)\' from incorrect lower protocol")
            throw ProtocolInstanceError.invalidLowerProtocol
        }
        #endif
    }

    public var context: NetworkContext { parentProtocol.context }

    public mutating func attachLowerProtocol(
        _ lowerProtocol: LowerProtocol,
    ) throws(NetworkError) -> LowerProtocol.PairedUpperLinkage? {
        guard lower.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        lower = lowerProtocol
        return nil
    }

    fileprivate func invokeConnect() {
        lower.invokeConnect(state: &context.state, self.reference)
    }

    fileprivate func invokeConnect(state: inout NetworkContext.State) {
        lower.invokeConnect(state: &state, self.reference)
    }

    fileprivate func invokeDisconnect(error: NetworkError?) {
        lower.invokeDisconnect(state: &context.state, self.reference, error: error)
    }

    fileprivate func invokeDetach() {
        try? lower.invokeDetach(state: &context.state, self.reference)
    }

    fileprivate func invokeDetach(state: inout NetworkContext.State) {
        try? lower.invokeDetach(state: &state, self.reference)
    }
}

@available(Network 0.1.0, *)
extension MultiplexingPath {
    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        do { try validate(lower: from, #function) } catch { return }
        if parentProtocol.canCallConnect(state: &state, requested: false) {
            parentProtocol.connect(state: &state)
        }
        parentProtocol.handleConnectedEvent(state: &state, path: identifier)
        parentProtocol.handlePathChanged(
            state: &state,
            path: identifier,
            event: .established,
            isPrimary: pathIsPrimary
        )
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        do { try validate(lower: from, #function) } catch { return }
        parentProtocol.handlePathChanged(state: &state, path: identifier, event: .unavailable, isPrimary: false)
        parentProtocol.handleDisconnectedEvent(state: &state, path: identifier, error: error)
    }

    public mutating func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        // Don't validate lower, can pass through
        if case .pathPrimaryChanged(let primary) = event.internalEvent {
            if primary && !pathIsPrimary {
                var parent = parentProtocol
                parent.resetPrimaryPath(newPrimary: identifier)
            } else if !primary {
                pathIsPrimary = false
            }
            let pathEvent: MultiplexingPathEvent = isConnected(state: &state) ? .established : .available
            parentProtocol.handlePathChanged(
                state: &state,
                path: identifier,
                event: pathEvent,
                isPrimary: pathIsPrimary
            )
            return
        }

        if parentProtocol.handleNetworkProtocolEvent(state: &state, path: identifier, event: event) == .consumed {
            return
        }
        parentProtocol.applyToAllFlows { flow in
            flow.upper.deliverNetworkProtocolEvent(
                state: &state,
                originalReference: from,
                selfReference: flow.reference,
                event: event
            )
        }
    }
}

@available(Network 0.1.0, *)
extension ManyToManyProtocolHandler {
    public func deliverNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        inboundFlowLinkage.deliverNewInboundFlowEvent(
            state: &state,
            reference,
            flowReference: flowReference,
            flowMetadata: flowMetadata
        )
    }

    public func invokeConnect(
        state: inout NetworkContext.State,
        path pathID: MultiplexingPathIdentifier
    ) {
        guard let path = self.path(for: pathID) else { return }
        path.lower.invokeConnect(state: &state, path.reference)
    }

    public func invokeDisconnect(path pathID: MultiplexingPathIdentifier, error: NetworkError? = nil) {
        guard let path = self.path(for: pathID) else { return }
        path.lower.invokeDisconnect(state: &context.state, path.reference, error: error)
    }

    public func invokeEstablish(
        state: inout NetworkContext.State,
        path pathID: MultiplexingPathIdentifier
    ) {
        invokeConnect(state: &state, path: pathID)
    }

    public func deliverConnectedEvent(state: inout NetworkContext.State, flow flowID: MultiplexedFlowIdentifier) {
        switch flowID {
        case .allFlows:
            inboundFlowLinkage.deliverConnectedEvent(state: &state, reference)
            applyToAllFlows { flow in
                if flow.canCallConnect(state: &state, requested: false) {
                    connect(state: &state, flow: flow.identifier)
                }
            }
        case .outboundFlow, .inboundFlow:
            guard let flow = self.flow(for: flowID) else { return }
            flow.deliverConnectedEvent(state: &state)
        }
    }

    public func deliverDisconnectedEvent(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier,
        error: NetworkError?
    ) {
        switch flowID {
        case .allFlows:
            inboundFlowLinkage.deliverDisconnectedEvent(state: &state, reference, error: error)
            applyToAllFlows { flow in
                flow.deliverDisconnectedEvent(state: &state, error: error)
            }
        case .outboundFlow, .inboundFlow:
            guard let flow = self.flow(for: flowID) else { return }
            flow.deliverDisconnectedEvent(state: &state, error: error)
        }
    }

    public func deliverNetworkProtocolEvent(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier,
        event: NetworkProtocolEvent
    ) {
        switch flowID {
        case .allFlows:
            inboundFlowLinkage.deliverNetworkProtocolEvent(
                state: &state,
                originalReference: self.reference,
                selfReference: self.reference,
                event: event
            )
            applyToAllFlows { flow in
                flow.upper.deliverNetworkProtocolEvent(
                    state: &state,
                    originalReference: self.reference,
                    selfReference: flow.reference,
                    event: event
                )
            }
        case .outboundFlow, .inboundFlow:
            guard let flow = self.flow(for: flowID) else { return }
            flow.upper.deliverNetworkProtocolEvent(
                state: &state,
                originalReference: flow.reference,
                selfReference: flow.reference,
                event: event
            )
        }
    }
}

@available(Network 0.1.0, *)
extension HeterogeneousManyToManyProtocolHandler {
    public func deliverConnectedEvent(state: inout NetworkContext.State, flow flowID: MultiplexedFlowIdentifier) {
        switch flowID {
        case .allFlows:
            inboundFlowLinkage.deliverConnectedEvent(state: &state, reference)
            applyToAllFlows { flow in
                if flow.canCallConnect(state: &state, requested: false) {
                    connect(state: &state, flow: flow.identifier)
                }
            }
            applyToAllSecondaryFlows { flow in
                if flow.canCallConnect(state: &state, requested: false) {
                    connect(state: &state, flow: flow.identifier)
                }
            }
        case .outboundFlow, .inboundFlow:
            if let flow = self.flow(for: flowID) {
                flow.deliverConnectedEvent(state: &state)
            }
            if let flow = self.secondaryFlow(for: flowID) {
                flow.deliverConnectedEvent(state: &state)
            }
        }
    }

    public func deliverDisconnectedEvent(flow flowID: MultiplexedFlowIdentifier, error: NetworkError?) {
        switch flowID {
        case .allFlows:
            inboundFlowLinkage.deliverDisconnectedEvent(state: &context.state, reference, error: error)
            applyToAllFlows { flow in
                flow.deliverDisconnectedEvent(error: error)
            }
            applyToAllSecondaryFlows { flow in
                flow.deliverDisconnectedEvent(error: error)
            }
        case .outboundFlow, .inboundFlow:
            if let flow = self.flow(for: flowID) {
                flow.deliverDisconnectedEvent(error: error)
            }
            if let flow = self.secondaryFlow(for: flowID) {
                flow.deliverDisconnectedEvent(error: error)
            }
        }
    }

    public func deliverDisconnectedEvent(
        state: inout NetworkContext.State,
        flow flowID: MultiplexedFlowIdentifier,
        error: NetworkError?
    ) {
        switch flowID {
        case .allFlows:
            inboundFlowLinkage.deliverDisconnectedEvent(state: &state, reference, error: error)
            applyToAllFlows { flow in
                flow.deliverDisconnectedEvent(state: &state, error: error)
            }
            applyToAllSecondaryFlows { flow in
                flow.deliverDisconnectedEvent(state: &state, error: error)
            }
        case .outboundFlow, .inboundFlow:
            if let flow = self.flow(for: flowID) {
                flow.deliverDisconnectedEvent(state: &state, error: error)
            }
            if let flow = self.secondaryFlow(for: flowID) {
                flow.deliverDisconnectedEvent(state: &state, error: error)
            }
        }
    }

    /// Delivers a protocol event using a context state the caller already holds.
    public func deliverNetworkProtocolEvent(state: inout NetworkContext.State, flow flowID: MultiplexedFlowIdentifier, event: NetworkProtocolEvent) {
        switch flowID {
        case .allFlows:
            inboundFlowLinkage.deliverNetworkProtocolEvent(
                state: &state,
                originalReference: self.reference,
                selfReference: self.reference,
                event: event
            )
            applyToAllFlows { flow in
                flow.upper.deliverNetworkProtocolEvent(
                    state: &state,
                    originalReference: self.reference,
                    selfReference: flow.reference,
                    event: event
                )
            }
            applyToAllSecondaryFlows { flow in
                flow.upper.deliverNetworkProtocolEvent(
                    state: &state,
                    originalReference: self.reference,
                    selfReference: flow.reference,
                    event: event
                )
            }
        case .outboundFlow, .inboundFlow:
            if let flow = self.flow(for: flowID) {
                flow.upper.deliverNetworkProtocolEvent(
                    state: &state,
                    originalReference: flow.reference,
                    selfReference: flow.reference,
                    event: event
                )
            }
            if let flow = self.secondaryFlow(for: flowID) {
                flow.upper.deliverNetworkProtocolEvent(
                    state: &state,
                    originalReference: flow.reference,
                    selfReference: flow.reference,
                    event: event
                )
            }
        }
    }
}

@available(Network 0.1.0, *)
extension ManyToManyOutboundDatagramProtocol where Path: AutomaticLowerDatagramProcessing {
    public mutating func resumeReadingInboundDatagrams(path pathID: MultiplexingPathIdentifier) {
        guard var path = self.path(for: pathID) else { return }
        path.resumeReadingInboundDatagrams(state: &context.state)
    }

    @inline(__always)
    public func getDatagramsToSend(
        path pathID: MultiplexingPathIdentifier,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        try fromExternal { state throws(NetworkError) in
            try getDatagramsToSend(
                state: &state,
                path: pathID,
                maximumDatagramCount: maximumDatagramCount,
                minimumDatagramSize: minimumDatagramSize
            )
        }
    }

    /// Fetches datagrams to send using a context state the caller already holds.
    public func getDatagramsToSend(
        state: inout NetworkContext.State,
        path pathID: MultiplexingPathIdentifier,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        guard let path = self.path(for: pathID) else { throw NetworkError.posix(EINVAL) }
        return try path.lower.invokeGetDatagramsToSend(state: &state,
            path.reference,
            maximumDatagramCount: maximumDatagramCount,
            minimumDatagramSize: minimumDatagramSize
        )
    }

    public func enqueueOutboundDatagrams(
        path pathID: MultiplexingPathIdentifier,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        guard var path = self.path(for: pathID) else { throw NetworkError.posix(EINVAL) }
        return try path.addToLowerSendQueue(datagrams)
    }

    public func sendEnqueuedOutboundDatagrams(path pathID: MultiplexingPathIdentifier) throws(NetworkError) {
        guard var path = self.path(for: pathID) else { throw NetworkError.posix(EINVAL) }
        path.serviceLowerSendQueue(state: &context.state)
    }

    /// Services a path's send queue using a context state the caller already holds.
    public func sendEnqueuedOutboundDatagrams(
        state: inout NetworkContext.State,
        path pathID: MultiplexingPathIdentifier
    ) throws(NetworkError) {
        guard var path = self.path(for: pathID) else { throw NetworkError.posix(EINVAL) }
        path.serviceLowerSendQueue(state: &state)
    }

    public func accessReceivedDatagrams(path pathID: MultiplexingPathIdentifier, _ body: (inout FrameArray) -> Void) {
        guard var path = self.path(for: pathID) else {
            log.error("Unknown path for id: \(pathID)")
            return
        }
        body(&path.lowerReceiveQueue)
    }

    public func accessReceivedDatagrams(
        path pathID: MultiplexingPathIdentifier,
        _ body: (inout FrameArray, Path) -> Void
    ) {
        guard var path = self.path(for: pathID) else {
            log.error("Unknown path for id: \(pathID)")
            return
        }
        body(&path.lowerReceiveQueue, path)
    }

    public func sendAllEnqueuedOutboundDatagrams(state: inout NetworkContext.State) {
        allPathIdentifiers { pathID in
            try? sendEnqueuedOutboundDatagrams(state: &state, path: pathID)
        }
    }
}

@available(Network 0.1.0, *)
extension MultiplexingDatapathPath where Self: AutomaticLowerDatagramProcessing {
    public mutating func handleInboundDataAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        do { try validate(lower: from, #function) } catch { return }
        handleInboundDataAvailableEvent(state: &state)
    }

    public mutating func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) {
        do { try validate(lower: from, #function) } catch { return }
        handleOutboundRoomAvailableEvent(state: &state)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
open class MultiplexingDatagramPath<ParentProtocol: ManyToManyOutboundDatagramProtocol, LinkageType: OutboundDatagramLinkage>: MultiplexingDatapathPath,
    AutomaticLowerDatagramProcessing
{
    public typealias ParentProtocol = ParentProtocol
    public typealias LowerProtocol = LinkageType

    public var parentProtocol: ParentProtocol
    public var lower = LowerProtocol()
    public var eventManager = ProtocolEventManager()

    public let identifier = MultiplexingPathIdentifier()

    public var lowerSendQueue = FrameArray()
    public var lowerReceiveQueue = FrameArray()

    public var pathIsPrimary: Bool = false
    public var pathHasMigrationInfo: Bool = false

    public var reference: ProtocolInstanceReference

    public func serviceLowerReceiveQueue(state: inout NetworkContext.State) {
        guard !lowerReceiveQueue.isEmpty else { return }
        parentProtocol.serviceReceivedDatagrams(state: &state, path: identifier)
    }

    public func handleOutboundRoomAvailable(state: inout NetworkContext.State) {
        parentProtocol.handleOutboundRoomAvailableEvent(state: &state, path: identifier)
    }

    public required init(state: inout NetworkContext.State, parent: ParentProtocol) {
        self.parentProtocol = parent
        reference = .init(eventManager: &self.eventManager, context: parent.context, state: &state)
        reference.setParentReference(parent.reference)
    }

    /// To be overridden by subclasses
    public func asUpperLinkage() -> LowerProtocol.PairedUpperLinkage {
        .init()
    }
}
