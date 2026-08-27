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

@available(Network 0.1.0, *)
struct ProtocolEventManagerState: ~Copyable {
    enum EventState {
        case idle
        case handlingCallFromUpperProtocol
        case handlingAsyncCall
        case handlingExternalCall
        case handlingTimerWakeupCall
        case processingEventFromLowerProtocol
    }

    // Connected state only moves forward
    enum ConnectedState: CustomStringConvertible {
        case initial  // Not reported connected or disconnected
        case connected  // Reported connected, won't get a connect call
        case disconnected  // Reported disconnected

        var description: String {
            switch self {
            case .initial: return "initial"
            case .connected: return "connected"
            case .disconnected: return "disconnected"
            }
        }
    }

    // Connect call state only moves forward
    enum ConnectCallState: CustomStringConvertible {
        case initial  // Neither connect nor disconnect called
        case connectRequested  // Connect was previously requested, but not called
        case connectCalled  // Connect was previously called
        case disconnectCalled  // Disconnect was previously called

        var description: String {
            switch self {
            case .initial: return "initial"
            case .connectRequested: return "connectRequested"
            case .connectCalled: return "connectCalled"
            case .disconnectCalled: return "disconnectCalled"
            }
        }
    }

    enum PendingEvent: ~Copyable {
        case connected(_ from: ProtocolInstanceReference, _ to: ProtocolInstanceReference)
        case disconnected(_ from: ProtocolInstanceReference, _ to: ProtocolInstanceReference, error: NetworkError?)
        case inboundDataAvailable(_ from: ProtocolInstanceReference, _ to: ProtocolInstanceReference)
        case outboundRoomAvailable(_ from: ProtocolInstanceReference, _ to: ProtocolInstanceReference)
        case inboundAborted(_ from: ProtocolInstanceReference, _ to: ProtocolInstanceReference, error: NetworkError?)
        case outboundAborted(_ from: ProtocolInstanceReference, _ to: ProtocolInstanceReference, error: NetworkError?)
        case newInboundFlow(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            flowReference: ProtocolInstanceReference,
            flowMetadata: AbstractProtocolMetadata?
        )
        case networkProtocolEvent(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            event: NetworkProtocolEvent
        )

        fileprivate func run() {
            switch self {
            case .connected(let from, let to): to.handleConnectedEvent(from)
            case .disconnected(let from, let to, let error): to.handleDisconnectedEvent(from, error: error)
            case .inboundDataAvailable(let from, let to): to.handleInboundDataAvailableEvent(from)
            case .outboundRoomAvailable(let from, let to): to.handleOutboundRoomAvailableEvent(from)
            case .inboundAborted(let from, let to, let error): to.handleInboundAbortedEvent(from, error: error)
            case .outboundAborted(let from, let to, let error): to.handleOutboundAbortedEvent(from, error: error)
            case .newInboundFlow(let from, let to, let flow, let metadata):
                to.handleNewInboundFlowEvent(from, flowReference: flow, flowMetadata: metadata)
            case .networkProtocolEvent(let from, let to, let event): to.handleNetworkProtocolEvent(from, event: event)
            }
        }

        @inline(always)
        fileprivate var toReference: ProtocolInstanceReference {
            switch self {
            case .connected(_, let to): return to
            case .disconnected(_, let to, _): return to
            case .inboundDataAvailable(_, let to): return to
            case .outboundRoomAvailable(_, let to): return to
            case .inboundAborted(_, let to, _): return to
            case .outboundAborted(_, let to, _): return to
            case .newInboundFlow(_, let to, _, _): return to
            case .networkProtocolEvent(_, let to, _): return to
            }
        }

        fileprivate consuming func deliver(state: inout NetworkContext.State) -> ProtocolInstanceReference {
            let toReference = self.toReference
            if !toReference.isNone {
                toReference.addEventFromLowerProtocol(state: &state, event: self)
            }
            return toReference
        }

        fileprivate consuming func reassign(to newTo: ProtocolInstanceReference) -> PendingEvent {
            switch self {
            case .connected(let from, _): return .connected(from, newTo)
            case .disconnected(let from, _, let error): return .disconnected(from, newTo, error: error)
            case .inboundDataAvailable(let from, _): return .inboundDataAvailable(from, newTo)
            case .outboundRoomAvailable(let from, _): return .outboundRoomAvailable(from, newTo)
            case .inboundAborted(let from, _, let error): return .inboundAborted(from, newTo, error: error)
            case .outboundAborted(let from, _, let error): return .outboundAborted(from, newTo, error: error)
            case .newInboundFlow(let from, _, let flow, let metadata):
                return .newInboundFlow(from, newTo, flowReference: flow, flowMetadata: metadata)
            case .networkProtocolEvent(let from, _, let event): return .networkProtocolEvent(from, newTo, event: event)
            }
        }

        fileprivate var isConnected: Bool {
            switch self {
            case .connected: return true
            default: return false
            }
        }

        fileprivate var isDisconnected: Bool {
            switch self {
            case .disconnected: return true
            default: return false
            }
        }

    }

    mutating func startCallFromUpperProtocol() {
        guard eventState == .idle else {
            fatalError("Illegal state: \(eventState)")
        }
        eventState = .handlingCallFromUpperProtocol
    }

    mutating func finishCallFromUpperProtocol() {
        guard eventState == .handlingCallFromUpperProtocol else {
            fatalError("Illegal state: \(eventState)")
        }
        eventState = .idle
    }

    mutating func startExternalCall() -> Bool {
        guard eventState == .idle else {
            // Don't mark as a fatal error, since this is often used
            // as a guard to ensure that the events will unwind
            return false
        }
        eventState = .handlingExternalCall
        return true
    }

    mutating func finishExternalCall() {
        guard eventState == .handlingExternalCall else {
            // Don't mark as a fatal error, since this is often used
            // as a guard to ensure that the events will unwind
            return
        }
        eventState = .idle
    }

    mutating func addEventFromLowerProtocol(event: consuming PendingEvent) {
        pendingEventsFromLowerProtocol.append(event)
    }

    mutating func startTimerWakeupCall() {
        guard eventState == .idle else {
            fatalError("Illegal state: \(eventState)")
        }
        eventState = .handlingTimerWakeupCall
    }

    mutating func finishTimerWakeupCall() {
        guard eventState == .handlingTimerWakeupCall else {
            fatalError("Illegal state: \(eventState)")
        }
        eventState = .idle
    }

    mutating func startAsyncCall() {
        guard eventState == .idle else {
            fatalError("Illegal state: \(eventState)")
        }
        eventState = .handlingAsyncCall
    }

    mutating func finishAsyncCall() {
        guard eventState == .handlingAsyncCall else {
            fatalError("Illegal state: \(eventState)")
        }
        eventState = .idle
    }

    mutating func startDrainingPendingEventsFromLower(hasNewEvent: Bool = false) -> Int {
        guard eventState == .idle else {
            // Fast exit if we're not fully unwound
            return 0
        }

        guard !pendingEventsFromLowerProtocol.isEmpty else {
            // Fast path case for no pending events
            if hasNewEvent {
                eventState = .processingEventFromLowerProtocol
                return 1
            } else {
                return 0
            }
        }

        eventState = .processingEventFromLowerProtocol
        if hasNewEvent {
            return pendingEventsFromLowerProtocol.count + 1
        } else {
            return pendingEventsFromLowerProtocol.count
        }
    }

    mutating func readPendingEventFromLower() -> PendingEvent {
        pendingEventsFromLowerProtocol.removeFirst()
    }

    mutating func finishDrainingPendingEventsFromLower() {
        guard eventState == .processingEventFromLowerProtocol else {
            fatalError("Illegal state: \(eventState)")
        }
        eventState = .idle
    }

    func countPendingEventsToUpper() -> Int {
        pendingEventsToDeliverToUpperProtocol.count
    }

    mutating func readPendingEventToUpper() -> PendingEvent? {
        pendingEventsToDeliverToUpperProtocol.popFirst()
    }

    mutating func addPendingEventToDeliverToUpperProtocol(_ event: consuming PendingEvent) {
        guard eventState != .idle else {
            fatalError("Illegal state: \(eventState)")
        }
        pendingEventsToDeliverToUpperProtocol.append(event)
    }

    mutating func enqueuePendingEventForUpperProtocol(_ event: consuming PendingEvent) {
        unassignedPendingEventsToDeliverToUpperProtocol.append(event)
    }

    mutating func discardPendingEventsForUpperProtocol() {
        unassignedPendingEventsToDeliverToUpperProtocol.removeAll()
    }

    var eventState: EventState = .idle
    var connectedState: ConnectedState = .initial
    var connectCallState: ConnectCallState = .initial
    var pendingEventsFromLowerProtocol = NetworkUniqueDeque<PendingEvent>()
    var pendingEventsToDeliverToUpperProtocol = NetworkUniqueDeque<PendingEvent>()
    var unassignedPendingEventsToDeliverToUpperProtocol = NetworkUniqueDeque<PendingEvent>()

    var timerScheduled = false

    var drainingEvents = false

    var isIdle: Bool {
        eventState == .idle
    }

    init() {}
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct ProtocolEventManager: ~Copyable {
    var contextIndex: NetworkStateIndex?
    var context: NetworkContext?
    public init() {
        contextIndex = nil
        context = nil
    }
    internal mutating func register(with context: NetworkContext, state: inout NetworkContext.State) -> NetworkStateIndex {
        if let contextIndex {
            // Already registered
            return contextIndex
        }
        self.context = context
        let registeredIndex = state.registerProtocolEventState()
        contextIndex = registeredIndex
        return registeredIndex
    }
    internal mutating func unregister(state: inout NetworkContext.State) {
        guard let contextIndex else { return }
        state.unregisterProtocolEventState(contextIndex)
        self.contextIndex = nil
    }
//    deinit {
//        guard let contextIndex, let context else { return }
//
//        // TODO: TFPDEBUG avoid async on deinit
////        context.async {
////            context.state.unregisterProtocolEventState(contextIndex)
////        }
//    }
}

@available(Network 0.1.0, *)
extension NetworkContext.State {
    fileprivate func softAssert() {
        #if DEBUG
        self.assert()
        #endif
    }
    @inline(always)
    fileprivate mutating func runEvents(on referenceToTrigger: ProtocolInstanceReference) {
        guard !referenceToTrigger.isNone,
            let indexToTrigger = referenceToTrigger.protocolEventStateIndex
        else { return }
        let eventCount = protocolEventStates[indexToTrigger].startDrainingPendingEventsFromLower()
        if eventCount > 0 {
            for _ in 0..<eventCount {
                let pendingEvent = protocolEventStates[indexToTrigger].readPendingEventFromLower()
                pendingEvent.run()
            }
            protocolEventStates[indexToTrigger].finishDrainingPendingEventsFromLower()
            drainPendingEvents(index: indexToTrigger)
        }
    }

    @inline(always)
    fileprivate mutating func runEvent(_ event: consuming ProtocolEventManagerState.PendingEvent) {
        let referenceToTrigger = event.toReference
        guard !referenceToTrigger.isNone,
            let indexToTrigger = referenceToTrigger.protocolEventStateIndex()
        else { return }

        let eventCount = protocolEventStates[indexToTrigger].startDrainingPendingEventsFromLower(hasNewEvent: true)
        if eventCount == 0 {
            // Cannot run events. Enqueue new event.
            protocolEventStates[indexToTrigger].addEventFromLowerProtocol(event: event)
            return
        } else if eventCount == 1 {
            // Fast path for common case. Just run the new event, don't enqueue.
            event.run()
        } else {
            // Enqueue new event, then run all events.
            protocolEventStates[indexToTrigger].addEventFromLowerProtocol(event: event)
            for _ in 0..<eventCount {
                let pendingEvent = protocolEventStates[indexToTrigger].readPendingEventFromLower()
                pendingEvent.run()
            }
        }
        protocolEventStates[indexToTrigger].finishDrainingPendingEventsFromLower()
        drainPendingEvents(index: indexToTrigger)
    }

    fileprivate mutating func drainPendingEvents(index: NetworkStateIndex) {
        if protocolEventStates[index].isIdle && !protocolEventStates[index].drainingEvents {
            protocolEventStates[index].drainingEvents = true
            let lowerEvents = protocolEventStates[index].startDrainingPendingEventsFromLower()
            if lowerEvents > 0 {
                for _ in 0..<lowerEvents {
                    protocolEventStates[index].readPendingEventFromLower().run()
                }
                protocolEventStates[index].finishDrainingPendingEventsFromLower()
            }
            var upperEvents = protocolEventStates[index].countPendingEventsToUpper()
            while upperEvents > 0 {
                if upperEvents == 1 {
                    // For cases with one event, just deliver to the lower protocol queue and run
                    if let pendingEvent = protocolEventStates[index].readPendingEventToUpper() {
                        runEvent(pendingEvent)
                    }
                } else {
                    // For cases with more than one event, batch all of the events in the lower protocol queue and run them in one pass
                    var referencesToTrigger = Deque<ProtocolInstanceReference>(minimumCapacity: upperEvents)
                    for _ in 0..<upperEvents {
                        if let pendingEvent = protocolEventStates[index].readPendingEventToUpper() {
                            referencesToTrigger.append(pendingEvent.deliver(state: &self))
                        }
                    }
                    while let referenceToTrigger = referencesToTrigger.popFirst() {
                        runEvents(on: referenceToTrigger)
                    }
                }
                upperEvents = protocolEventStates[index].countPendingEventsToUpper()
            }
            protocolEventStates[index].drainingEvents = false
        }
    }

    fileprivate mutating func deliverEventToUpperProtocol(
        index: NetworkStateIndex,
        parentIndex: NetworkStateIndex?,
        event: consuming ProtocolEventManagerState.PendingEvent,
        drain: Bool = true
    ) {
        softAssert()
        if event.isConnected {
            switch protocolEventStates[index].connectedState {
            case .initial: protocolEventStates[index].connectedState = .connected
            case .connected, .disconnected: return  // Don't deliver a redundant event
            }
        } else if event.isDisconnected {
            switch protocolEventStates[index].connectedState {
            case .disconnected: return  // Don't deliver a redundant event
            default: protocolEventStates[index].connectedState = .disconnected
            }
        }
        if let parentIndex {
            protocolEventStates[parentIndex].addPendingEventToDeliverToUpperProtocol(event)
            if drain {
                drainPendingEvents(index: parentIndex)
            }
        } else {
            protocolEventStates[index].addPendingEventToDeliverToUpperProtocol(event)
        }
    }

    fileprivate mutating func reassignQueuedPendingEventsForUpperProtocol(
        index: NetworkStateIndex,
        parentIndex: NetworkStateIndex?,
        newUpper: ProtocolInstanceReference
    ) {
        softAssert()
        if let parentIndex {
            var foundEvents = false
            while let event = protocolEventStates[index].unassignedPendingEventsToDeliverToUpperProtocol.popFirst() {
                let event = event.reassign(to: newUpper)
                deliverEventToUpperProtocol(index: index, parentIndex: parentIndex, event: event, drain: false)
                foundEvents = true
            }
            if foundEvents {
                drainPendingEvents(index: parentIndex)
            }
        } else {
            while let event = protocolEventStates[index].unassignedPendingEventsToDeliverToUpperProtocol.popFirst() {
                let event = event.reassign(to: newUpper)
                deliverEventToUpperProtocol(index: index, parentIndex: nil, event: event, drain: false)
            }
        }
    }

    fileprivate mutating func enqueuePendingEventForUpperProtocol(
        index: NetworkStateIndex,
        event: consuming ProtocolEventManagerState.PendingEvent
    ) {
        softAssert()
        protocolEventStates[index].enqueuePendingEventForUpperProtocol(event)
    }

    fileprivate mutating func discardPendingEventsForUpperProtocol(index: NetworkStateIndex) {
        softAssert()
        protocolEventStates[index].discardPendingEventsForUpperProtocol()
    }

    fileprivate mutating func addEventFromLowerProtocol(
        index: NetworkStateIndex,
        event: consuming ProtocolEventManagerState.PendingEvent
    ) {
        softAssert()
        protocolEventStates[index].addEventFromLowerProtocol(event: event)
    }

    fileprivate mutating func handleCallFromUpperProtocol<R, E: Error>(
        index: NetworkStateIndex,
        _ body: (inout NetworkContext.State) throws(E) -> R
    ) throws(E) -> R {
        softAssert()
        protocolEventStates[index].startCallFromUpperProtocol()
        defer {
            protocolEventStates[index].finishCallFromUpperProtocol()
            drainPendingEvents(index: index)
        }
        return try body(&self)
    }

    fileprivate mutating func handleCallFromUpperProtocol<R: ~Copyable, E: Error>(
        index: NetworkStateIndex,
        _ body: (inout NetworkContext.State) throws(E) -> R
    ) throws(E) -> R {
        softAssert()
        protocolEventStates[index].startCallFromUpperProtocol()
        defer {
            protocolEventStates[index].finishCallFromUpperProtocol()
            drainPendingEvents(index: index)
        }
        return try body(&self)
    }

    fileprivate mutating func handleCallFromUpperProtocol<R, T: ~Copyable, E: Error>(
        index: NetworkStateIndex,
        _ value: consuming T,
        _ body: (inout NetworkContext.State, consuming T) throws(E) -> R
    ) throws(E) -> R {
        softAssert()
        protocolEventStates[index].startCallFromUpperProtocol()
        defer {
            protocolEventStates[index].finishCallFromUpperProtocol()
            drainPendingEvents(index: index)
        }
        return try body(&self, value)
    }

    fileprivate mutating func fromExternal<R, E: Error>(
        index: NetworkStateIndex,
        _ body: (inout NetworkContext.State) throws(E) -> R
    ) throws(E) -> R {
        softAssert()
        let startedExternalCall = protocolEventStates[index].startExternalCall()
        defer {
            if startedExternalCall {
                protocolEventStates[index].finishExternalCall()
                drainPendingEvents(index: index)
            }
        }
        return try body(&self)
    }

    fileprivate mutating func fromExternal<R: ~Copyable, E: Error>(
        index: NetworkStateIndex,
        _ body: (inout NetworkContext.State) throws(E) -> R
    ) throws(E) -> R {
        softAssert()
        let startedExternalCall = protocolEventStates[index].startExternalCall()
        defer {
            if startedExternalCall {
                protocolEventStates[index].finishExternalCall()
                drainPendingEvents(index: index)
            }
        }
        return try body(&self)
    }

    fileprivate mutating func fromExternal<R, T: ~Copyable, E: Error>(
        index: NetworkStateIndex,
        _ value: consuming T,
        _ body: (inout NetworkContext.State, consuming T) throws(E) -> R
    ) throws(E) -> R {
        softAssert()
        let startedExternalCall = protocolEventStates[index].startExternalCall()
        defer {
            if startedExternalCall {
                protocolEventStates[index].finishExternalCall()
                drainPendingEvents(index: index)
            }
        }
        return try body(&self, value)
    }

    fileprivate mutating func runAsync(index: NetworkStateIndex, _ block: () -> Void) {
        protocolEventStates[index].startAsyncCall()
        defer {
            protocolEventStates[index].finishAsyncCall()
            drainPendingEvents(index: index)
        }
        block()
    }

    fileprivate mutating func runTimerWakeup(index: NetworkStateIndex, referenceToWakeup: ProtocolInstanceReference) {
        assert()
        protocolEventStates[index].startTimerWakeupCall()
        defer {
            protocolEventStates[index].finishTimerWakeupCall()
            drainPendingEvents(index: index)
        }
        referenceToWakeup.timerWakeup()
    }

    fileprivate mutating func connectRequested(index: NetworkStateIndex) {
        softAssert()
        if protocolEventStates[index].connectCallState == .initial {
            // Connect can't be called yet, but remember that it has been requested
            protocolEventStates[index].connectCallState = .connectRequested
        }
    }

    fileprivate mutating func canCallConnect(index: NetworkStateIndex, requested: Bool) -> Bool {
        softAssert()
        guard
            (protocolEventStates[index].connectCallState == .initial && requested)
                || protocolEventStates[index].connectCallState == .connectRequested,
            protocolEventStates[index].connectedState == .initial
        else {
            if protocolEventStates[index].connectCallState == .initial && requested {
                // Connect can't be called yet, but remember that it has been requested
                protocolEventStates[index].connectCallState = .connectRequested
            }
            return false
        }
        protocolEventStates[index].connectCallState = .connectCalled
        return true
    }

    fileprivate mutating func canCallDisconnect(index: NetworkStateIndex) -> Bool {
        softAssert()
        guard protocolEventStates[index].connectCallState != .disconnectCalled,
            protocolEventStates[index].connectedState != .disconnected
        else {
            return false
        }
        protocolEventStates[index].connectCallState = .disconnectCalled
        return true
    }

    fileprivate mutating func isConnected(index: NetworkStateIndex) -> Bool {
        softAssert()
        return protocolEventStates[index].connectedState == .connected
    }

    fileprivate func async(context: NetworkContext, index: NetworkStateIndex, _ block: @escaping () -> Void) {
        softAssert()
        self.async {
            context.state.runAsync(index: index, block)
        }
    }

    fileprivate func scheduleWakeup(
        context: NetworkContext,
        index: NetworkStateIndex,
        timerReference: TimerReference,
        referenceToWakeup: ProtocolInstanceReference,
        milliseconds: UInt64
    ) {
        softAssert()
        resetTimer(
            for: timerReference,
            to: .milliseconds(
                milliseconds,
                {
                    context.state.runTimerWakeup(index: index, referenceToWakeup: referenceToWakeup)
                }
            )
        )
    }

}

@available(Network 0.1.0, *)
extension NetworkContext {
    fileprivate func softAssert() {
        #if DEBUG
        self.assert()
        #endif
    }

    fileprivate func async(index: NetworkStateIndex, _ block: @escaping () -> Void) {
        softAssert()
        self.async {
            self.state.runAsync(index: index, block)
        }
    }

    fileprivate func scheduleWakeup(
        index: NetworkStateIndex,
        timerReference: TimerReference,
        referenceToWakeup: ProtocolInstanceReference,
        milliseconds: UInt64
    ) {
        softAssert()
        resetTimer(
            for: timerReference,
            to: .milliseconds(
                milliseconds,
                {
                    self.state.runTimerWakeup(index: index, referenceToWakeup: referenceToWakeup)
                }
            )
        )
    }
}

@available(Network 0.1.0, *)
extension ProtocolInstance where Self: ~Copyable {
    func connectRequested(state: inout NetworkContext.State) {
        reference.connectRequested(state: &state)
    }

    func canCallConnect(state: inout NetworkContext.State, requested: Bool) -> Bool {
        reference.canCallConnect(state: &state, requested: requested)
    }

    func canCallDisconnect(state: inout NetworkContext.State) -> Bool {
        reference.canCallDisconnect(state: &state)
    }

    @inline(always)
    func isConnected(state: inout NetworkContext.State) -> Bool {
        reference.isConnected(state: &state)
    }
}

@available(Network 0.1.0, *)
extension ProtocolInstanceReference {

    func connectRequested(state: inout NetworkContext.State) {
        guard let _protocolEventStateIndex else { return }
        state.connectRequested(index: _protocolEventStateIndex)
    }

    func canCallConnect(state: inout NetworkContext.State, requested: Bool) -> Bool {
        guard let _protocolEventStateIndex else { return false }
        return state.canCallConnect(index: _protocolEventStateIndex, requested: requested)
    }

    func canCallDisconnect(state: inout NetworkContext.State) -> Bool {
        guard let _protocolEventStateIndex else { return false }
        return state.canCallDisconnect(index: _protocolEventStateIndex)
    }

    @inline(always)
    func isConnected(state: inout NetworkContext.State) -> Bool {
        guard let _protocolEventStateIndex else { return false }
        return state.isConnected(index: _protocolEventStateIndex)
    }

    @inline(always)
    func handleCallFromUpperProtocol<R, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.handleCallFromUpperProtocol(index: protocolEventStateIndex, body)
    }

    @inline(always)
    func handleCallFromUpperProtocol<R: ~Copyable, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.handleCallFromUpperProtocol(index: protocolEventStateIndex, body)
    }

    @inline(always)
    func handleCallFromUpperProtocol<R, T: ~Copyable, E: Error>(
        state: inout NetworkContext.State,
        _ value: consuming T,
        _ body: (inout NetworkContext.State, consuming T) throws(E) -> R
    ) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.handleCallFromUpperProtocol(index: protocolEventStateIndex, value, body)
    }

    @inline(always)
    func deliverEventToUpperProtocol(state: inout NetworkContext.State, event: consuming ProtocolEventManagerState.PendingEvent) {
        guard let _protocolEventStateIndex else { return }
        state.deliverEventToUpperProtocol(
            index: _protocolEventStateIndex,
            parentIndex: _parentProtocolEventStateIndex,
            event: event
        )
    }

    @inline(always)
    func enqueuePendingEventForUpperProtocol(state: inout NetworkContext.State, event: consuming ProtocolEventManagerState.PendingEvent) {
        guard let _protocolEventStateIndex else { return }
        state.enqueuePendingEventForUpperProtocol(
            index: _protocolEventStateIndex,
            event: event
        )
    }

    @inline(always)
    func reassignQueuedPendingEventsForUpperProtocol(state: inout NetworkContext.State, to newUpper: ProtocolInstanceReference) {
        guard let _protocolEventStateIndex else { return }
        state.reassignQueuedPendingEventsForUpperProtocol(
            index: _protocolEventStateIndex,
            parentIndex: _parentProtocolEventStateIndex,
            newUpper: newUpper
        )
    }

    @inline(always)
    func discardPendingEventsForUpperProtocol(state: inout NetworkContext.State) {
        guard let _protocolEventStateIndex else { return }
        state.discardPendingEventsForUpperProtocol(index: _protocolEventStateIndex)
    }

    @inline(always)
    func addEventFromLowerProtocol(state: inout NetworkContext.State, event: consuming ProtocolEventManagerState.PendingEvent) {
        guard let protocolEventStateIndex = protocolEventStateIndex else { return }
        state.addEventFromLowerProtocol(index: protocolEventStateIndex, event: event)
    }

    public func fromExternal<R, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.fromExternal(index: protocolEventStateIndex, body)
    }

    public func fromExternal<R: ~Copyable, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.fromExternal(index: protocolEventStateIndex, body)
    }

    func fromExternal<R, T: ~Copyable, E: Error>(
        state: inout NetworkContext.State,
        _ value: consuming T,
        _ body: (inout NetworkContext.State, consuming T) throws(E) -> R
    ) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.fromExternal(index: protocolEventStateIndex, value, body)
    }

    public func async(state: inout NetworkContext.State, _ block: @escaping () -> Void) {
        let protocolEventStateIndex = protocolEventStateIndex!
        state.async(context: context, index: protocolEventStateIndex, block)
    }

    func timerWakeup() {
        switch reference {
        case .none: return
        case .tcp(let instance): instance.wakeup()
        #if !NETWORK_NO_SWIFT_QUIC
        case .quic(let instance): instance.wakeup()
        #endif
        #if !NETWORK_EMBEDDED
        case .custom(let container, let index): container.accessTimerSchedulable(at: index) { $0.wakeup() }
        #endif
        default: return
        }
    }

    func scheduleWakeup(
        state: inout NetworkContext.State,
        milliseconds: UInt64,
        timerReference: TimerReference
    ) {
        let protocolEventStateIndex = protocolEventStateIndex!
        state.scheduleWakeup(
            context: context,
            index: protocolEventStateIndex,
            timerReference: timerReference,
            referenceToWakeup: self,
            milliseconds: milliseconds
        )
    }

    func unscheduleWakeup(state: inout NetworkContext.State, timerReference: TimerReference) {
        state.assert()
        state.resetTimer(for: timerReference, to: .unschedule)
    }
}

@available(Network 0.1.0, *)
extension ProtocolInstanceReference2 {

    func connectRequested(state: inout NetworkContext.State) {
        guard let eventStateIndex else { return }
        state.connectRequested(index: eventStateIndex)
    }

    func canCallConnect(state: inout NetworkContext.State, requested: Bool) -> Bool {
        guard let eventStateIndex else { return false }
        return state.canCallConnect(index: eventStateIndex, requested: requested)
    }

    func canCallDisconnect(state: inout NetworkContext.State) -> Bool {
        guard let eventStateIndex else { return false }
        return state.canCallDisconnect(index: eventStateIndex)
    }

    @inline(__always)
    func isConnected(state: inout NetworkContext.State) -> Bool {
        guard let eventStateIndex else { return false }
        return state.isConnected(index: eventStateIndex)
    }

    @inline(__always)
    func handleCallFromUpperProtocol<R, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.handleCallFromUpperProtocol(index: protocolEventStateIndex, body)
    }

    @inline(__always)
    func handleCallFromUpperProtocol<R: ~Copyable, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.handleCallFromUpperProtocol(index: protocolEventStateIndex, body)
    }

    @inline(__always)
    func handleCallFromUpperProtocol<R, T: ~Copyable, E: Error>(
        state: inout NetworkContext.State,
        _ value: consuming T,
        _ body: (inout NetworkContext.State, consuming T) throws(E) -> R
    ) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.handleCallFromUpperProtocol(index: protocolEventStateIndex, value, body)
    }

    @inline(__always)
    func deliverEventToUpperProtocol(state: inout NetworkContext.State, event: consuming ProtocolEventManagerState.PendingEvent) {
        guard let eventStateIndex else { return }
        state.deliverEventToUpperProtocol(
            index: eventStateIndex,
            parentIndex: parentEventStateIndex,
            event: event
        )
    }

    @inline(__always)
    func enqueuePendingEventForUpperProtocol(state: inout NetworkContext.State, event: consuming ProtocolEventManagerState.PendingEvent) {
        guard let eventStateIndex else { return }
        state.enqueuePendingEventForUpperProtocol(
            index: eventStateIndex,
            event: event
        )
    }

    @inline(__always)
    func reassignQueuedPendingEventsForUpperProtocol(state: inout NetworkContext.State, to newUpper: ProtocolInstanceReference) {
        guard let eventStateIndex else { return }
        state.reassignQueuedPendingEventsForUpperProtocol(
            index: eventStateIndex,
            parentIndex: parentEventStateIndex,
            newUpper: newUpper
        )
    }

    @inline(__always)
    func discardPendingEventsForUpperProtocol(state: inout NetworkContext.State) {
        guard let eventStateIndex else { return }
        state.discardPendingEventsForUpperProtocol(index: eventStateIndex)
    }

    @inline(__always)
    func addEventFromLowerProtocol(state: inout NetworkContext.State, event: consuming ProtocolEventManagerState.PendingEvent) {
        guard let protocolEventStateIndex = protocolEventStateIndex else { return }
        state.addEventFromLowerProtocol(index: protocolEventStateIndex, event: event)
    }

    public func fromExternal<R, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.fromExternal(index: protocolEventStateIndex, body)
    }

    public func fromExternal<R: ~Copyable, E: Error>(state: inout NetworkContext.State, _ body: (inout NetworkContext.State) throws(E) -> R) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.fromExternal(index: protocolEventStateIndex, body)
    }

    func fromExternal<R, T: ~Copyable, E: Error>(
        state: inout NetworkContext.State,
        _ value: consuming T,
        _ body: (inout NetworkContext.State, consuming T) throws(E) -> R
    ) throws(E) -> R {
        let protocolEventStateIndex = protocolEventStateIndex!
        return try state.fromExternal(index: protocolEventStateIndex, value, body)
    }

    public func async(context: NetworkContext, state: inout NetworkContext.State, _ block: @escaping () -> Void) {
        let protocolEventStateIndex = protocolEventStateIndex!
        state.async(context: context, index: protocolEventStateIndex, block)
    }

    func timerWakeup() {
        // TODO: TFPDEBUG Fix this
//        switch reference {
//        case .none: return
//        case .tcp(let instance): instance.wakeup()
//        #if !NETWORK_NO_SWIFT_QUIC
//        case .quic(let instance): instance.wakeup()
//        #endif
//        #if !NETWORK_EMBEDDED
//        case .custom(let container, let index): container.accessTimerSchedulable(at: index) { $0.wakeup() }
//        #endif
//        default: return
//        }
    }

    public func scheduleWakeup(state: inout NetworkContext.State,
                               milliseconds: UInt64,
                               timerReference: TimerReference) {
        // TODO: TFPDEBUG For now we don't have the right type to pass to referenceToWakeup, ignore

//        let protocolEventStateIndex = protocolEventStateIndex!
//        context.scheduleWakeup(index: protocolEventStateIndex, referenceToWakeup: self, milliseconds: milliseconds)
    }

    public func unscheduleWakeup(state: inout NetworkContext.State, timerReference: TimerReference) {
        state.assert()
        state.resetTimer(for: timerReference, to: .unschedule)
    }
}
