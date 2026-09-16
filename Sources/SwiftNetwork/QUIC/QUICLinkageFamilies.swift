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

#if !NETWORK_NO_SWIFT_QUIC

/// Bundles the linkage families a QUIC connection is generic over.
///
/// A QUIC connection presents stream flows and datagram flows to the protocols above it, and
/// runs over datagram paths beneath it. Each of those three attachment points can use a
/// different linkage family. Grouping them into a single type lets every type inside the
/// connection take one generic parameter instead of three.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol QUICLinkageFamilies: Sendable {
    /// The linkage family used by stream flows handed to upper protocols.
    ///
    /// Its lower linkage must be constructible from a QUIC stream, so that the stack can hand
    /// a newly created stream to the protocol above it.
    associatedtype StreamFlowLinkageFamily: StreamLinkageFamily
    where StreamFlowLinkageFamily.Lower: QUICStreamLowerLinkage,
          StreamFlowLinkageFamily.Lower.QUICFamilies == Self

    /// The linkage family used by datagram flows handed to upper protocols.
    ///
    /// Its lower linkage must be constructible from a QUIC datagram flow.
    associatedtype DatagramFlowLinkageFamily: DatagramLinkageFamily
    where DatagramFlowLinkageFamily.Lower: QUICDatagramFlowLowerLinkage,
          DatagramFlowLinkageFamily.Lower.QUICFamilies == Self

    /// The linkage family used by the datagram paths beneath the connection.
    ///
    /// Its upper linkage must be constructible from a QUIC path, so that the stack can attach
    /// a newly created path to the datagram protocol below it.
    associatedtype PathLinkageFamily: DatagramLinkageFamily
    where PathLinkageFamily.Upper: QUICPathUpperLinkage,
          PathLinkageFamily.Upper.QUICFamilies == Self

    associatedtype MultipathLinkageType: DatagramMultipathLinkage
    where MultipathLinkageType.MultipathLowerProtocol == PathLinkageFamily.Lower
}

/// Require that QUICStreamInstances can be wrapped in linkages
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol QUICStreamLowerLinkage: Sendable {
    associatedtype QUICFamilies: QUICLinkageFamilies
    init(_ quicStream: QUICStreamInstance<QUICFamilies>)
}

/// Require that QUICDatagramFlows can be wrapped in linkages
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol QUICDatagramFlowLowerLinkage: Sendable {
    associatedtype QUICFamilies: QUICLinkageFamilies
    init(_ quicStream: QUICDatagramFlow<QUICFamilies>)
}

/// Require that QUICPaths can be wrapped in linkages
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol QUICPathUpperLinkage: Sendable {
    associatedtype QUICFamilies: QUICLinkageFamilies
    init(_ quicStream: QUICPath<QUICFamilies>)
}

#endif
