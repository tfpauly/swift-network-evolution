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

@_spi(Essentials)
@available(Network 0.1.0, *)
public struct ProtocolInstanceReference: Hashable {

    let eventStateIndex: NetworkStateIndex?

    var parentEventStateIndex: NetworkStateIndex?

    func protocolEventStateIndex(allowParent: Bool = true) -> NetworkStateIndex? {
        if let parentEventStateIndex { return parentEventStateIndex }
        return eventStateIndex
    }

    var protocolEventStateIndex: NetworkStateIndex? {
        protocolEventStateIndex()
    }

    public mutating func setParentReference(_ parentReference: ProtocolInstanceReference) {
        parentEventStateIndex = parentReference.eventStateIndex
    }

    public init() {
        eventStateIndex = nil
    }

    public init(context: NetworkContext, eventManager: inout ProtocolEventManager) {
        self.eventStateIndex = eventManager.register(with: context, state: &context.state)
    }

    /// Registers using a context state the caller already holds.
    ///
    /// Use this instead of `init(context:eventManager:)` when constructing a reference from
    /// inside a call that already has the state, so the state isn't re-derived from the context.
    public init(
        eventManager: inout ProtocolEventManager,
        context: NetworkContext,
        state: inout NetworkContext.State
    ) {
        self.eventStateIndex = eventManager.register(with: context, state: &state)
    }

    public var isNone: Bool {
        eventStateIndex == nil
    }
}
