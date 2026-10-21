//
//  ┌───────────────────────────────────────────────────────┐
//  │                   S W I F T M I K O                   │
//  │  Swift-Native Multi-Vendor Network Device Automation  │
//  └───────────────────────────────────────────────────────┘
//
//  Author & Maintainer: K.K. Campbell
//  Created with the assistance of Claude Sonnet 5 (Anthropic),
//  via Claude Code.
//
// Tests/SwiftmikoCLITests/SSHConnTests.swift
//
// Coverage for partitionResults() — previously untested. sshConn()/
// runDeviceTasks() themselves need a live (or injectable) device
// connection and aren't covered here; partitionResults() is the pure
// part of SSHConn.swift, splitting a name->output map by whether the
// output is the sentinel error string sshConn() returns on failure.

import XCTest
@testable import SwiftmikoCLI

final class SSHConnTests: XCTestCase {

    func testPartitionResultsSeparatesSuccessesFromFailures() {
        let results = [
            "rtr1": "show version output",
            "rtr2": errorPattern,
            "rtr3": "another real output",
        ]
        let (valid, failed) = partitionResults(results)

        XCTAssertEqual(valid, ["rtr1": "show version output", "rtr3": "another real output"])
        XCTAssertEqual(failed, ["rtr2"])
    }

    func testPartitionResultsWithAllSuccessesHasNoFailures() {
        let results = ["rtr1": "output one", "rtr2": "output two"]
        let (valid, failed) = partitionResults(results)
        XCTAssertEqual(valid, results)
        XCTAssertTrue(failed.isEmpty)
    }

    func testPartitionResultsWithAllFailuresHasNoValidEntries() {
        let results = ["rtr1": errorPattern, "rtr2": errorPattern]
        let (valid, failed) = partitionResults(results)
        XCTAssertTrue(valid.isEmpty)
        XCTAssertEqual(Set(failed), ["rtr1", "rtr2"])
    }

    func testPartitionResultsOnEmptyInputReturnsEmptyOutputs() {
        let (valid, failed) = partitionResults([:])
        XCTAssertTrue(valid.isEmpty)
        XCTAssertTrue(failed.isEmpty)
    }

    func testPartitionResultsClassifiesAnyOutputEqualToTheSentinelAsFailed() {
        // Documents current behavior, not a recommendation: a device
        // whose real command output happens to equal the exact sentinel
        // string is indistinguishable from a connection failure, since
        // partitionResults only does a string equality check.
        let (valid, failed) = partitionResults(["rtr1": errorPattern])
        XCTAssertTrue(valid.isEmpty)
        XCTAssertEqual(failed, ["rtr1"])
    }
}
