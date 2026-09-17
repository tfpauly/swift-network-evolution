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

#if !NETWORK_NO_SWIFT_QUIC

import XCTest

#if canImport(SwiftNetwork)
@_spi(Essentials) @_spi(ProtocolProvider) @testable import SwiftNetwork
#elseif canImport(Network)
@_spi(Essentials) @_spi(ProtocolProvider) @testable import Network
#endif

@_spi(TestHarness) @_spi(Essentials) @_spi(ProtocolProvider) import SwiftNetworkTestHarness

@available(Network 0.1.0, *)
class QUICPathValidationMessageTests: XCTestCase {
    let logString = "PathValidationTests"
    var connection: QUICConnection<TestQUICLinkageFamilies>!
    var path: QUICTestPath!  // NOTE: This path immediately transitions to cid assigned due to setup()

    override func setUp() {
        connection = QUICConnection<TestQUICLinkageFamilies>(context: NetworkContext.implicitContext)
        path = connection.context.onQueue {
            QUICTestPath.makeFromExternal(parent: self.connection)
        }
        path.set(interface: nil, priority: 0, isInitial: true)
        path.assignDCID(QUICConnectionID(8))
    }

    func testIncomingPathChallenge() {
        // challenge received from a path that is not validated
        let challenge = FramePathChallenge(data: 1)
        XCTAssertEqual(path.challengesSent, 0)
        connection
            .handlePathChallengeFrame(challenge, path: path)
        XCTAssertEqual(path.pendingInboundChallenges.count, 1)
        XCTAssertEqual(path.state, .probing)
        XCTAssertEqual(path.pendingOutboundChallenges.count, 0)

        // challenge received on a path that is validated, should just generate response
        path.changeState(to: .validated)
        let challenge2 = FramePathChallenge(data: 2)
        connection
            .handlePathChallengeFrame(challenge2, path: path)
        // pending challenges are not cleared until they are processed
        XCTAssertEqual(path.pendingInboundChallenges.count, 2)
        XCTAssertEqual(path.state, .validated)  // we remain validated when the peer re-probes
    }

    func testOutgoingPathChallenge() {
        self.connection.context.onQueue {
            XCTAssertEqual(path.state, .cidAssigned)

            let startTime = NetworkClock.Instant.now
            var pendingItems = PendingItems(packetNumberSpace: .applicationData)
            connection.fromExternal { state in path.addPendingItems(state: &state, &pendingItems, now: startTime) }  // should be empty
            XCTAssertTrue(pendingItems.pathChallenges.isEmpty)
            XCTAssertTrue(pendingItems.pathResponses.isEmpty)

            // Add incoming and outgoing challenges. These will produce path-specific PendingItems
            path.beginValidation()
            XCTAssertEqual(path.state, .probing)
            XCTAssertEqual(path.pendingOutboundChallenges.count, 0)
            path.handlePathChallenge(1)
            XCTAssertEqual(path.pendingInboundChallenges.count, 1)
            connection.fromExternal { state in path.addPendingItems(state: &state, &pendingItems, now: startTime) }

            XCTAssertFalse(pendingItems.pathChallenges.isEmpty)
            XCTAssertFalse(pendingItems.pathResponses.isEmpty)
            XCTAssertEqual(path.pendingInboundChallenges.count, 0)

            let outboundChallenge = pendingItems.pathChallenges.first?.data ?? 0

            XCTAssertEqual(path.lastChallengeSentTime, startTime)
            XCTAssertEqual(path.nextChallengeDuration, .milliseconds(250))

            pendingItems = PendingItems(packetNumberSpace: .applicationData)  // clear items
            // simulate send on the path before the challenge retransmission time is met
            var interval = NetworkDuration.milliseconds(100)
            connection.fromExternal { state in path.addPendingItems(state: &state, &pendingItems, now: startTime + interval) }
            XCTAssertTrue(pendingItems.pathChallenges.isEmpty)
            XCTAssertTrue(pendingItems.pathResponses.isEmpty)

            // simulate a retransmission of the challenge
            interval = NetworkDuration.milliseconds(250)
            connection.fromExternal { state in path.addPendingItems(state: &state, &pendingItems, now: startTime + interval) }
            XCTAssertFalse(pendingItems.pathChallenges.isEmpty)
            XCTAssertTrue(pendingItems.pathResponses.isEmpty)

            connection.fromExternal { state in
                path.handlePathChallengeResponse(state: &state, outboundChallenge)
            }
            XCTAssertEqual(path.state, .validated)
            XCTAssertEqual(path.pendingOutboundChallenges.count, 0)
        }
    }
}

#endif
