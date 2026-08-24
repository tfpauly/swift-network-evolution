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
public protocol InboundMessageHandler: ~Copyable, InboundDataHandler where LowerProtocol: OutboundMessageLinkage {
    mutating func handleInboundMessageAvailableEvent(_ from: ProtocolInstanceReference)
    mutating func handleOutboundMessageRoomAvailableEvent(_ from: ProtocolInstanceReference)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundMessageHandler: ~Copyable, OutboundDataHandler where UpperProtocol: InboundMessageLinkage {
    associatedtype OutboundMessageType: ~Copyable
    mutating func receiveMessage(_ from: ProtocolInstanceReference) throws(NetworkError) -> OutboundMessageType?
    mutating func sendMessage(_ from: ProtocolInstanceReference, message: consuming OutboundMessageType) throws(NetworkError)
}
