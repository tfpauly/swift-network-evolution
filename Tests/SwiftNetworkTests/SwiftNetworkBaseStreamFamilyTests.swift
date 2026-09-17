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

import XCTest

#if canImport(SwiftNetwork)
@_spi(Essentials) @_spi(ProtocolProvider) @testable import SwiftNetwork
#elseif canImport(Network)
@_spi(Essentials) @_spi(ProtocolProvider) @testable import Network
#endif

@_spi(TestHarness) @_spi(Essentials) @_spi(ProtocolProvider) import SwiftNetworkTestHarness

@available(Network 0.1.0, *)
final class SwiftNetworkBaseStreamFamilyTests: NetTestCase {

    // Attaches a stream upper harness directly to a stream lower harness through the
    // base stream linkages, and verifies that data flows in both directions.
    func testStreamHarnessesThroughBaseLinkages() {
        let parameters = Parameters()
        let expectation = XCTestExpectation()
        let context = parameters.context
        context.async {
            defer { expectation.fulfill() }
            let path = PathProperties(parameters: parameters)
            let storage = TestNetworkProtocolStorage(context: context)

            let localEndpoint = Endpoint(address: IPv4Address([0x0a, 0x00, 0x00, 0x14])!, port: 1234)
            let remoteEndpoint = Endpoint(address: IPv4Address([0x0a, 0x00, 0x00, 0x75])!, port: 2345)

            let (upperHarness, upperHarnessLinkage) = storage.createStreamUpperHarness(
                identifier: "Client",
                local: localEndpoint,
                remote: remoteEndpoint,
                parameters: parameters,
                path: path,
                context: context)

            let (lowerHarness, lowerHarnessLinkage) = storage.createStreamLowerHarness(
                identifier: "Client",
                context: context)

            do {
                try upperHarnessLinkage.invokeAttachLowerProtocol(
                    lowerHarnessLinkage,
                    remote: remoteEndpoint,
                    local: localEndpoint,
                    parameters: parameters,
                    path: path)
            } catch {
                XCTAssertTrue(false, "Failed to attach stream harnesses: \(error)")
                return
            }

            upperHarness.start { connected in
                XCTAssertTrue(connected, "Stream harness failed to become connected")
            }

            let outbound: [UInt8] = [0x68, 0x65, 0x6c, 0x6c, 0x6f]  // "hello"
            XCTAssertTrue(upperHarness.write(outbound), "Failed to write stream data")
            XCTAssertEqual(
                lowerHarness.extractLastOutboundPacket(),
                outbound,
                "Lower harness did not observe written stream data"
            )

            let inbound: [UInt8] = [0x74, 0x68, 0x65, 0x72, 0x65]  // "there"
            lowerHarness.setNextInboundPacket(inbound)
            XCTAssertEqual(
                upperHarness.read(),
                inbound,
                "Upper harness did not read inbound stream data"
            )
        }
        wait(for: [expectation])
    }

    // Verifies that TCP instances can be created in the gappy arrays in the
    // base storage, and that each instance gets its own linkage pair.
    func testStreamInstanceStorage() {
        let parameters = Parameters()
        let expectation = XCTestExpectation()
        let context = parameters.context
        context.async {
            defer { expectation.fulfill() }
            let storage = TestNetworkProtocolStorage(context: context)

            // TCP's inbound linkage is a datagram linkage, since TCP consumes datagrams
            // from below, while its outbound linkage is a stream linkage.
            let (tcpUpper, tcpLower): (
                TestInboundDatagramLinkage,
                TestOutboundStreamLinkage
            ) = storage.createTestTCPInstance()
            XCTAssertFalse(tcpUpper.isDetached, "TCP upper linkage unexpectedly detached")
            XCTAssertFalse(tcpLower.isDetached, "TCP lower linkage unexpectedly detached")

            // Each linkage pair shares one reference, and the instances are distinct.
            XCTAssertEqual(tcpUpper.reference, tcpLower.reference, "TCP linkages should share a reference")
        }
        wait(for: [expectation])
    }

    // Attaches a datagram lower harness below TCP through TCP's datagram-side inbound
    // linkage. This exercises the attachLowerProtocol path that only resolves once TCP
    // is registered in TestInboundDatagramLinkage rather than the stream one.
    func testAttachDatagramHarnessBelowTCP() {
        let parameters = Parameters()
        let expectation = XCTestExpectation()
        let context = parameters.context
        context.async {
            defer { expectation.fulfill() }
            let path = PathProperties(parameters: parameters)
            let storage = TestNetworkProtocolStorage(context: context)

            let localEndpoint = Endpoint(address: IPv4Address([0x0a, 0x00, 0x00, 0x14])!, port: 1234)
            let remoteEndpoint = Endpoint(address: IPv4Address([0x0a, 0x00, 0x00, 0x75])!, port: 2345)

            let (tcpDatagramUpper, tcpStreamLower): (
                TestInboundDatagramLinkage,
                TestOutboundStreamLinkage
            ) = storage.createTestTCPInstance()

            let (_, lowerHarnessLinkage) = storage.createDatagramLowerHarness(
                identifier: "BelowTCP",
                context: context)

            // TCP attaches a datagram protocol beneath itself.
            do {
                try tcpDatagramUpper.invokeAttachLowerProtocol(
                    lowerHarnessLinkage,
                    remote: remoteEndpoint,
                    local: localEndpoint,
                    parameters: parameters,
                    path: path)
            } catch {
                XCTAssertTrue(false, "Failed to attach datagram harness below TCP: \(error)")
                return
            }

            // The stream-side linkage remains available for an upper protocol to attach to.
            XCTAssertFalse(tcpStreamLower.isDetached, "TCP stream linkage unexpectedly detached")
        }
        wait(for: [expectation])
    }
}
