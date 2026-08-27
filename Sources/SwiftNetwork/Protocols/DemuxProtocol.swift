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

#if canImport(BasicContainers)
import BasicContainers
internal import DequeModule
#endif

#if canImport(Synchronization)
internal import Synchronization
#endif

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public enum DemuxError: Error, CustomStringConvertible {
    case patternTooLong
    case invalidMask

    public var description: String {
        switch self {
        case .patternTooLong: return "Pattern Too Long"
        case .invalidMask: return "Invalid Mask"
        }
    }
}

@_spi(Essentials)
@available(Network 0.1.0, *)
public struct DemuxPattern: Sendable, Hashable {
    static let maxPatternLength = 30
    let patternRange: Range<Int>  // Range of bytes in frame that the pattern must match
    let pattern: [30 of UInt8]  // Content of the pattern
    let mask: [30 of UInt8]  // Mask for the pattern

    public static func == (lhs: borrowing DemuxPattern, rhs: borrowing DemuxPattern) -> Bool {
        guard lhs.patternRange == rhs.patternRange else { return false }
        for i in 0..<maxPatternLength {
            guard lhs.pattern[i] == rhs.pattern[i],
                lhs.mask[i] == rhs.mask[i]
            else {
                return false
            }
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        for i in 0..<pattern.count {
            hasher.combine(pattern[i])
        }
    }

    var isEmpty: Bool {
        patternRange.isEmpty
    }

    init(_ pattern: RawSpan, at offset: Int, mask: RawSpan? = nil) throws(DemuxError) {
        let patternLength = pattern.byteCount
        guard patternLength <= Self.maxPatternLength else { throw .patternTooLong }

        self.patternRange = offset..<offset + patternLength
        var tempPattern = [30 of UInt8](repeating: 0)
        var tempMask = [30 of UInt8](repeating: 0xff)

        if let mask {
            guard mask.byteCount == patternLength else { throw .invalidMask }
            for i in 0..<patternLength {
                tempPattern[i] = pattern[i]
                tempMask[i] = mask[i]
            }
        } else {
            for i in 0..<patternLength {
                tempPattern[i] = pattern[i]
            }
        }
        self.pattern = tempPattern
        self.mask = tempMask
    }

    func matchesFrame(_ frame: borrowing Frame) -> Bool {
        guard !patternRange.isEmpty else { return false }
        guard let bytes = frame.bytes else { return false }
        guard bytes.byteCount >= patternRange.upperBound else { return false }
        let startOffset = patternRange.lowerBound
        let patternLength = patternRange.count
        for byteIndex in 0..<patternLength {
            if bytes[startOffset + byteIndex] & self.mask[byteIndex] != self.pattern[byteIndex] & self.mask[byteIndex] {
                // Mismatch in some byte
                return false
            }
        }
        return true
    }
}

@_spi(Essentials)
@available(Network 0.1.0, *)
public struct DemuxProtocol: NetworkProtocol {
    public typealias Options = DemuxOptions
    public typealias Metadata = DemuxMetadata
    public typealias Instance = DemuxInstance

    public struct DemuxOptions: PerProtocolOptions {
        var demuxPatterns = Deque<DemuxPattern>()

        init() {}

        init?(from serializedBytes: [UInt8]) {
            // Ignore content
        }

        public func serialize() -> [UInt8]? {
            var hasPatterns = false
            for demuxPattern in demuxPatterns {
                if !demuxPattern.isEmpty {
                    hasPatterns = true
                    break
                }
            }
            return Serializer.serialize { write in
                write.uint8(hasPatterns ? 1 : 0)
            }
        }
        public var serializeInParameters: Bool {
            true
        }
        public func deepCopy() -> DemuxOptions {
            self
        }
        public func isEqual(to other: DemuxOptions, for: ProtocolCompareMode) -> Bool {
            self == other
        }

        public mutating func addPattern(_ pattern: RawSpan, at offset: Int, mask: RawSpan? = nil) throws(DemuxError) {
            demuxPatterns.append(try DemuxPattern(pattern, at: offset, mask: mask))
        }
    }

    // TODO: Add a way to dynamically add patterns to an existing upper protocol
    public struct DemuxMetadata: PerProtocolMetadata {
        var isStatic: Bool = false

        init() {}
        public func isEqual(to other: DemuxMetadata, for: ProtocolCompareMode) -> Bool {
            self == other
        }
    }

    public final class DemuxInstance: OutboundDatagramHandler, InboundDatagramHandler, LoggableProtocol,
        ProtocolInstanceContainer
    {
        public typealias UpperProtocol = DefaultInboundDatagramLinkage
        public typealias LowerProtocol = DefaultOutboundDatagramLinkage
        
        var defaultUpper = UpperProtocol()
        var defaultInboundFrames = FrameArray()

        struct DemuxEntry: ~Copyable {
            var upper: UpperProtocol
            var inboundFrames = FrameArray()
            var demuxPatterns = Deque<DemuxPattern>()
        }
        var demuxEntries = NetworkUniqueArray<DemuxEntry>()

        var lower = LowerProtocol()
        var asUpper: LowerProtocol.PairedLinkage { .init(reference: reference) }
        var asLower: UpperProtocol.PairedLinkage { .init(reference: reference) }

        public private(set) var context: NetworkContext
        init(context: NetworkContext) {
            self.context = context
            self.reference = .init()
        }
        public var reference = ProtocolInstanceReference()
        public var log = NetworkLoggerState()
        public var eventManager = ProtocolEventManager()

        internal func validate(
            upper upperProtocol: ProtocolInstanceReference,
            _ label: String
        ) throws(ProtocolInstanceError) {
            #if DEBUG
            if upperProtocol == defaultUpper.reference { return }
            for i in 0..<demuxEntries.count {
                if demuxEntries[i].upper.reference == upperProtocol { return }
            }
            Logger.proto.fault("Received \'\(label)\' from incorrect upper protocol")
            throw ProtocolInstanceError.invalidUpperProtocol

            #endif
        }

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

        //        public func attachUpperDatagramProtocol(_ from: ProtocolInstanceReference, remote: Endpoint?, local: Endpoint?, parameters: Parameters?, path: PathProperties?) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
        //            <#code#>
        //        }
        //

        public func attachUpperProtocol(
            _ upperProtocol: DefaultInboundDatagramLinkage,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            if defaultUpper.isDetached {
                // Set up default
                defaultUpper = upperProtocol
                #if !NETWORK_EMBEDDED
                if let parameters {
                    if let options = parameters.protocolOptions(for: self.reference) {
                        self.log.logPrefix = options.logIDString ?? ""
                    }
                }
                #endif
            } else if defaultUpper != upperProtocol {
                #if !NETWORK_EMBEDDED
                if let parameters {
                    if let demuxOptions: ProtocolOptions<DemuxProtocol> = parameters.protocolOptions(
                        for: self.reference
                    ) {
                        demuxEntries.append(
                            DemuxEntry(
                                upper: upperProtocol,
                                demuxPatterns: demuxOptions.perProtocolOptions!.demuxPatterns
                            )
                        )
                    }
                }
                #endif
            }
        }

        public func attachLowerProtocol(
            _ lowerProtocol: LowerProtocol,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            guard lower.isDetached else {
                throw NetworkError.posix(EALREADY)
            }
            lower = lowerProtocol
            try lowerProtocol.invokeAttachUpperProtocol(
                asUpper,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        }

        public func attachUpperDatagramProtocol(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
            if defaultUpper.isDetached {
                // Set up default
                defaultUpper = UpperProtocol(reference: from)
                #if !NETWORK_EMBEDDED
                if let parameters {
                    if let options = parameters.protocolOptions(for: self.reference) {
                        self.log.logPrefix = options.logIDString ?? ""
                    }
                }
                #endif
            } else if defaultUpper.reference != from {
                #if !NETWORK_EMBEDDED
                if let parameters {
                    if let demuxOptions: ProtocolOptions<DemuxProtocol> = parameters.protocolOptions(
                        for: self.reference
                    ) {
                        demuxEntries.append(
                            DemuxEntry(
                                upper: UpperProtocol(reference: from),
                                demuxPatterns: demuxOptions.perProtocolOptions!.demuxPatterns
                            )
                        )
                    }
                }
                #endif
            }

            return asLower
        }

        public func attachLowerDatagramProtocol(
            state: inout NetworkContext.State,
            _ lowerProtocol: ProtocolInstanceReference,
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            guard lower.isDetached else {
                throw NetworkError.posix(EALREADY)
            }
//            self.lower = try lowerProtocol.attachUpperDatagramProtocol(
//                state: &state,
//                reference,
//                remote: remote,
//                local: local,
//                parameters: parameters,
//                path: path
//            )
        }

        func addInboundDatagram(_ datagram: consuming Frame) -> Int? {
            for entryIndex in 0..<demuxEntries.count {
                for patternIndex in 0..<demuxEntries[entryIndex].demuxPatterns.count {
                    if demuxEntries[entryIndex].demuxPatterns[patternIndex].matchesFrame(datagram) {
                        // Found a match!
                        demuxEntries[entryIndex].inboundFrames.add(frame: datagram)
                        return entryIndex
                    }
                }
            }

            // Add to default
            defaultInboundFrames.add(frame: datagram)
            return nil
        }

        func serviceInboundFrames(
            _ from: ProtocolInstanceReference,
            maximumDatagramCount: Int,
            requestingIndex: inout Int?
        ) -> FrameArray? {
            if from == defaultUpper.reference {
                // Look for pending frames for default
                if !defaultInboundFrames.isEmpty {
                    return defaultInboundFrames.drainArray(maximumFrameCount: maximumDatagramCount)
                }
            } else {
                for i in 0..<demuxEntries.count {
                    if demuxEntries[i].upper.reference == from {
                        if !demuxEntries[i].inboundFrames.isEmpty {
                            return demuxEntries[i].inboundFrames.drainArray(maximumFrameCount: maximumDatagramCount)
                        }
                        requestingIndex = i
                        break
                    }
                }
            }
            return nil
        }

        public func receiveDatagrams(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            maximumDatagramCount: Int
        ) throws(NetworkError) -> FrameArray? {
            do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
            var requestingIndex: Int? = nil

            let returnArray = serviceInboundFrames(
                from,
                maximumDatagramCount: maximumDatagramCount,
                requestingIndex: &requestingIndex
            )
            if let returnArray {
                return returnArray
            }

            guard !demuxEntries.isEmpty else {
                // No patterns, just go direct
                return try lower.invokeReceiveDatagrams(state: &context.state, self.reference, maximumDatagramCount: maximumDatagramCount)
            }

            // Read datagrams out and categorize them based on patterns
            let inboundDatagrams = try lower.invokeReceiveDatagrams(state: &context.state, 
                self.reference,
                maximumDatagramCount: maximumDatagramCount
            )
            guard var inboundDatagrams, !inboundDatagrams.isEmpty else {
                return nil
            }

            var signalInboundDataAvailableToPatterns = false
            var signalInboundDataAvailableToDefault = false

            while let datagram = inboundDatagrams.popFirst() {
                let matchingIndex = self.addInboundDatagram(datagram)
                if matchingIndex != requestingIndex {
                    if matchingIndex != nil {
                        signalInboundDataAvailableToPatterns = true
                    } else {
                        signalInboundDataAvailableToDefault = true
                    }
                }
            }

            if signalInboundDataAvailableToPatterns {
                for i in 0..<demuxEntries.count {
                    if !demuxEntries[i].inboundFrames.isEmpty {
                        demuxEntries[i].upper.deliverInboundDataAvailableEvent(state: &context.state, self.reference)
                    }
                }
            }

            if signalInboundDataAvailableToDefault {
                defaultUpper.deliverInboundDataAvailableEvent(state: &context.state, self.reference)
            }

            // Return frames for the requesting index
            return serviceInboundFrames(
                from,
                maximumDatagramCount: maximumDatagramCount,
                requestingIndex: &requestingIndex
            )
        }

        public func getDatagramsToSend(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            maximumDatagramCount: Int,
            minimumDatagramSize: Int
        ) throws(NetworkError) -> FrameArray? {
            do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
            return try lower.invokeGetDatagramsToSend(state: &context.state, 
                self.reference,
                maximumDatagramCount: maximumDatagramCount,
                minimumDatagramSize: minimumDatagramSize
            )
        }

        public func sendDatagrams(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            datagrams: consuming FrameArray
        ) throws(NetworkError) {
            do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
            try lower.invokeSendDatagrams(state: &context.state, self.reference, datagrams: datagrams)
        }

        public func detach(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) throws(NetworkError) {
            do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
            var shouldTeardown: Bool
            if from == defaultUpper.reference {
                shouldTeardown = true
            } else {
                for i in 0..<demuxEntries.count {
                    if demuxEntries[i].upper.reference == from {
                        demuxEntries[i].upper = .init(reference: .init())
                        demuxEntries[i].inboundFrames.finalizeAllFramesAsFailed()
                        demuxEntries.remove(at: i)
                        break
                    }
                }

                shouldTeardown = (defaultUpper.isDetached && demuxEntries.isEmpty)
            }

            guard shouldTeardown else { return }

            defaultUpper = .init(reference: .init())
            defaultInboundFrames.finalizeAllFramesAsFailed()
            for i in 0..<demuxEntries.count {
                demuxEntries[i].upper = .init(reference: .init())
                demuxEntries[i].inboundFrames.finalizeAllFramesAsFailed()
            }
            try lower.invokeDetach(state: &context.state, self.reference)
            lower = .init(reference: .init())
        }

        public func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
            do { try validate(upper: from, #function) } catch { return }
            if from == defaultUpper.reference {

                if lower.isConnected(state: &context.state) {
                    if canCallConnect(state: &context.state, requested: true) {
                        defaultUpper.deliverConnectedEvent(state: &context.state, self.reference)
                    }
                } else {
                    connectRequested(state: &context.state)
                    lower.invokeConnect(state: &context.state, self.reference)
                }
            } else {
                // Just reply connected to the non-default cases
                from.deliverEventToUpperProtocol(state: &context.state, event: .connected(self.reference, from))
            }
        }

        public func disconnect(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            error: NetworkError?
        ) {
            do { try validate(upper: from, #function) } catch { return }

            if from == defaultUpper.reference {
                if canCallDisconnect(state: &context.state) {
                    lower.invokeDisconnect(state: &context.state, self.reference, error: error)
                }
            } else {
                // Just reply disconnected to the non-default cases
                from.deliverEventToUpperProtocol(state: &context.state, event: .disconnected(self.reference, from, error: error))
            }
        }

        public func handleApplicationEvent(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            event: ApplicationEvent
        ) {
            // Don't validate upper, can pass through
            lower.invokeApplicationEvent(state: &context.state, from, event: event)
        }

        public func getMetadata<P>(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference
        ) -> ProtocolMetadata<P>? where P: NetworkProtocol {
            do { try validate(upper: from, #function) } catch { return nil }
            return lower.invokeGetMetadata(state: &context.state, self.reference)
        }

        public func getMetrics(
            state: inout NetworkContext.State,
            _ from: ProtocolInstanceReference,
            requestedNetworkMetric: RequestedNetworkMetrics
        ) -> NetworkMetrics? {
            lower.invokeGetMetrics(state: &context.state, 
                self.reference,
                requestedNetworkMetric: requestedNetworkMetric
            )
        }

        // Events from lower

        public func handleConnectedEvent(_ from: ProtocolInstanceReference) {
            do { try validate(lower: from, #function) } catch { return }
            if canCallConnect(state: &context.state, requested: false) {
                defaultUpper.deliverConnectedEvent(state: &context.state, self.reference)
            }
        }

        public func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
            do { try validate(lower: from, #function) } catch { return }
            for i in 0..<demuxEntries.count {
                demuxEntries[i].upper.deliverDisconnectedEvent(state: &context.state, self.reference, error: error)
            }

            // Pass through disconnected up to the default protocol
            defaultUpper.deliverDisconnectedEvent(state: &context.state, self.reference, error: error)
        }

        public func handleInboundDataAvailableEvent(_ from: ProtocolInstanceReference) {
            do { try validate(lower: from, #function) } catch { return }

            defaultUpper.deliverInboundDataAvailableEvent(state: &context.state, self.reference)
            for i in 0..<demuxEntries.count {
                demuxEntries[i].upper.deliverInboundDataAvailableEvent(state: &context.state, self.reference)
            }
        }

        public func handleOutboundRoomAvailableEvent(_ from: ProtocolInstanceReference) {
            do { try validate(lower: from, #function) } catch { return }
            defaultUpper.deliverOutboundRoomAvailableEvent(state: &context.state, self.reference)
            for i in 0..<demuxEntries.count {
                demuxEntries[i].upper.deliverOutboundRoomAvailableEvent(state: &context.state, self.reference)
            }
        }

        public func handleNetworkProtocolEvent(_ from: ProtocolInstanceReference, event: NetworkProtocolEvent) {
            // Don't validate lower, can pass through
            defaultUpper.deliverNetworkProtocolEvent(
                state: &context.state,
                originalReference: from,
                selfReference: self.reference,
                event: event
            )
            for i in 0..<demuxEntries.count {
                demuxEntries[i].upper.deliverNetworkProtocolEvent(
                    state: &context.state,
                    originalReference: from,
                    selfReference: self.reference,
                    event: event
                )
            }
        }
    }

    public init() {}
    public func newPerProtocolOptions() -> DemuxOptions? { DemuxOptions() }
    public func newPerProtocolOptions(from existing: DemuxOptions) -> DemuxOptions { existing }
    public func newPerProtocolOptions(from serializedBytes: [UInt8]) -> DemuxOptions? {
        DemuxOptions(from: serializedBytes)
    }
    public func newPerProtocolMetadata() -> DemuxMetadata? { DemuxMetadata() }
    public func newProtocolInstance(context: NetworkContext) -> ProtocolInstanceReference? {
        DemuxInstance(context: context).reference
    }

    static let identifier = ProtocolIdentifier(name: "demux", level: .link, mapping: .oneToOne)
    static let definition = ProtocolDefinition<DemuxProtocol>(identifier: identifier)

    static public func options() -> ProtocolOptions<DemuxProtocol> {
        DemuxProtocol.definition.protocolOptions()
    }

    static public func instance(context: NetworkContext) -> ProtocolInstanceReference {
        DemuxProtocol().newProtocolInstance(context: context)!
    }
}

@_spi(Essentials)
@available(Network 0.1.0, *)
extension ProtocolOptions<DemuxProtocol> {
    public func addPattern(_ pattern: RawSpan, at offset: Int, mask: RawSpan? = nil) throws(DemuxError) {
        try perProtocolOptions!.addPattern(pattern, at: offset, mask: mask)
    }
}
