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

#if canImport(BasicContainers)
import BasicContainers
internal import DequeModule
#endif

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(Musl)
import Musl
internal import Logging
#elseif canImport(os)
internal import os
#endif

#if !NETWORK_NO_TESTING_HARNESS

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol UpperHarnessProtocol: TopDatapathProtocol, LoggableProtocol {
    /// Metadata handed over by the new inbound flow event that created this harness.
    var flowMetadata: AbstractProtocolMetadata? { get set }
    func teardown()
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class UpperHarness<LinkageFamily: DataLinkageFamily>: UpperHarnessProtocol {
    public typealias LinkageType = LinkageFamily.Upper
    public typealias LowerProtocol = LinkageFamily.Lower

    // Completions: called once!
    public struct Completions {
        public var connected: ((Bool) -> Void)?
        public var disconnected: (() -> Void)?

        // true when inbound data is available, false when disconnected. The completion runs
        // inline while the event's context state is held, so it receives that state and must
        // thread it into any reads rather than re-deriving it.
        public var inboundDataAvailable: ((inout NetworkContext.State, Bool) -> Void)?

        public var inboundAborted: ((NetworkError?) -> Void)?
        public var outboundAborted: ((NetworkError?) -> Void)?
        public var error: ((NetworkError) -> Void)?  // invoked when error detected
        public var earlyDataRejected: (() -> Void)?
        public var receivedRemoteTransportParameters: (([UInt8]) -> Void)?
        public init() {}
    }
    public var completions = Completions()

    var inboundDataAvailableReceived = false

    public var receivedConnected = false
    public var receivedDisconnected = false

    public var log = NetworkLoggerState()

    public fileprivate(set) var context: NetworkContext

    public var reference: ProtocolInstanceReference

    public var lower = LowerProtocol()

    public var eventManager = ProtocolEventManager()
    // Metadata passed in by the new inbound flow event when a new flow is created.
    public var flowMetadata: AbstractProtocolMetadata?

    var local: Endpoint
    var remote: Endpoint
    var parameters: Parameters
    var path: PathProperties

    public init(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) {
        self.context = context
        self.local = local
        self.remote = remote
        self.parameters = parameters
        self.path = path
        log.logPrefix = "[UpperHarness:\(identifier)]"
        reference = .init(context: context, eventManager: &self.eventManager)
    }

    /// Creates a harness using a context state the caller already holds.
    ///
    /// Use this when building a harness from inside a call that carries the state, such as
    /// handling a new inbound flow, so registering the reference doesn't re-derive it.
    public required init(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext,
        state: inout NetworkContext.State
    ) {
        self.context = context
        self.local = local
        self.remote = remote
        self.parameters = parameters
        self.path = path
        log.logPrefix = "[UpperHarness:\(identifier)]"
        reference = .init(eventManager: &self.eventManager, context: context, state: &state)
    }

    public func handleConnectedEvent(state: inout NetworkContext.State) {
        log.debug("Received connected event")
        self.receivedConnected = true
        if let completion = completions.connected {
            completion(true)
            self.completions.connected = nil
        }
    }

    public func handleDisconnectedEvent(state: inout NetworkContext.State, error: NetworkError?) {
        log.debug("Received disconnected event, error \(error.debugDescription)")
        receivedDisconnected = true
        if let completion = completions.connected {
            completion(false)
            self.completions.connected = nil
        }
        if let completion = completions.disconnected {
            completion()
            self.completions.disconnected = nil
        }
        if let error, let errorCompletion = self.completions.error {
            errorCompletion(error)
            self.completions.error = nil
        }

        if let inboundDataAvailableCompletion = self.completions.inboundDataAvailable {
            inboundDataAvailableCompletion(&state, false)
            self.completions.inboundDataAvailable = nil
        }
    }

    public func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {
        if let inboundDataAvailableCompletion = self.completions.inboundDataAvailable {
            self.completions.inboundDataAvailable = nil
            inboundDataAvailableCompletion(&state, true)
        } else {
            self.inboundDataAvailableReceived = true
        }
    }

    public func handleOutboundRoomAvailableEvent(state: inout NetworkContext.State) {
    }

    public func handleNetworkProtocolEvent(state: inout NetworkContext.State, _ event: NetworkProtocolEvent) {
        log.debug("Received network protocol event: \(event)")
        if let quicEvent = event.quicEvent {
            switch quicEvent {
            case .earlyDataRejected:
                if let earlyDataRejectedCompletion = self.completions.earlyDataRejected {
                    self.completions.earlyDataRejected = nil
                    earlyDataRejectedCompletion()
                }
            case .receivedRemoteTransportParameters(let transportParameters):
                if let transportParametersCompletion = self.completions.receivedRemoteTransportParameters {
                    self.completions.receivedRemoteTransportParameters = nil
                    transportParametersCompletion(transportParameters)
                }
            default: break
            }
        }
    }

    public func start() {
        invokeConnect()
    }

    public func start(_ completion: @escaping (Bool) -> Void) {
        self.completions.connected = completion
        start()
    }

    public func stop(error: NetworkError? = nil) {
        invokeDisconnect(error: error)
    }

    /// Stops using a context state the caller already holds.
    public func stop(state: inout NetworkContext.State, error: NetworkError? = nil) {
        invokeDisconnect(state: &state, error: error)
    }

    public func teardown() {
        do throws(NetworkError) {
            var mutatingSelf = self
            try mutatingSelf.invokeDetach()
        } catch {
            log.error("Failed to detach lower protocol: \(error)")
        }
    }

    public func waitForInboundDataAvailable(
        completion: @escaping (inout NetworkContext.State, Bool) -> Void
    ) {
        if self.inboundDataAvailableReceived {
            // Received inbound data available, but didn't deliver. Fire now. This is an
            // external entry point, so acquire the state for the completion.
            self.inboundDataAvailableReceived = false
            fromExternal { state in
                completion(&state, true)
            }
            return
        }
        completions.inboundDataAvailable = completion
    }

    /// Registers a completion that does not need the context state.
    public func waitForInboundDataAvailable(completion: @escaping (Bool) -> Void) {
        waitForInboundDataAvailable { _, available in completion(available) }
    }

    public func waitForDisconnected(completion: @escaping () -> Void) {
        if receivedDisconnected {
            completion()
            return
        }
        completions.disconnected = completion
    }

    public func waitForError(completion: @escaping (NetworkError?) -> Void) {
        completions.error = completion
    }

    final public func getMetadata<P: NetworkProtocol>() -> ProtocolMetadata<P>? {
        fromExternal { state in
            guard let metadata = lower.invokeGetMetadata(state: &state, reference) as? ProtocolMetadata<P> else {
                return nil
            }
            return metadata
        }
    }

    final public func getMetrics(requestedNetworkMetric: RequestedNetworkMetrics) -> NetworkMetrics? {
        fromExternal { state in
            lower.invokeGetMetrics(state: &state, reference, requestedNetworkMetric: requestedNetworkMetric)
        }
    }

    public func invokeDataStallEvent() {
        invokeApplicationEvent(.dataStall)
    }

    public func invokeConnectionIdleEvent() {
        invokeApplicationEvent(.connectionIdle)
    }

    public func invokeConnectionReusedEvent() {
        invokeApplicationEvent(.connectionReused)
    }

    public func invokeApplicationEvent(_ event: ApplicationEvent) {
        fromExternal { state in
            lower.invokeApplicationEvent(state: &state, reference, event: event)
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class DatagramUpperHarness<LinkageFamily: DatagramLinkageFamily>: UpperHarness<LinkageFamily>, TopDatagramProtocol {
    public func write(_ datagram: [UInt8]) -> Bool {
        fromExternal { state in
            write(state: &state, datagram)
        }
    }

    /// Writes using a context state the caller already holds.
    public func write(state: inout NetworkContext.State, _ datagram: [UInt8]) -> Bool {
        do throws(NetworkError) {
            let frames = try invokeGetDatagramsToSend(
                state: &state,
                maximumDatagramCount: 1,
                minimumDatagramSize: datagram.count
            )
            guard var frames = frames else {
                log.error("Failed to get datagram to send")
                return false
            }
            frames.iterateMutableFrames { frame in
                let result = Serializer.serialize(&frame, claim: true) { write throws(SerializationError) in
                    try write.buffer(datagram)
                }
                log.debug("Write result: \(result)")
                frame.collapse()
                if !frame.unclaim(fromStart: datagram.count) {
                    log.error("Failed to unclaim")
                }
                return false
            }
            try invokeSendDatagrams(state: &state, frames)
            return true
        } catch {
            return false
        }
    }

    public func read() -> [UInt8]? {
        fromExternal { state in
            read(state: &state)
        }
    }

    /// Reads using a context state the caller already holds.
    ///
    /// Inbound-data completions run inline while the delivering event holds the state, so they
    /// have to use this rather than `read()`.
    public func read(state: inout NetworkContext.State) -> [UInt8]? {
        do throws(NetworkError) {
            let frames = try invokeReceiveDatagrams(state: &state, maximumDatagramCount: 1)
            guard var frames = frames else {
                log.debug("Failed to receive datagrams")
                return nil
            }
            var returnBuffer: [UInt8]? = nil
            frames.iterateMutableFrames { frame in
                var buffer = [UInt8]()
                let length = frame.unclaimedLength
                if length > 0 {
                    _ = Deserializer.deserialize(&frame, claim: false) { read throws(DeserializationError) in
                        try read.buffer(&buffer, length: length)
                    }
                }
                returnBuffer = buffer
                frame.finalize(success: true)
                return true
            }
            return returnBuffer
        } catch {
            return nil
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class StreamUpperHarness<LinkageFamily: StreamLinkageFamily>: UpperHarness<LinkageFamily>, TopStreamProtocol {

    public func handleInboundAbortedEvent(state: inout NetworkContext.State, error: NetworkError?) {
        log.debug("Received inbound aborted event: \(error?.description ?? "no error")")
        self.inboundAborted = true
        self.inboundAbortError = error
        if let inboundAbortedCompletion = self.completions.inboundAborted {
            self.completions.inboundAborted = nil
            inboundAbortedCompletion(self.inboundAbortError)
        }
    }
    public func handleOutboundAbortedEvent(state: inout NetworkContext.State, error: NetworkError?) {
        log.debug("Received outbound aborted event: \(error?.description ?? "no error")")
        self.outboundAborted = true
        self.outboundAbortError = error
        if let inboundAbortedCompletion = self.completions.outboundAborted {
            self.completions.inboundAborted = nil
            inboundAbortedCompletion(self.outboundAbortError)
        }
    }

    var inboundAborted = false
    var outboundAborted = false
    var inboundAbortError: NetworkError?
    var outboundAbortError: NetworkError?

    public func waitForInboundAborted(completion: @escaping (NetworkError?) -> Void) {
        if self.inboundAborted {
            completion(self.inboundAbortError)
            return
        }
        completions.inboundAborted = completion
    }

    public func waitForOutboundAborted(completion: @escaping (NetworkError?) -> Void) {
        if self.outboundAborted {
            completion(self.outboundAbortError)
            return
        }
        completions.outboundAborted = completion
    }

    public func write(_ bytes: [UInt8], sendFIN: Bool = false, earlyData: Bool = false) -> Bool {
        fromExternal { state in
            write(state: &state, bytes, sendFIN: sendFIN, earlyData: earlyData)
        }
    }

    /// Writes using a context state the caller already holds.
    public func write(
        state: inout NetworkContext.State,
        _ bytes: [UInt8],
        sendFIN: Bool = false,
        earlyData: Bool = false
    ) -> Bool {
        do throws(NetworkError) {
            var frame = Frame(count: bytes.count)
            let result = Serializer.serialize(&frame, claim: false) { write throws(SerializationError) in
                try write.span(bytes.span.bytes)
            }
            guard result.isValid else {
                Logger.proto.error("Serializing to frame failed")
                return false
            }
            if sendFIN {
                frame.metadataComplete = true
                frame.connectionComplete = true
            }
            if earlyData {
                try invokeSendEarlyStreamData(state: &state, .init(frame: frame))
            } else {
                try invokeSendStreamData(state: &state, .init(frame: frame))
            }
            return true
        } catch {
            return false
        }
    }

    public var receivedFIN: Bool = false

    public func readAndDrop(upTo maximumBytes: Int = Int.max) -> Int {
        do throws(NetworkError) {
            guard var frames = try invokeReceiveStreamData(minimumBytes: 1, maximumBytes: maximumBytes) else {
                return 0
            }
            var bytesRead = 0
            frames.iterateMutableFrames { frame in
                let length = frame.unclaimedLength
                let fin = frame.connectionComplete
                bytesRead += length
                if fin {
                    self.receivedFIN = true
                }
                frame.finalize(success: true)
                return true
            }
            return bytesRead
        } catch {
            return 0
        }
    }

    public func read(upTo maximumBytes: Int = Int.max) -> [UInt8]? {
        fromExternal { state in
            read(state: &state, upTo: maximumBytes)
        }
    }

    /// Reads using a context state the caller already holds.
    ///
    /// Inbound-data completions run inline while the delivering event holds the state, so they
    /// have to use this rather than `read(upTo:)`.
    public func read(state: inout NetworkContext.State, upTo maximumBytes: Int = Int.max) -> [UInt8]? {
        do throws(NetworkError) {
            guard
                var frames = try invokeReceiveStreamData(
                    state: &state,
                    minimumBytes: 1,
                    maximumBytes: maximumBytes
                )
            else {
                return nil
            }
            var returnBuffer: [UInt8]? = nil
            frames.iterateMutableFrames { frame in
                var buffer = [UInt8]()
                let length = frame.unclaimedLength
                let fin = frame.connectionComplete
                if length > 0 {
                    _ = Deserializer.deserialize(&frame, claim: false) { read throws(DeserializationError) in
                        try read.buffer(&buffer, length: length)
                    }
                }
                if fin {
                    self.receivedFIN = true
                }
                if returnBuffer == nil {
                    returnBuffer = buffer
                } else {
                    returnBuffer?.append(contentsOf: buffer)
                }
                frame.finalize(success: true)
                return true
            }
            return returnBuffer
        } catch {
            return nil
        }
    }

    public func abortInbound(error: NetworkError?) {
        fromExternal { state in
            do throws(NetworkError) {
                try lower.invokeAbortInbound(state: &state, reference, error: error)
            } catch {
                log.error("Failed to abort inbound: \(error)")
            }
        }
    }

    public func abortOutbound(error: NetworkError?) {
        fromExternal { state in
            do throws(NetworkError) {
                try lower.invokeAbortOutbound(state: &state, reference, error: error)
            } catch {
                log.error("Failed to abort outbound: \(error)")
            }
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class LowerHarness<LinkageFamily: DataLinkageFamily>: BottomProtocolHandler, LoggableProtocol {
    public typealias UpperProtocol = LinkageFamily.Upper
    public typealias LinkageType = LinkageFamily.Lower

    public var log = NetworkLoggerState()
    public private(set) var context: NetworkContext

    public var reference: ProtocolInstanceReference
    public var upper = UpperProtocol()

    public var eventManager = ProtocolEventManager()

    var pendingOutboundPackets = FrameArray()
    var pendingInboundPackets = FrameArray()

    public init(
        identifier: String = "",
        context: NetworkContext
    ) {
        log.logPrefix = "[LowerHarness:\(identifier)]"
        self.context = context
        reference = .init(context: context, eventManager: &self.eventManager)
    }

    public func flushPackets() {
        pendingOutboundPackets.finalizeAllFramesAsFailed()
    }

    public func teardown() {
        log.debug("Received teardown")
        flushPackets()
    }

    func extractLastOutboundBytes() -> UniqueArray<UInt8>? {
        guard var frame = pendingOutboundPackets.popFirst() else {
            return nil
        }
        return frame.extractBytes()
    }

    public func extractLastOutboundPacket() -> [UInt8]? {
        guard let bytes = extractLastOutboundBytes() else {
            return nil
        }
        return [UInt8](copying: bytes.span, maxCount: bytes.count)
    }

    public var hasOutboundPackets: Bool {
        !pendingOutboundPackets.isEmpty
    }

    func setNextInboundPacketBytes(_ bytes: consuming UniqueArray<UInt8>, sendAvailableEvent: Bool = true) {
        pendingInboundPackets.add(frame: .init(bytes: bytes))
        if sendAvailableEvent {
            deliverInboundDataAvailableEvent()
        }
    }

    public func setNextInboundPacket(_ packet: [UInt8], sendAvailableEvent: Bool = true) {
        pendingInboundPackets.add(frame: .init(copyBuffer: packet))
        if sendAvailableEvent {
            deliverInboundDataAvailableEvent()
        }
    }

    public func setNextInboundPacket(from: LowerHarness, sendAvailableEvent: Bool = true) -> Bool {
        guard let bytes = from.extractLastOutboundBytes() else {
            return false
        }
        setNextInboundPacketBytes(bytes, sendAvailableEvent: sendAvailableEvent)
        return true
    }

    public func deliverViableEvent() {
        deliverNetworkProtocolEvent(.viabilityChanged(isViable: true))
    }

    public func deliverPathIsPrimary() {
        deliverNetworkProtocolEvent(.pathIsPrimary)
    }

    public func deliverPathIsNotPrimary() {
        deliverNetworkProtocolEvent(.pathIsNotPrimary)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class DatagramLowerHarness<LinkageFamily: DatagramLinkageFamily>: LowerHarness<LinkageFamily>, BottomDatagramProtocol {
    
    public var maximumOutputSize = 1500

    public func receiveDatagrams(
        state: inout NetworkContext.State,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        let array = pendingInboundPackets.drainArray(maximumFrameCount: maximumDatagramCount)
        log.debug("Deliver inbound datagram count: \(array.count)")
        return array
    }

    public func getDatagramsToSend(
        state: inout NetworkContext.State,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        let frameSize = min(minimumDatagramSize, self.maximumOutputSize)
        var frameArray = FrameArray(capacity: maximumDatagramCount)
        for _ in 0..<maximumDatagramCount {
            let frame = Frame(count: frameSize)
            frameArray.add(frame: frame)
        }
        return frameArray
    }

    public func sendDatagrams(
        state: inout NetworkContext.State,
        _ datagrams: consuming FrameArray
    ) throws(NetworkError) {
        pendingOutboundPackets.add(frames: datagrams)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class StreamLowerHarness<LinkageFamily: StreamLinkageFamily>: LowerHarness<LinkageFamily>, BottomStreamProtocol {

    public func receiveStreamData(
        state: inout NetworkContext.State,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        pendingInboundPackets.drainArray(maximumByteCount: maximumBytes)
    }

    public func getOutboundStreamDataRoomAvailable(
        state: inout NetworkContext.State
    ) throws(NetworkError) -> Int {
        Int.max
    }

    public func sendStreamData(
        state: inout NetworkContext.State,
        _ streamData: consuming FrameArray
    ) throws(NetworkError) {
        pendingOutboundPackets.add(frames: streamData)
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class NewFlowHarness<LinkageFamily: DataLinkageFamily, HarnessType: UpperHarnessProtocol>: InboundFlowHandler,
    LoggableProtocol
where
    // The harness this one creates per inbound flow sits on the flow linkage that the listener
    // hands back, so its lower protocol has to be the family's own data linkage. Stating it
    // here is what lets `attachUpperProtocolToExistingFlow`'s result be assigned to the new
    // harness's `lower`.
    LinkageFamily.Listener.PairedUpperLinkage.DataLinkage == LinkageFamily.Lower,
    HarnessType.LowerProtocol == LinkageFamily.Lower,
    HarnessType.LinkageType == LinkageFamily.Upper
{
    public typealias LowerProtocol = LinkageFamily.Listener
    typealias HarnessType = HarnessType

    public var eventManager = ProtocolEventManager()

    public var log = NetworkLoggerState()
    public private(set) var context: NetworkContext

    public var reference: ProtocolInstanceReference
    var lower = LowerProtocol()

    public var upperHarnesses: [HarnessType] = []

    var local: Endpoint
    var remote: Endpoint
    var parameters: Parameters
    var path: PathProperties

    public struct Completions {
        var createNewFlowHandler: ((inout NetworkContext.State) -> (HarnessType, HarnessType.LinkageType))?
        public var connected: ((Bool) -> Void)?
        public var disconnected: (() -> Void)?
        var newFlow = Deque<(() -> Void)>()
        public var error: ((NetworkError) -> Void)?  // invoked when error detected
        public init() {}
    }
    public var completions: Completions = .init()

    public var receivedConnected = false
    public var receivedDisconnected = false

    public func attachLowerProtocol(
        _ lowerProtocol: LowerProtocol,
    ) throws(NetworkError) -> LowerProtocol.PairedUpperLinkage? {
        guard lower.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        lower = lowerProtocol
        return nil
    }

    public func handleConnectedEvent(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        log.debug("Received connected event")
        self.receivedConnected = true
        if let completion = completions.connected {
            completion(true)
            self.completions.connected = nil
        }
    }

    public func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    ) {
        log.debug("Received disconnected event, \(error?.description ?? "<no error>")")
        receivedDisconnected = true
        if let completion = completions.connected {
            completion(false)
            self.completions.connected = nil
        }
        if let completion = completions.disconnected {
            completion()
            self.completions.disconnected = nil
        }
        if let error, let errorCompletion = self.completions.error {
            errorCompletion(error)
            self.completions.error = nil
        }
    }

    public func handleNewInboundFlowEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        log.debug(
            "Received new inbound flow event with reference \(flowReference) with flowMetadata: \(flowMetadata.debugDescription)"
        )
        guard let createNewFlowHandler = completions.createNewFlowHandler else {
            log.error("Received new inbound flow event but no handler was set")
            return
        }
        do throws(NetworkError) {
            var (newUpperHarness, upperLinkage) = createNewFlowHandler(&state)
            newUpperHarness.lower = try lower.invokeAttachUpperProtocolToExistingFlow(upperLinkage, existingFlowReference: flowReference)
            upperHarnesses.append(newUpperHarness)
            newUpperHarness.flowMetadata = flowMetadata
            newUpperHarness.invokeConnect(state: &state)
            if let newFlowCompletion = completions.newFlow.popFirst() {
                newFlowCompletion()
            }
        } catch {
            log.error("Failed to attach new inbound flow")
            return
        }
    }


    public var newInboundCIDEventCount = 0
    public var newOutboundCIDEventCount = 0
    public func handleNetworkProtocolEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: NetworkProtocolEvent
    ) {
        log.debug("Received network protocol event: \(event)")
        #if !NETWORK_NO_SWIFT_QUIC
        if let quicEvent = event.quicEvent {
            switch quicEvent {
            case .newInboundConnectionID: newInboundCIDEventCount += 1
            case .newOutboundConnectionID: newOutboundCIDEventCount += 1
            default: break
            }
        }
        #endif
    }

    public func teardown() {
        for upperHarness in upperHarnesses {
            upperHarness.teardown()
        }
        upperHarnesses.removeAll()
        fromExternal { state in
            do throws(NetworkError) {
                try lower.invokeDetach(state: &state, reference)
                lower = .init()
            } catch {
                log.error("Failed to detach lower protocol: \(error)")
            }
        }
    }

    public init(
        identifier: String = "",
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext,
        createNewFlowHandler: @escaping ((inout NetworkContext.State) -> (HarnessType, HarnessType.LinkageType))
    ) {
        log.logPrefix = "[NewFlowHarness:\(identifier)]"
        self.context = context
        self.local = local
        self.remote = remote
        self.parameters = parameters
        self.path = path
        reference = .init(context: context, eventManager: &self.eventManager)
        completions.createNewFlowHandler = createNewFlowHandler
    }

    public func waitForDisconnected(completion: @escaping () -> Void) {
        if receivedDisconnected {
            completion()
            return
        }
        completions.disconnected = completion
    }

    public func waitForError(completion: @escaping (NetworkError?) -> Void) {
        completions.error = completion
    }

    public func start() {
        fromExternal { state in
            lower.invokeConnect(state: &state, reference)
        }
    }

    public func start(_ completion: @escaping (Bool) -> Void) {
        completions.connected = completion
        start()
    }

    public func stop(error: NetworkError? = nil) {
        fromExternal { state in
            lower.invokeDisconnect(state: &state, reference, error: error)
        }
    }

    public func waitForNewFlow(completion: @escaping () -> Void) {
        completions.newFlow.append(completion)
    }

    public func invokeApplicationEvent(_ event: ApplicationEvent) {
        fromExternal { state in
            lower.invokeApplicationEvent(state: &state, reference, event: event)
        }
    }

    final public func getMetadata<P: NetworkProtocol>() -> ProtocolMetadata<P>? {
        fromExternal { state in
            guard let metadata = lower.invokeGetMetadata(state: &state, reference) as? ProtocolMetadata<P> else {
                return nil
            }
            return metadata
        }
    }

    final public func getMetrics(requestedNetworkMetric: RequestedNetworkMetrics) -> NetworkMetrics? {
        fromExternal { state in
            lower.invokeGetMetrics(state: &state, reference, requestedNetworkMetric: requestedNetworkMetric)
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class NewDatagramFlowHarness<LinkageFamily: DatagramLinkageFamily>: NewFlowHarness<LinkageFamily, DatagramUpperHarness<LinkageFamily>> { }

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public class NewStreamFlowHarness<LinkageFamily: StreamLinkageFamily>: NewFlowHarness<LinkageFamily, StreamUpperHarness<LinkageFamily>> { }

#endif
