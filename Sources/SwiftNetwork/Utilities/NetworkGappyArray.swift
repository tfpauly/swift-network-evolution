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

#if canImport(Synchronization)
internal import Synchronization
#endif

// This index is used to refer to a location (as in NetworkGappyArray) without
// exposing numeric properties. It also contains a generation to detect invalid
// reuse of indices.
@available(Network 0.1.0, *)
struct NetworkStateIndex: Hashable {
    fileprivate let index: Int
    fileprivate let generation: UInt64
    fileprivate init(index: Int, generation: UInt64) {
        self.index = index
        self.generation = generation
    }
    fileprivate func indexWithNextGeneration() -> Self {
        .init(index: index, generation: generation &+ 1)
    }
    var rawValue: Int { index }
}

// A "gappy array" is an array of non-copyable elements where the index of
// an element does not change once it is added. The index will remain until
// the element is removed. When the element is removed, this can create a
// "gap" in the array which can be re-used by new elements.
//
// This type does not convey any particular order, but is used to be a condensed
// way of holding elements that have fast lookup. This is similar to how
// interface indices (if_index) is used in kernel networking stacks.
@available(Network 0.1.0, *)
struct NetworkGappyArray<Element: ~Copyable>: ~Copyable {

    // Array of elements, which may have gaps
    fileprivate var elements = NetworkUniqueArray<Element?>()

    // Free indices in elements array
    fileprivate var gaps = NetworkPriorityQueue<GapRecord>()

    private var generation: UInt64 = 0

    @inlinable
    subscript(position: NetworkStateIndex) -> Element {
        _modify {
            yield &elements[position.index]!
        }
        mutating _read {
            yield elements[position.index]!
        }
    }

    var count: Int { elements.count - gaps.count }

    var isEmpty: Bool { count == 0 }

    internal struct GapRecord: ~Copyable, NetworkComparable {
        let index: NetworkStateIndex
        init(_ index: NetworkStateIndex) {
            self.index = index
        }

        static func < (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
            lhs.index.index < rhs.index.index
        }
        static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
            (lhs.index.index == rhs.index.index)
        }
    }

    mutating func insert(_ element: consuming Element) -> NetworkStateIndex {
        if let gap = gaps.pop() {
            let gapIndex = gap.index.indexWithNextGeneration()
            elements[gapIndex.index] = consume element
            return gapIndex
        }
        let newIndex = elements.count
        elements.append(element)
        return NetworkStateIndex(index: newIndex, generation: generation)
    }

    internal mutating func cleanupGapsIfNecessary(incrementedGeneration: Bool) {
        let count = elements.count
        guard count > 0, elements[count - 1] == nil else {
            // Cannot cleanup gaps at the end
            return
        }

        guard gaps.count * 10 > elements.count else {
            // Only cleanup gaps if they represent more than 10% of the total elements
            return
        }

        // Walk elements from end, removing any that are nil, and remove
        // the corresponding gap record
        while true {
            let count = elements.count
            guard count > 0 else { break }  // Array must be non-empty
            guard elements[count - 1] == nil else { break }  // Value must be nil
            gaps.removeFirst { $0.index.index == count - 1 }
            elements.removeLast()
        }

        if !incrementedGeneration {
            self.generation &+= 1
        }
    }

    mutating func remove(index: NetworkStateIndex) {
        var incrementedGeneration = false
        defer { cleanupGapsIfNecessary(incrementedGeneration: incrementedGeneration) }
        if index.index == elements.count - 1 {
            // Removing last element
            elements.removeLast()
            self.generation &+= 1
            incrementedGeneration = true
            return
        }

        // Clear element and record the gap
        elements[index.index] = nil
        gaps.push(GapRecord(index))
    }
}


// TODO: Have a registrar (held by the context) that knows about the available linkages?
// TODO: Or do we push the registrars into the linkage type definitions... like a linkage family, with associated types for supporting datagrams, streams, messages, etc.

// TODO: Be able to register a function to get back to the definition?
@available(Network 0.1.0, *)
struct NetworkProtocolRegistrar: ~Copyable {

    // Count of protocols, only grows
    private let protocolCount = NetworkMutex<Int>(1)
    private var nextProtocolIndex: NetworkStateIndex {
        var index: Int = 0
        protocolCount.withLock {
            index = $0
            $0 += 1
        }
        return NetworkStateIndex(index: index, generation: 0)
    }

    private var registeredProtocols = Dictionary<ProtocolIdentifier, NetworkStateIndex>()

    var count: Int { registeredProtocols.count }

    var isEmpty: Bool { count == 0 }

    mutating func register(protocol protocolIdentifier: ProtocolIdentifier) -> NetworkStateIndex {
        if let existingIndex = registeredProtocols[protocolIdentifier] {
            return existingIndex
        }
        let newIndex = nextProtocolIndex
        registeredProtocols[protocolIdentifier] = newIndex
        return newIndex
    }
}

