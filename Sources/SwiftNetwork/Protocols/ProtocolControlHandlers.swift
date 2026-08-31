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

/// A protocol closer to the app, with a linkage to a lower protocol toward the network.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol UpperProtocolHandler<LowerProtocol>: ~Copyable, ProtocolInstance {
    associatedtype LowerProtocol: LowerProtocolLinkage

    mutating func attachLowerProtocol(
        _ lowerProtocol: LowerProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    mutating func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    mutating func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )
    mutating func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    )
}

/// A protocol closer to the network, with a linkage to an upper protocol toward the app.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol LowerProtocolHandler<UpperProtocol>: ~Copyable, ProtocolInstance {
    associatedtype UpperProtocol: UpperProtocolLinkage

    mutating func attachUpperProtocol(
        _ upperProtocol: UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    mutating func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError)

    mutating func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    mutating func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )

    mutating func handleApplicationEvent(
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
