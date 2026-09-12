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

// MARK: Automatic Datagram Processing

/// A protocol for automatically sending and receiving datagrams with lower protocols.
///
/// Add conformance to `AutomaticLowerDatagramProcessing` to automatically send and receive
/// datagrams from lower protocols.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol AutomaticLowerDatagramProcessing: ~Copyable, InboundDatagramHandler {
    var lower: LowerProtocol { get set }

    /// A queue of datagrams the framework sends to the lower protocol.
    ///
    /// Protocols generally don't need to access this directly.
    /// Instead, call `addToLowerSendQueue`.
    var lowerSendQueue: FrameArray { get set }

    /// A queue of datagrams that have been received from the lower protocol.
    ///
    /// Protocols should access frames from this queue in response
    /// to the `serviceLowerReceiveQueue` call.
    var lowerReceiveQueue: FrameArray { get set }

    /// A function the framework calls when the lower protocol has added datagrams to
    /// `lowerReceiveQueue`.
    ///
    /// Protocols should implement this function to customize behavior. Thread `state` into any
    /// calls made to other protocols so that the state is never re-derived from the context.
    mutating func serviceLowerReceiveQueue(state: inout NetworkContext.State)

    /// A function the framework calls when outbound room becomes available.
    ///
    /// Protocols should implement this function to customize behavior.
    func handleOutboundRoomAvailable()
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension AutomaticLowerDatagramProcessing where Self: ~Copyable {
    /// Adds datagrams to the lower send queue.
    ///
    /// Appends frames to `lowerSendQueue`.
    public mutating func addToLowerSendQueue(_ datagrams: consuming FrameArray) throws(NetworkError) {
        lowerSendQueue.add(frames: datagrams)
    }

    /// Indicates to the lower protocol that datagrams have been added to the send queue.
    ///
    /// Drains `lowerSendQueue` to the lower protocol.
    public mutating func serviceLowerSendQueue(state: inout NetworkContext.State) {
        guard !lowerSendQueue.isEmpty else { return }
        try? lower.invokeSendDatagrams(state: &state, reference, datagrams: lowerSendQueue.drainArray())
    }

    /// Indicates that datagrams should be read from the lower protocol.
    public mutating func resumeReadingInboundDatagrams(state: inout NetworkContext.State) {
        _readInboundDatagrams(state: &state)
    }
}

/// A protocol for automatically processing datagrams from upper protocols.
///
/// Add conformance to `AutomaticUpperDatagramProcessing` to automatically process datagrams
/// from upper protocols.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol AutomaticUpperDatagramProcessing: ~Copyable, OutboundDatagramHandler {
    var upper: UpperProtocol { get set }

    /// A queue of datagrams that have been sent by the upper protocol.
    ///
    /// Protocols should access frames from this queue in response
    /// to the `serviceUpperSendQueue` call.
    var upperSendQueue: FrameArray { get set }

    /// A function the framework calls when the upper protocol has added datagrams to
    /// `upperSendQueue`.
    ///
    /// Protocols should implement this function to customize behavior.
    func serviceUpperSendQueue()

    /// The maximum datagram size the upper protocol can send.
    var maximumUpperDatagramSize: Int { get set }

    /// A Boolean value that indicates whether the upper protocol is blocked from sending datagrams.
    var blockUpperSendQueue: Bool { get set }

    /// A queue of datagrams the framework delivers to the upper protocol.
    ///
    /// Protocols generally don't need to access this directly.
    /// Instead, call `addToUpperReceiveQueue`.
    var upperReceiveQueue: FrameArray { get set }

}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension AutomaticUpperDatagramProcessing where Self: ~Copyable {
    /// Adds datagrams to the upper receive queue.
    ///
    /// Appends frames to `upperReceiveQueue`.
    public mutating func addToUpperReceiveQueue(_ datagrams: consuming FrameArray) throws(NetworkError) {
        upperReceiveQueue.add(frames: datagrams)
    }

    /// Indicates to the upper protocol that datagrams have been added to the receive queue.
    ///
    /// Notifies the upper protocol that frames are available in `upperReceiveQueue`.
    public func serviceUpperReceiveQueue(state: inout NetworkContext.State) {
        guard !upperReceiveQueue.isEmpty else { return }
        upper.deliverInboundDataAvailableEvent(state: &state, reference)
    }
}

// MARK: Manual Datagram Processing

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDatagramHandler: ~Copyable, InboundDataHandler where LowerProtocol: OutboundDatagramLinkage { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundDatagramHandler: ~Copyable, OutboundDataHandler where UpperProtocol: InboundDatagramLinkage {
    mutating func receiveDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray?
    mutating func getDatagramsToSend(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?
    mutating func sendDatagrams(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError)
}

// MARK: Implementation Details

@available(Network 0.1.0, *)
extension AutomaticLowerDatagramProcessing where Self: ~Copyable {
    mutating func _readInboundDatagrams(state: inout NetworkContext.State) {
        var readCount = 0
        repeat {
            do throws(NetworkError) {
                let datagrams = try lower.invokeReceiveDatagrams(
                    state: &state,
                    reference,
                    maximumDatagramCount: Int.max
                )
                if let datagrams = consume datagrams {
                    readCount = datagrams.count
                    lowerReceiveQueue.add(frames: datagrams)
                } else {
                    readCount = 0
                }
            } catch {
                break
            }
            serviceLowerReceiveQueue(state: &state)
            serviceLowerSendQueue(state: &state)
        } while readCount != 0
    }

    mutating func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {
        _readInboundDatagrams(state: &state)
    }

    mutating func handleOutboundRoomAvailableEvent(state: inout NetworkContext.State) {
        serviceLowerSendQueue(state: &state)
        handleOutboundRoomAvailable()
    }
}

@available(Network 0.1.0, *)
extension AutomaticUpperDatagramProcessing where Self: ~Copyable {
    internal func newOutboundFrame(_ dataSize: Int) -> Frame {
        Frame(count: dataSize)
    }

    public mutating func receiveDatagrams(
        state: inout NetworkContext.State,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !upperReceiveQueue.isEmpty else { return nil }
        return upperReceiveQueue.drainArray(maximumFrameCount: maximumDatagramCount)
    }

    public func getDatagramsToSend(
        state: inout NetworkContext.State,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !blockUpperSendQueue else { return nil }
        let datagramSize: Int
        if maximumUpperDatagramSize == 0 {
            datagramSize = minimumDatagramSize
        } else {
            datagramSize = min(minimumDatagramSize, maximumUpperDatagramSize)
        }
        var returnArray = FrameArray(capacity: maximumDatagramCount)
        for _ in 0..<maximumDatagramCount {
            returnArray.add(frame: newOutboundFrame(datagramSize))
        }
        return returnArray
    }

    public mutating func sendDatagrams(
        state: inout NetworkContext.State,
        _ datagrams: consuming FrameArray
    ) throws(NetworkError) {
        upperSendQueue.add(frames: datagrams)
        serviceUpperSendQueue()
    }
}
