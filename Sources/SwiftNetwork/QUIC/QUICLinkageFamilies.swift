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
    associatedtype StreamFlowLinkageFamily: StreamLinkageFamily
    /// The linkage family used by datagram flows handed to upper protocols.
    associatedtype DatagramFlowLinkageFamily: DatagramLinkageFamily
    /// The linkage family used by the datagram paths beneath the connection.
    associatedtype PathLinkageFamily: DatagramLinkageFamily
}

/// The linkage families used by a QUIC connection in a standard protocol stack.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DefaultQUICLinkageFamilies: QUICLinkageFamilies {
    public typealias StreamFlowLinkageFamily = DefaultStreamLinkageFamily
    public typealias DatagramFlowLinkageFamily = DefaultDatagramLinkageFamily
    public typealias PathLinkageFamily = DefaultDatagramLinkageFamily
}

// Spellings of the QUIC types for the default linkage families, for callers that work with a
// standard stack.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public typealias QUICDefaultPath = QUICPath<DefaultQUICLinkageFamilies>

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public typealias QUICDefaultStream = QUICStreamInstance<DefaultQUICLinkageFamilies>

@available(Network 0.1.0, *)
typealias QUICDefaultAck = Ack<DefaultQUICLinkageFamilies>

@available(Network 0.1.0, *)
typealias QUICDefaultRecovery = Recovery<DefaultQUICLinkageFamilies>

@available(Network 0.1.0, *)
typealias QUICDefaultStreamIDState = QUICStreamIDState<DefaultQUICLinkageFamilies>

#endif
