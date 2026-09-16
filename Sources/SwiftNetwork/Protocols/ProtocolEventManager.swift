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
        typealias EventBlock = (inout NetworkContext.State, ProtocolInstanceReference) -> Void
        typealias ErrorEventBlock = (inout NetworkContext.State, ProtocolInstanceReference, NetworkError?) -> Void
        typealias NewInboundFlowEventBlock = (
            inout NetworkContext.State,
            ProtocolInstanceReference,
            ProtocolInstanceReference,
            AbstractProtocolMetadata?
        ) -> Void
        typealias NetworkProtocolEventBlock = (
            inout NetworkContext.State,
            ProtocolInstanceReference,
            NetworkProtocolEvent
        ) -> Void

        case connected(_ from: ProtocolInstanceReference, _ to: ProtocolInstanceReference, _ block: EventBlock)
        case disconnected(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            error: NetworkError?,
            _ block: ErrorEventBlock
        )
        case inboundDataAvailable(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            _ block: EventBlock
        )
        case outboundRoomAvailable(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            _ block: EventBlock
        )
        case inboundAborted(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            error: NetworkError?,
            _ block: ErrorEventBlock
        )
        case outboundAborted(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            error: NetworkError?,
            _ block: ErrorEventBlock
        )
        case newInboundFlow(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            flowReference: ProtocolInstanceReference,
            flowMetadata: AbstractProtocolMetadata?,
            _ block: NewInboundFlowEventBlock
        )
        case networkProtocolEvent(
            _ from: ProtocolInstanceReference,
            _ to: ProtocolInstanceReference,
            event: NetworkProtocolEvent,
            _ block: NetworkProtocolEventBlock
        )

        fileprivate func run(state: inout NetworkContext.State) {
            switch self {
            case .connected(let from, _, let block): block(&state, from)
            case .disconnected(let from, _, let error, let block): block(&state, from, error)
            case .inboundDataAvailable(let from, _, let block): block(&state, from)
            case .outboundRoomAvailable(let from, _, let block): block(&state, from)
            case .inboundAborted(let from, _, let error, let block): block(&state, from, error)
            case .outboundAborted(let from, _, let error, let block): block(&state, from, error)
            case .newInboundFlow(let from, _, let flow, let metadata, let block):
                block(&state, from, flow, metadata)
            case .networkProtocolEvent(let from, _, let event, let block): block(&state, from, event)
            }
        }

        @inline(always)
        fileprivate var toReference: ProtocolInstanceReference {
            switch self {
            case .connected(_, let to, _): return to
            case .disconnected(_, let to, _, _): return to
            case .inboundDataAvailable(_, let to, _): return to
            case .outboundRoomAvailable(_, let to, _): return to
            case .inboundAborted(_, let to, _, _): return to
            case .outboundAborted(_, let to, _, _): return to
            case .newInboundFlow(_, let to, _, _, _): return to
            case .networkProtocolEvent(_, let to, _, _): return to
            }
        }

        fileprivate consuming func deliver(state: inout NetworkContext.State) -> ProtocolInstanceReference {
            let toReference = self.toReference
            if !toReference.isNone {
                toReference.addEventFromLowerProtocol(state: &state, event: self)
            }
            return toReference
        }

        fileprivate consuming func reassign(
            to newTo: ProtocolInstanceReference,
            _ newBlock: @escaping EventBlock,
            _ newErrorBlock: @escaping ErrorEventBlock,
            _ newInboundFlowBlock: @escaping NewInboundFlowEventBlock,
            _ newNetworkProtocolEventBlock: @escaping NetworkProtocolEventBlock,
            _ newInboundAbortedBlock: @escaping ErrorEventBlock,
            _ newOutboundAbortedBlock: @escaping ErrorEventBlock
        ) -> PendingEvent {
            switch self {
            case .connected(let from, _, _): return .connected(from, newTo, newBlock)
            case .disconnected(let from, _, let error, _):
                return .disconnected(from, newTo, error: error, newErrorBlock)
            case .inboundDataAvailable(let from, _, _): return .inboundDataAvailable(from, newTo, newBlock)
            case .outboundRoomAvailable(let from, _, _): return .outboundRoomAvailable(from, newTo, newBlock)
            case .inboundAborted(let from, _, let error, _):
                return .inboundAborted(from, newTo, error: error, newInboundAbortedBlock)
            case .outboundAborted(let from, _, let error, _):
                return .outboundAborted(from, newTo, error: error, newOutboundAbortedBlock)
            case .newInboundFlow(let from, _, let flow, let metadata, _):
                return .newInboundFlow(
                    from,
                    newTo,
                    flowReference: flow,
                    flowMetadata: metadata,
                    newInboundFlowBlock
                )
            case .networkProtocolEvent(let from, _, let event, _):
                return .networkProtocolEvent(from, newTo, event: event, newNetworkProtocolEventBlock)
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

    // Number of things that still hold this index: queued async blocks, at most one scheduled
    // timer wakeup, and any such block currently running. They all dereference the index, so the
    // event state must outlive them; see `retiring`.
    private(set) var outstandingWakeups: UInt32 = 0

    // Whether the scheduled timer wakeup is currently counted in `outstandingWakeups`. Timers are
    // rescheduled in place rather than stacked, so this keeps a reschedule from counting twice.
    private var timerScheduled = false

    // Set when unregistration was requested while blocks were still outstanding. The last block
    // to finish removes the event state.
    var retiring = false

    mutating func addOutstandingWakeup() {
        outstandingWakeups += 1
    }

    mutating func finishOutstandingWakeup() {
        outstandingWakeups -= 1
    }

    mutating func addScheduledTimer() {
        // Rescheduling replaces the existing timer entry, so it is still just one outstanding
        // wakeup.
        guard !timerScheduled else { return }
        timerScheduled = true
        outstandingWakeups += 1
    }

    mutating func clearScheduledTimer() {
        guard timerScheduled else { return }
        timerScheduled = false
        outstandingWakeups -= 1
    }

    // Whether the event state can be removed, meaning no scheduled block still holds its index.
    var canRemove: Bool {
        outstandingWakeups == 0
    }

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
        state.retireProtocolEventState(contextIndex)
        self.contextIndex = nil
    }
}

@available(Network 0.1.0, *)
extension NetworkContext.State {
    fileprivate func softAssert() {
        #if DEBUG
        self.assert()
        #endif
    }

    // Marks a scheduled timer for `index` as no longer outstanding, dropping the event state if
    // that was the last thing keeping a retiring one alive.
    fileprivate mutating func clearScheduledTimer(_ index: NetworkStateIndex) {
        protocolEventStates[index].clearScheduledTimer()
        removeProtocolEventStateIfRetired(index)
    }

    // Removes an event state that is retiring once nothing scheduled still holds its index.
    fileprivate mutating func removeProtocolEventStateIfRetired(_ index: NetworkStateIndex) {
        guard protocolEventStates[index].retiring, protocolEventStates[index].canRemove else {
            return
        }
        unregisterProtocolEventState(index)
    }

    // Retires the event state for `index`, removing it now if nothing scheduled still holds it.
    //
    // Queued async blocks and scheduled timer wakeups capture the index and dereference it when
    // they run, so removing the state while any are outstanding would leave them pointing at an
    // empty slot. In that case the state is marked retiring and the last such block removes it.
    fileprivate mutating func retireProtocolEventState(_ index: NetworkStateIndex) {
        guard protocolEventStates[index].canRemove else {
            protocolEventStates[index].retiring = true
            return
        }
        unregisterProtocolEventState(index)
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
                pendingEvent.run(state: &self)
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
            event.run(state: &self)
        } else {
            // Enqueue new event, then run all events.
            protocolEventStates[indexToTrigger].addEventFromLowerProtocol(event: event)
            for _ in 0..<eventCount {
                let pendingEvent = protocolEventStates[indexToTrigger].readPendingEventFromLower()
                pendingEvent.run(state: &self)
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
                    protocolEventStates[index].readPendingEventFromLower().run(state: &self)
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
        newUpper: ProtocolInstanceReference,
        block: @escaping ProtocolEventManagerState.PendingEvent.EventBlock,
        errorBlock: @escaping ProtocolEventManagerState.PendingEvent.ErrorEventBlock,
        newInboundFlowBlock: @escaping ProtocolEventManagerState.PendingEvent.NewInboundFlowEventBlock,
        networkProtocolEventBlock: @escaping ProtocolEventManagerState.PendingEvent.NetworkProtocolEventBlock,
        inboundAbortedBlock: @escaping ProtocolEventManagerState.PendingEvent.ErrorEventBlock,
        outboundAbortedBlock: @escaping ProtocolEventManagerState.PendingEvent.ErrorEventBlock
    ) {
        softAssert()
        if let parentIndex {
            var foundEvents = false
            while let event = protocolEventStates[index].unassignedPendingEventsToDeliverToUpperProtocol.popFirst() {
                let event = event.reassign(
                    to: newUpper,
                    block,
                    errorBlock,
                    newInboundFlowBlock,
                    networkProtocolEventBlock,
                    inboundAbortedBlock,
                    outboundAbortedBlock
                )
                deliverEventToUpperProtocol(index: index, parentIndex: parentIndex, event: event, drain: false)
                foundEvents = true
            }
            if foundEvents {
                drainPendingEvents(index: parentIndex)
            }
        } else {
            while let event = protocolEventStates[index].unassignedPendingEventsToDeliverToUpperProtocol.popFirst() {
                let event = event.reassign(
                    to: newUpper,
                    block,
                    errorBlock,
                    newInboundFlowBlock,
                    networkProtocolEventBlock,
                    inboundAbortedBlock,
                    outboundAbortedBlock
                )
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

    fileprivate mutating func runAsync(
        index: NetworkStateIndex,
        _ block: (inout NetworkContext.State) -> Void
    ) {
        protocolEventStates[index].startAsyncCall()
        defer {
            protocolEventStates[index].finishAsyncCall()
            drainPendingEvents(index: index)
            // This block no longer holds the index. Account for it after draining, since draining
            // can schedule further work, and drop the event state if this was the last holder.
            protocolEventStates[index].finishOutstandingWakeup()
            removeProtocolEventStateIfRetired(index)
        }
        block(&self)
    }

    fileprivate mutating func runTimerWakeup(
        index: NetworkStateIndex,
        _ wakeup: (inout NetworkContext.State) -> Void
    ) {
        assert()
        // The scheduler drops a timer entry when it fires, so that entry is no longer outstanding.
        // The wakeup call itself now holds the index instead: `wakeup` can unregister this event
        // state, and the `defer` below still needs it. Swapping one holder for the other keeps the
        // count from reaching zero mid-call, and lets `wakeup` arm a fresh timer.
        protocolEventStates[index].addOutstandingWakeup()
        protocolEventStates[index].clearScheduledTimer()
        protocolEventStates[index].startTimerWakeupCall()
        defer {
            protocolEventStates[index].finishTimerWakeupCall()
            drainPendingEvents(index: index)
            protocolEventStates[index].finishOutstandingWakeup()
            removeProtocolEventStateIfRetired(index)
        }
        wakeup(&self)
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

    fileprivate mutating func async(
        context: NetworkContext,
        index: NetworkStateIndex,
        _ block: @escaping (inout NetworkContext.State) -> Void
    ) {
        softAssert()
        // The queued block holds `index` until it runs, so keep the event state alive until then.
        protocolEventStates[index].addOutstandingWakeup()
        self.async {
            context.state.runAsync(index: index, block)
        }
    }

    fileprivate mutating func scheduleWakeup(
        context: NetworkContext,
        index: NetworkStateIndex,
        timerReference: TimerReference,
        milliseconds: UInt64,
        _ wakeup: @escaping (inout NetworkContext.State) -> Void
    ) {
        softAssert()
        // The scheduled wakeup holds `index` until it fires or is unscheduled.
        protocolEventStates[index].addScheduledTimer()
        resetTimer(
            for: timerReference,
            to: .milliseconds(
                milliseconds,
                {
                    // The scheduler hands back no state, so this is where the timer re-enters
                    // the stack: acquire the state once and thread it into `wakeup`.
                    context.state.runTimerWakeup(index: index, wakeup)
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

    fileprivate func async(
        index: NetworkStateIndex,
        _ block: @escaping (inout NetworkContext.State) -> Void
    ) {
        softAssert()
        self.state.protocolEventStates[index].addOutstandingWakeup()
        self.async {
            self.state.runAsync(index: index, block)
        }
    }

    fileprivate func scheduleWakeup(
        index: NetworkStateIndex,
        timerReference: TimerReference,
        milliseconds: UInt64,
        _ wakeup: @escaping (inout NetworkContext.State) -> Void
    ) {
        softAssert()
        self.state.protocolEventStates[index].addScheduledTimer()
        resetTimer(
            for: timerReference,
            to: .milliseconds(
                milliseconds,
                {
                    self.state.runTimerWakeup(index: index, wakeup)
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
    func reassignQueuedPendingEventsForUpperProtocol(
        state: inout NetworkContext.State,
        to newUpper: ProtocolInstanceReference,
        block: @escaping ProtocolEventManagerState.PendingEvent.EventBlock,
        errorBlock: @escaping ProtocolEventManagerState.PendingEvent.ErrorEventBlock,
        newInboundFlowBlock: @escaping ProtocolEventManagerState.PendingEvent.NewInboundFlowEventBlock,
        networkProtocolEventBlock: @escaping ProtocolEventManagerState.PendingEvent.NetworkProtocolEventBlock,
        inboundAbortedBlock: @escaping ProtocolEventManagerState.PendingEvent.ErrorEventBlock,
        outboundAbortedBlock: @escaping ProtocolEventManagerState.PendingEvent.ErrorEventBlock
    ) {
        guard let eventStateIndex else { return }
        state.reassignQueuedPendingEventsForUpperProtocol(
            index: eventStateIndex,
            parentIndex: parentEventStateIndex,
            newUpper: newUpper,
            block: block,
            errorBlock: errorBlock,
            newInboundFlowBlock: newInboundFlowBlock,
            networkProtocolEventBlock: networkProtocolEventBlock,
            inboundAbortedBlock: inboundAbortedBlock,
            outboundAbortedBlock: outboundAbortedBlock
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

    public func async(
        context: NetworkContext,
        state: inout NetworkContext.State,
        _ block: @escaping (inout NetworkContext.State) -> Void
    ) {
        let protocolEventStateIndex = protocolEventStateIndex!
        state.async(context: context, index: protocolEventStateIndex, block)
    }

    /// Schedules a timer wakeup, running `wakeup` with the context state once the timer fires.
    ///
    /// The scheduler hands back no state, so the timer is an entry point into the stack: the
    /// state is acquired when the timer fires and threaded into `wakeup`.
    public func scheduleWakeup(
        context: NetworkContext,
        state: inout NetworkContext.State,
        milliseconds: UInt64,
        timerReference: TimerReference,
        _ wakeup: @escaping (inout NetworkContext.State) -> Void
    ) {
        guard let protocolEventStateIndex else { return }
        state.scheduleWakeup(
            context: context,
            index: protocolEventStateIndex,
            timerReference: timerReference,
            milliseconds: milliseconds,
            wakeup
        )
    }

    public func unscheduleWakeup(state: inout NetworkContext.State, timerReference: TimerReference) {
        state.assert()
        state.resetTimer(for: timerReference, to: .unschedule)
        guard let protocolEventStateIndex else { return }
        state.clearScheduledTimer(protocolEventStateIndex)
    }
}
