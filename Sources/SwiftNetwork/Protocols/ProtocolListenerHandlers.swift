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

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundFlowHandler: ~Copyable, UpperProtocolHandler {
    func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    )
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol ListenerHandler: ~Copyable, LowerProtocolHandler where UpperProtocol: InboundFlowLinkage {
    #if !NETWORK_EMBEDDED
    // Create a new flow
    mutating func attachUpperProtocolToNewFlow<Linkage: LowerProtocolLinkage>(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Linkage

    // Attach to an inbound flow
    mutating func attachUpperProtocolToExistingFlow<Linkage: LowerProtocolLinkage>(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> Linkage
    #endif
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol DatagramListenerHandler: ~Copyable, ListenerHandler
where UpperProtocol.DataLinkage == DefaultOutboundDatagramLinkage {
    mutating func attachNewDatagramFlowProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> DatagramListenerLinkage

    // Create a new flow
    mutating func attachUpperDatagramProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> DefaultOutboundDatagramLinkage

    // Attach to an inbound flow
    mutating func attachUpperDatagramProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> DefaultOutboundDatagramLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol StreamListenerHandler: ~Copyable, ListenerHandler
where UpperProtocol: InboundStreamFlowLinkage {
    mutating func attachNewStreamFlowProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> UpperProtocol.PairedLinkage

    // Create a new flow
    mutating func attachUpperStreamProtocolToNewFlow(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> UpperProtocol.DataLinkage

    // Attach to an inbound flow
    mutating func attachUpperStreamProtocolToExistingFlow(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) -> UpperProtocol.DataLinkage
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol HeterogeneousListenerHandler: ~Copyable, ListenerHandler {
    associatedtype SecondaryUpperProtocol: InboundFlowLinkage
}
