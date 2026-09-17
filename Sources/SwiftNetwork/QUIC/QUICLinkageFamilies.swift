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

/// Bundles the linkage families a whole protocol stack is built from.
///
/// A stack's datagram and stream linkages reference each other -- TCP takes datagrams below and
/// presents a stream above, and a QUIC connection presents both -- so a type generic over one
/// family almost always needs the other. Carrying them as separate generic parameters makes every
/// such type generic over the cross product, and the associated-type expansion does not terminate.
/// Grouping them means the storage and every linkage take exactly one generic parameter.
///
/// The group also says how to wrap a QUIC stream, datagram flow, or path in one of its own
/// linkages. That used to be expressed as conformances on the linkages themselves, pointing back at
/// the group (`QUICFamilies == Self`); requiring it here instead keeps the requirements pointing one
/// way, which the compiler can actually resolve. A client that supplies its own group therefore has
/// to keep supporting these QUIC attachment points.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol LinkageFamilyGroup: Sendable {
    /// The family used by datagram protocols in this stack, including the paths beneath a QUIC
    /// connection and the datagram flows it presents.
    associatedtype DatagramFamily: DatagramLinkageFamily

    /// The family used by stream protocols in this stack, including the stream flows a QUIC
    /// connection presents.
    associatedtype StreamFamily: StreamLinkageFamily

    /// The multipath linkage a protocol spanning several paths hands out. QUIC is the only such
    /// protocol today.
    associatedtype MultipathLinkageType: DatagramMultipathLinkage
    where MultipathLinkageType.MultipathLowerProtocol == DatagramFamily.Lower

    /// Wraps a QUIC stream in the lower linkage its upper protocol talks to.
    static func linkage(for quicStream: QUICStreamInstance<Self>) -> StreamFamily.Lower

    /// Wraps a QUIC datagram flow in the lower linkage its upper protocol talks to.
    static func linkage(for quicDatagramFlow: QUICDatagramFlow<Self>) -> DatagramFamily.Lower

    /// Wraps a QUIC path in the upper linkage the datagram protocol below it reports to.
    static func linkage(for quicPath: QUICPath<Self>) -> DatagramFamily.Upper
}

#endif
