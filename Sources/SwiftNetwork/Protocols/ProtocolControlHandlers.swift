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

/// A protocol closer to the app, with a linkage to a lower protocol toward the network.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol UpperProtocolHandler<LowerProtocol>: ~Copyable, ProtocolInstance {
    associatedtype LowerProtocol: LowerProtocolLinkage

    mutating func attachLowerProtocol(
        _ lowerProtocol: LowerProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    mutating func handleConnectedEvent(_ from: ProtocolInstanceReference)
    mutating func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?)
    mutating func handleNetworkProtocolEvent(_ from: ProtocolInstanceReference, event: NetworkProtocolEvent)
}

@available(Network 0.1.0, *)
extension ProtocolInstanceReference {
    func handleConnectedEvent(_ from: ProtocolInstanceReference) {
        switch reference {
        case .none: return
        case .tcp(var instance): instance.handleConnectedEvent(from)
        case .udp(let index): context.state.udpInstances[index].handleConnectedEvent(from)
        case .ip(let index): context.state.ipInstances[index].handleConnectedEvent(from)
        case .tls(var instance): instance.handleConnectedEvent(from)
        case .tlsEncryptionLevel(let instance): instance.handleConnectedEvent(from)
        case .streamEndpointFlow(let instance): instance.handleConnectedEvent(from)
        case .datagramEndpointFlow(let instance): instance.handleConnectedEvent(from)
        #if !NETWORK_NO_SWIFT_QUIC
        case .quicPath(let instance): instance.handleConnectedEvent(from)
        case .quicCrypto(let instance): instance.handleConnectedEvent(from)
        #endif
        #if !NETWORK_NO_TESTING_HARNESS
        case .streamUpperHarness(let instance): instance.handleConnectedEvent(from)
        case .datagramUpperHarness(let instance): instance.handleConnectedEvent(from)
        case .newStreamFlowHarness(let instance): instance.handleConnectedEvent(from)
        case .newDatagramFlowHarness(let instance): instance.handleConnectedEvent(from)
        #endif
        #if !NETWORK_EMBEDDED
        case .custom(let container, let index):
            return container.accessUpper(at: index) { $0.handleConnectedEvent(from) }
        #endif
        default: fatalError("Protocol cannot accept handleConnectedEvent event")
        }
    }
    func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        switch reference {
        case .none: return
        case .tcp(var instance): instance.handleDisconnectedEvent(from, error: error)
        case .udp(let index): context.state.udpInstances[index].handleDisconnectedEvent(from, error: error)
        case .ip(let index): context.state.ipInstances[index].handleDisconnectedEvent(from, error: error)
        case .tls(var instance): instance.handleDisconnectedEvent(from, error: error)
        case .tlsEncryptionLevel(let instance): instance.handleDisconnectedEvent(from, error: error)
        case .streamEndpointFlow(let instance): instance.handleDisconnectedEvent(from, error: error)
        case .datagramEndpointFlow(let instance): instance.handleDisconnectedEvent(from, error: error)
        #if !NETWORK_NO_SWIFT_QUIC
        case .quicPath(let instance): instance.handleDisconnectedEvent(from, error: error)
        case .quicCrypto(let instance): instance.handleDisconnectedEvent(from, error: error)
        #endif
        #if !NETWORK_NO_TESTING_HARNESS
        case .streamUpperHarness(let instance): instance.handleDisconnectedEvent(from, error: error)
        case .datagramUpperHarness(let instance): instance.handleDisconnectedEvent(from, error: error)
        case .newStreamFlowHarness(let instance): instance.handleDisconnectedEvent(from, error: error)
        case .newDatagramFlowHarness(let instance): instance.handleDisconnectedEvent(from, error: error)
        #endif
        #if !NETWORK_EMBEDDED
        case .custom(let container, let index):
            return container.accessUpper(at: index) { $0.handleDisconnectedEvent(from, error: error) }
        #endif
        default: fatalError("Protocol cannot accept handleDisconnectedEvent event")
        }
    }

    func handleNetworkProtocolEvent(_ from: ProtocolInstanceReference, event: NetworkProtocolEvent) {
        switch self.reference {
        case .none: return
        case .udp(let index): context.state.udpInstances[index].handleNetworkProtocolEvent(from, event: event)
        case .ip(let index): context.state.ipInstances[index].handleNetworkProtocolEvent(from, event: event)
        case .tcp(var instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .tls(var instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .tlsEncryptionLevel(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .streamEndpointFlow(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .datagramEndpointFlow(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        #if !NETWORK_NO_SWIFT_QUIC
        case .quicPath(var instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .quicCrypto(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        #endif
        #if !NETWORK_NO_TESTING_HARNESS
        case .streamUpperHarness(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .datagramUpperHarness(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .newStreamFlowHarness(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        case .newDatagramFlowHarness(let instance): instance.handleNetworkProtocolEvent(from, event: event)
        #endif
        #if !NETWORK_EMBEDDED
        case .custom(let container, let index):
            return container.accessUpper(at: index) { $0.handleNetworkProtocolEvent(from, event: event) }
        #endif
        default: fatalError("Protocol cannot accept handleNetworkProtocolEvent call")
        }
    }

}

/// A protocol closer to the network, with a linkage to an upper protocol toward the app.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol LowerProtocolHandler<UpperProtocol>: ~Copyable, ProtocolInstance {
    associatedtype UpperProtocol: UpperProtocolLinkage

    mutating func attachUpperProtocol(
        _ upperProtocol: UpperProtocol,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    mutating func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError)

    mutating func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference)
    mutating func disconnect(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        error: NetworkError?
    )

    mutating func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    )

    func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>?
    func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics?
}

@available(Network 0.1.0, *)
extension ProtocolInstanceReference {
    func connect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) {
        guard !isNone else { return }
        self.handleCallFromUpperProtocol(state: &state) { state in
            switch self.reference {
            case .none: return
            case .udp(let index):
                state.withUDPInstance(index) { instance, state in instance.connect(state: &state, from) }
            case .ip(let index):
                state.withIPInstance(index) { instance, state in instance.connect(state: &state, from) }
            case .tcp(var instance): instance.connect(state: &state, from)
            case .tls(var instance): instance.connect(state: &state, from)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(let instance): instance.connect(state: &state, from)
            case .quicStream(let instance): instance.connect(state: &state, from)
            case .quicDatagram(let instance): instance.connect(state: &state, from)
            case .quicCrypto(let instance): instance.connect(state: &state, from)
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(let instance): instance.connect(state: &state, from)
            case .streamLowerHarness(let instance): instance.connect(state: &state, from)
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index): return container.accessLower(at: index) { $0.connect(state: &state, from) }
            #endif
            default: fatalError("Protocol cannot accept connect call")
            }
        }
    }

    func disconnect(state: inout NetworkContext.State, _ from: ProtocolInstanceReference, error: NetworkError?) {
        guard !isNone else { return }
        self.handleCallFromUpperProtocol(state: &state) { state in
            switch self.reference {
            case .none: return
            case .udp(let index):
                state.withUDPInstance(index) { instance, state in
                    instance.disconnect(state: &state, from, error: error)
                }
            case .ip(let index):
                state.withIPInstance(index) { instance, state in
                    instance.disconnect(state: &state, from, error: error)
                }
            case .tcp(var instance): instance.disconnect(state: &state, from, error: error)
            case .tls(var instance): instance.disconnect(state: &state, from, error: error)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(let instance): instance.disconnect(state: &state, from, error: error)
            case .quicStream(let instance): instance.disconnect(state: &state, from, error: error)
            case .quicDatagram(let instance): instance.disconnect(state: &state, from, error: error)
            case .quicCrypto(let instance): instance.disconnect(state: &state, from, error: error)
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(let instance): instance.disconnect(state: &state, from, error: error)
            case .streamLowerHarness(let instance): instance.disconnect(state: &state, from, error: error)
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return container.accessLower(at: index) { $0.disconnect(state: &state, from, error: error) }
            #endif
            default: fatalError("Protocol cannot accept disconnect call")
            }
        }
    }

    func handleApplicationEvent(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        event: ApplicationEvent
    ) {
        self.handleCallFromUpperProtocol(state: &state) { state in
            switch self.reference {
            case .none: return
            case .udp(let index):
                state.withUDPInstance(index) { instance, state in
                    instance.handleApplicationEvent(state: &state, from, event: event)
                }
            case .ip(let index):
                state.withIPInstance(index) { instance, state in
                    instance.handleApplicationEvent(state: &state, from, event: event)
                }
            case .tcp(var instance): instance.handleApplicationEvent(state: &state, from, event: event)
            case .tls(var instance): instance.handleApplicationEvent(state: &state, from, event: event)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(let instance): instance.handleApplicationEvent(state: &state, from, event: event)
            case .quicStream(let instance): instance.handleApplicationEvent(state: &state, from, event: event)
            case .quicDatagram(let instance): instance.handleApplicationEvent(state: &state, from, event: event)
            case .quicCrypto(let instance): instance.handleApplicationEvent(state: &state, from, event: event)
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(let instance): instance.handleApplicationEvent(state: &state, from, event: event)
            case .streamLowerHarness(let instance): instance.handleApplicationEvent(state: &state, from, event: event)
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return container.accessLower(at: index) { $0.handleApplicationEvent(state: &state, from, event: event) }
            #endif
            default: fatalError("Protocol cannot accept handleApplicationEvent call")
            }
        }
    }

    func attachUpperProtocol<Linkage: UpperProtocolLinkage>(
        _ upperProtocol: Linkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG
        /*
        try self.handleCallFromUpperProtocol(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .udp(let index):
                try state.udpInstances[index].attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .ip(let index):
                try state.ipInstances[index].attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tcp(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tls(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .quicStream(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .quicDatagram(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .quicCrypto(let instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .streamLowerHarness(var instance):
                try instance.attachUpperProtocol(
                    upperProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                try container.accessLower(at: index) { instance throws(NetworkError) in
                    try instance.attachUpperProtocol(
                        upperProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept attachUpperProtocol call")
            }
        }
         */
    }

    func attachUpperStreamProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> OutboundStreamLinkage {
        try self.handleCallFromUpperProtocol(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .tcp(var instance):
                return try instance.attachUpperStreamProtocol(
                    from,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tls(var instance):
                return try instance.attachUpperStreamProtocol(
                    from,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicStream(let instance):
                return try instance.attachUpperStreamProtocol(
                    from,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .quicCrypto(let instance):
                return try instance.attachUpperStreamProtocol(
                    from,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .streamLowerHarness(var instance):
                return try instance.attachUpperStreamProtocol(
                    from,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return try container.accessOutboundStreamHandler(at: index) { instance throws(NetworkError) in
                    try instance.attachUpperStreamProtocol(
                        from,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept attachUpperStreamProtocol call")
            }
        }
    }

    func attachUpperDatagramProtocol(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> DefaultOutboundDatagramLinkage {
        try self.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .udp(let index):
                return try state.withUDPInstance(index) { instance, state throws(NetworkError) in
                    try instance.attachUpperDatagramProtocol(
                        state: &state,
                        from,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            case .ip(let index):
                return try state.withIPInstance(index) { instance, state throws(NetworkError) in
                    try instance.attachUpperDatagramProtocol(
                        state: &state,
                        from,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicDatagram(let instance):
                return try instance.attachUpperDatagramProtocol(
                    state: &state,
                    from,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(var instance):
                return try instance.attachUpperDatagramProtocol(
                    state: &state,
                    from,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return try container.accessOutboundDatagramHandler(at: index) { instance throws(NetworkError) in
                    try instance.attachUpperDatagramProtocol(
                        state: &state,
                        from,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept attachUpperDatagramProtocol call")
            }
        }
    }

    public func attachLowerProtocol<Linkage: LowerProtocolLinkage>(
        _ lowerProtocol: Linkage,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG

        /*
        try self.fromExternal(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .udp(let index):
                try state.udpInstances[index].attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .ip(let index):
                try state.ipInstances[index].attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tcp(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tls(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tlsEncryptionLevel(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .streamEndpointFlow(let instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .datagramEndpointFlow(let instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicPath(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .quicCrypto(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .streamUpperHarness(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .datagramUpperHarness(var instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .newStreamFlowHarness(let instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .newDatagramFlowHarness(let instance):
                try instance.attachLowerProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            case .custom(let container, let index):
                try container.accessUpper(at: index) { instance throws(NetworkError) in
                    try instance.attachLowerProtocol(
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            default: fatalError("Protocol cannot accept attachLowerProtocol call")
            }
        }
         */
    }

    public func attachLowerDatagramProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try self.fromExternal(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .udp(let index):
                try state.withUDPInstance(index) { instance, state throws(NetworkError) in
                    try instance.attachLowerDatagramProtocol(
                        state: &state,
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            case .ip(let index):
                try state.withIPInstance(index) { instance, state throws(NetworkError) in
                    try instance.attachLowerDatagramProtocol(
                        state: &state,
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            case .tcp(var instance):
                try instance.attachLowerDatagramProtocol(
                    state: &state,
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .datagramEndpointFlow(let instance):
                try instance.attachLowerDatagramProtocol(
                    state: &state,
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicPath(let instance):
                try instance.attachLowerDatagramProtocol(
                    state: &state,
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramUpperHarness(var instance):
                try instance.attachLowerDatagramProtocol(
                    state: &state,
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                try container.accessInboundDatagramHandler(at: index) { instance throws(NetworkError) in
                    try instance.attachLowerDatagramProtocol(
                        state: &state,
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept attachLowerDatagramProtocol call")
            }
        }
    }

    public func attachLowerStreamProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        try self.fromExternal(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .tls(var instance):
                try instance.attachLowerStreamProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .tlsEncryptionLevel(var instance):
                try instance.attachLowerStreamProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            case .streamEndpointFlow(let instance):
                try instance.attachLowerStreamProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicCrypto(var instance):
                try instance.attachLowerStreamProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .streamUpperHarness(var instance):
                try instance.attachLowerStreamProtocol(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                try container.accessInboundStreamHandler(at: index) { instance throws(NetworkError) in
                    try instance.attachLowerStreamProtocol(
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept attachLowerStreamProtocol call")
            }
        }
    }

    public func attachLowerStreamProtocolToExistingFlow(
        listener: StreamListenerLinkage,
        flowReference: ProtocolInstanceReference
    ) throws(NetworkError) {
        try self.fromExternal(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            case .tls(var instance):
                try instance.attachLowerStreamProtocolToExistingFlow(listener: listener, flowReference: flowReference)
            case .streamEndpointFlow(let instance):
                try instance.attachLowerStreamProtocolToExistingFlow(listener: listener, flowReference: flowReference)
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                try container.accessInboundStreamHandler(at: index) { instance throws(NetworkError) in
                    try instance.attachLowerStreamProtocolToExistingFlow(
                        listener: listener,
                        flowReference: flowReference
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept attachLowerStreamProtocolToExistingFlow call")
            }
        }
    }

    #if !NETWORK_EMBEDDED
    public func attachLowerProtocolForNewPath(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG

        /*
        try self.fromExternal(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(var instance):
                try instance.attachLowerProtocolForNewPath(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            case .custom(let container, let index):
                return try container.accessManyToMany(at: index) { instance throws(NetworkError) in
                    try instance.attachLowerProtocolForNewPath(
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            default: fatalError("Protocol cannot accept attachLowerProtocolForNewPath call")
            }
        }
         */
    }
    #endif

    public func attachLowerDatagramProtocolForNewPath(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        // TODO: TFPDEBUG
        /*
        try self.fromExternal(state: &context.state) { state throws(NetworkError) in
            switch self.reference {
            case .none: fatalError("Cannot attach to empty protocol")
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(var instance):
                try instance.attachLowerDatagramProtocolForNewPath(
                    lowerProtocol,
                    remote: remote,
                    local: local,
                    parameters: parameters,
                    path: path
                )
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return try container.accessManyToMany(at: index) { instance throws(NetworkError) in
                    try instance.attachLowerProtocolForNewPath(
                        lowerProtocol,
                        remote: remote,
                        local: local,
                        parameters: parameters,
                        path: path
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept attachLowerDatagramProtocolForNewPath call")
            }
        }
         */
    }

    public func detach(state: inout NetworkContext.State, _ from: ProtocolInstanceReference) throws(NetworkError) {
        guard !isNone else { return }

        // Releasing the protocol event state -- and any arena storage for the instance -- has to
        // happen *after* handleCallFromUpperProtocol returns. That bracket holds the instance's
        // event state across the call and touches it again on the way out
        // (finishCallFromUpperProtocol / drainPendingEvents), so releasing it from inside the
        // closure would pull the slot out from under the unwind. Record what to reclaim here and
        // do it below.
        //
        // The payloads are the same concrete instance types the reference enum holds, so
        // reclaiming doesn't go through an existential.
        enum Reclaim {
            case none
            case udp(NetworkStateIndex)
            case ip(NetworkStateIndex)
            case tcp(TCPProtocol.Instance)
            case tls(SwiftTLSProtocol.Instance)
            #if !NETWORK_NO_SWIFT_QUIC
            case quic(QUICProtocol.Instance)
            case quicStream(QUICStreamInstance)
            case quicDatagram(QUICDatagramFlow)
            case quicCrypto(QUICCrypto)
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case datagramLowerHarness(DatagramLowerHarness)
            case streamLowerHarness(StreamLowerHarness)
            #endif
            #if !NETWORK_EMBEDDED
            case custom(container: any ProtocolInstanceContainer, index: Int?)
            #endif
        }
        var reclaim = Reclaim.none

        try self.handleCallFromUpperProtocol(state: &state) { state throws(NetworkError) in
            switch self.reference {
            case .none: return
            case .udp(let index):
                try state.withUDPInstance(index) { instance, state throws(NetworkError) in
                    try instance.detach(state: &state, from)
                }
                reclaim = .udp(index)
            case .ip(let index):
                try state.withIPInstance(index) { instance, state throws(NetworkError) in
                    try instance.detach(state: &state, from)
                }
                reclaim = .ip(index)
            case .tcp(var instance):
                try instance.detach(state: &state, from)
                reclaim = .tcp(instance)
            case .tls(var instance):
                try instance.detach(state: &state, from)
                reclaim = .tls(instance)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(var instance):
                try instance.detach(state: &state, from)
                reclaim = .quic(instance)
            case .quicStream(var instance):
                try instance.detach(state: &state, from)
                reclaim = .quicStream(instance)
            case .quicDatagram(var instance):
                try instance.detach(state: &state, from)
                reclaim = .quicDatagram(instance)
            case .quicCrypto(let instance):
                try instance.detach(state: &state, from)
                reclaim = .quicCrypto(instance)
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(var instance):
                try instance.detach(state: &state, from)
                reclaim = .datagramLowerHarness(instance)
            case .streamLowerHarness(var instance):
                try instance.detach(state: &state, from)
                reclaim = .streamLowerHarness(instance)
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                try container.accessLower(at: index) { instance throws(NetworkError) in
                    try instance.detach(state: &state, from)
                }
                reclaim = .custom(container: container, index: index)
            #endif
            default: fatalError("Protocol cannot accept detach call")
            }
        }

        // The bracket is closed, so the event state is no longer in use and can be released,
        // along with any arena storage for the instance.
        switch reclaim {
        case .none:
            break
        case .udp(let index):
            state.withUDPInstance(index) { instance, state in
                instance.eventManager.unregister(state: &state)
            }
            state.unregisterUDPInstance(index)
        case .ip(let index):
            state.withIPInstance(index) { instance, state in
                instance.eventManager.unregister(state: &state)
            }
            state.unregisterIPInstance(index)
        case .tcp(let instance):
            instance.eventManager.unregister(state: &state)
        case .tls(let instance):
            instance.eventManager.unregister(state: &state)
        #if !NETWORK_NO_SWIFT_QUIC
        case .quic(let instance):
            instance.eventManager.unregister(state: &state)
        case .quicStream(let instance):
            instance.eventManager.unregister(state: &state)
        case .quicDatagram(let instance):
            instance.eventManager.unregister(state: &state)
        case .quicCrypto(let instance):
            instance.eventManager.unregister(state: &state)
        #endif
        #if !NETWORK_NO_TESTING_HARNESS
        case .datagramLowerHarness(let instance):
            instance.eventManager.unregister(state: &state)
        case .streamLowerHarness(let instance):
            instance.eventManager.unregister(state: &state)
        #endif
        #if !NETWORK_EMBEDDED
        case .custom(let container, let index):
            container.unregisterEventManager(at: index, state: &state)
        #endif
        }
    }

    public func getMetadata<P: NetworkProtocol>(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference
    ) -> ProtocolMetadata<P>? {
        self.handleCallFromUpperProtocol(state: &state) { state -> ProtocolMetadata<P>? in
            switch self.reference {
            case .none: return nil
            case .udp(let index):
                return state.withUDPInstance(index) { instance, state -> ProtocolMetadata<P>? in
                    instance.getMetadata(state: &state, from)
                }
            case .ip(let index):
                return state.withIPInstance(index) { instance, state -> ProtocolMetadata<P>? in
                    instance.getMetadata(state: &state, from)
                }
            case .tcp(let instance): return instance.getMetadata(state: &state, from)
            case .tls(let instance): return instance.getMetadata(state: &state, from)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(let instance): return instance.getMetadata(state: &state, from)
            case .quicStream(let instance): return instance.getMetadata(state: &state, from)
            case .quicDatagram(let instance): return instance.getMetadata(state: &state, from)
            case .quicCrypto(let instance): return instance.getMetadata(state: &state, from)
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(let instance): return instance.getMetadata(state: &state, from)
            case .streamLowerHarness(let instance): return instance.getMetadata(state: &state, from)
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index): return container.accessLower(at: index) { $0.getMetadata(state: &state, from) }
            #endif
            default: fatalError("Protocol cannot accept getMetadata call")
            }
        }
    }

    public func getMetrics(
        state: inout NetworkContext.State,
        _ from: ProtocolInstanceReference,
        requestedNetworkMetric: RequestedNetworkMetrics
    ) -> NetworkMetrics? {
        self.handleCallFromUpperProtocol(state: &state) { state -> NetworkMetrics? in
            switch self.reference {
            case .none: return nil
            case .udp(let index):
                return state.withUDPInstance(index) { instance, state -> NetworkMetrics? in
                    instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
                }
            case .ip(let index):
                return state.withIPInstance(index) { instance, state -> NetworkMetrics? in
                    instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
                }
            case .tcp(let instance): return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .tls(let instance): return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quic(let instance): return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .quicStream(let instance):
                return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .quicDatagram(let instance):
                return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .quicCrypto(let instance):
                return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            #endif
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(let instance):
                return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            case .streamLowerHarness(let instance):
                return instance.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return container.accessLower(at: index) {
                    $0.getMetrics(state: &state, from, requestedNetworkMetric: requestedNetworkMetric)
                }
            #endif
            default: fatalError("Protocol cannot accept getMetrics call")
            }
        }
    }
}
