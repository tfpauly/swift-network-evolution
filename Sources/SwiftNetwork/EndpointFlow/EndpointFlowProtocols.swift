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

@available(Network 0.1.0, *)
class EndpointFlowProtocol<LinkageFamily: DataLinkageFamily>: TopDatapathProtocol {
    typealias LinkageFamily = LinkageFamily
    typealias LowerProtocol = LinkageFamily.Lower

    // Completions: called once!
    struct Completions {
        public var connected: ((NetworkError?) -> Void)?
        public var outputRoomAvailable: (() -> Void)?

        // true when inbound data is available, false when disconnected
        public var inboundDataAvailable: ((Bool) -> Void)?

        // invoked when error detected
        public var error: ((NetworkError) -> Void)?

        // invoked when remote peer disconnects
        public var disconnected: ((NetworkError) -> Void)?
        public init() {}
    }
    var completions = Completions()

    var log = NetworkLoggerState()

    fileprivate(set) var context: NetworkContext

    let reference: ProtocolInstanceReference
    var lower = LowerProtocol()

    var eventManager = ProtocolEventManager()

    var local: Endpoint?
    var remote: Endpoint
    var parameters: Parameters
    var path: PathProperties

    init(
        identifier: String = "",
        local: Endpoint?,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        context: NetworkContext
    ) throws(NetworkError) {
        log.logPrefix = "[EndpointFlowProtocol:\(identifier)]"
        self.context = context
        self.local = local
        self.remote = remote
        self.parameters = parameters
        self.path = path
        reference = .init(context: context, eventManager: &self.eventManager)
    }

    func handleConnectedEvent(state: inout NetworkContext.State) {
        log.debug("Received connected event")
        if let completion = completions.connected {
            completion(nil)
            self.completions.connected = nil
        }
    }

    func handleDisconnectedEvent(
        state: inout NetworkContext.State,
        error: NetworkError?
    ) {
        log.debug("Received disconnected event")
        let disconnectError = error ?? .posix(ENOTCONN)
        if let completion = completions.connected {
            completion(disconnectError)
            self.completions.connected = nil
        }
        if let error, let errorCompletion = self.completions.error {
            errorCompletion(error)
            self.completions.error = nil
        }

        if let inboundDataAvailableCompletion = self.completions.inboundDataAvailable {
            inboundDataAvailableCompletion(false)
            self.completions.inboundDataAvailable = nil
        }

        if let disconnectedCompletion = self.completions.disconnected {
            disconnectedCompletion(disconnectError)
            self.completions.disconnected = nil
        }
    }

    func handleInboundDataAvailableEvent(state: inout NetworkContext.State) {
        log.debug("Received inbound data available event")
        // Clear the slot before invoking: the completion may synchronously
        // re-arm the waiter (when receiveStreamData returns nil because the
        // requested minimum spans more than one segment). Clearing afterwards
        // would clobber that re-registration and drop later notifications.
        if let inboundDataAvailableCompletion = self.completions.inboundDataAvailable {
            self.completions.inboundDataAvailable = nil
            inboundDataAvailableCompletion(true)
        }
    }

    public func handleOutboundRoomAvailableEvent(
        state: inout NetworkContext.State,
    ) {
        log.debug("Received outbound room available event")
        if let completion = self.completions.outputRoomAvailable {
            completion()
            self.completions.outputRoomAvailable = nil
        }
    }

    public func start() {
        log.debug("Starting flow")
        invokeConnect()

    }

    public func start(_ completion: @escaping (NetworkError?) -> Void) {
        self.completions.connected = completion
        start()
    }

    public func stop() {
        log.debug("Stopping flow")
        invokeDisconnect(error: nil)
    }

    public func teardown() {
        log.debug("Tearing down flow")
        fromExternal { state in
            do throws(NetworkError) {
                try lower.invokeDetach(state: &state, reference)
                lower = .init()
            } catch {
                log.error("Failed to detach lower protocol: \(error)")
            }
        }
    }

    public func abort(error: NetworkError? = nil) {
        log.debug("Aborting flow")
        invokeDisconnect(error: error)
    }

    public func waitForOutputRoomAvailable(_ completion: @escaping () -> Void) {
        completions.outputRoomAvailable = completion
    }

    public func waitForInboundDataAvailable(completion: @escaping (Bool) -> Void) {
        completions.inboundDataAvailable = completion
    }

    public func waitForError(completion: @escaping (NetworkError?) -> Void) {
        completions.error = completion
    }

    public func waitForDisconnected(completion: @escaping (NetworkError) -> Void) {
        completions.disconnected = completion
    }
}

@available(Network 0.1.0, *)
final class DatagramEndpointFlowProtocol<LinkageFamily: DatagramLinkageFamily>: EndpointFlowProtocol<LinkageFamily>, TopDatagramProtocol {

    func write(_ datagram: consuming Frame) -> Bool {
        fromExternal { state in
            do throws(NetworkError) {
                let length = datagram.unclaimedLength
                let frames = try lower.invokeGetDatagramsToSend(state: &state, reference,
                    maximumDatagramCount: 1,
                    minimumDatagramSize: length
                )
                guard var frames = frames else {
                    log.error("Failed to get datagram to send")
                    return false
                }
                frames.iterateMutableFrames { frame in
                    let copiedLength = datagram.copyInto(&frame, length: length)
                    if copiedLength < length {
                        log.error("Failed to copy \(length) bytes, only copied \(copiedLength)")
                    }
                    let frameLength = frame.unclaimedLength
                    if frameLength > copiedLength {
                        _ = frame.collapse(to: copiedLength)
                    }
                    datagram.finalize(success: true)
                    return false
                }
                try lower.invokeSendDatagrams(state: &state, reference, datagrams: frames)
                return true
            } catch {
                return false
            }
        }
    }

    func read() -> [UInt8]? {
        fromExternal { state in
            do throws(NetworkError) {
                let frames = try lower.invokeReceiveDatagrams(state: &state, reference, maximumDatagramCount: 1)
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
}

@available(Network 0.1.0, *)
final class StreamEndpointFlowProtocol<LinkageFamily: StreamLinkageFamily>: EndpointFlowProtocol<LinkageFamily>, TopStreamProtocol {

    override public func abort(error: NetworkError? = nil) {
        log.debug("Aborting flow")
        fromExternal { state in
            do throws(NetworkError) {
                try lower.invokeAbortOutbound(state: &state, reference, error: error)
                try lower.invokeAbortInbound(state: &state, reference, error: error)
            } catch {
                log.error("Failed to abort stream: \(error)")
            }
            lower.invokeDisconnect(state: &state, reference, error: error)
        }
    }

    private func invokeSendStreamData(_ streamData: consuming FrameArray) throws(NetworkError) {
        try fromExternal(streamData) { state, streamData throws(NetworkError) in
            try lower.invokeSendStreamData(state: &state, self.reference, streamData: streamData)
        }
    }

    func getOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int {
        try fromExternal { state throws(NetworkError) in
            try lower.invokeGetOutboundStreamDataRoomAvailable(state: &state, self.reference)
        }
    }

    func write(_ frame: consuming Frame) -> Bool {
        do throws(NetworkError) {
            try invokeSendStreamData(.init(frame: frame))
            return true
        } catch {
            return false
        }
    }

    func read(minimumBytes: Int, maximumBytes: Int) -> [UInt8]? {
        fromExternal { state in
            do throws(NetworkError) {
                guard
                    var frames = try lower.invokeReceiveStreamData(state: &state, reference,
                        minimumBytes: minimumBytes,
                        maximumBytes: maximumBytes
                    )
                else {
                    log.debug("No more stream data available")
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
    }
}
