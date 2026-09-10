/*
 * SPDX-FileCopyrightText: 2021 Lucas Wang <lucas.wang@tuta.io>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

// Original header below:
//
//  KDE_Connect_Tests.swift
//  KDE Connect Tests
//
//  Created by Lucas Wang on 2021-06-17.
//

import XCTest
@testable import KDE_Connect

// Intentional naming matching app target name
// swiftlint:disable:next type_name
class KDE_Connect_Tests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testScaleRatingMappingUsesNormalizedEndpoints() {
        XCTAssertEqual(ScaleRatingMapping.value(for: 1), 0.0, accuracy: 0.0001)
        XCTAssertEqual(ScaleRatingMapping.value(for: 10), 1.0, accuracy: 0.0001)
    }

    func testScaleRatingMappingRoundsToNearestRating() {
        XCTAssertEqual(ScaleRatingMapping.rating(for: 0.0), 1)
        XCTAssertEqual(ScaleRatingMapping.rating(for: 0.51), 6)
        XCTAssertEqual(ScaleRatingMapping.rating(for: 1.0), 10)
    }

    func testScaleRatingMappingHasTenSelectableRatings() {
        let values = (1...10).map { ScaleRatingMapping.value(for: $0) }
        let expected = [
            0.0, 1.0 / 9.0, 2.0 / 9.0, 3.0 / 9.0, 4.0 / 9.0,
            5.0 / 9.0, 6.0 / 9.0, 7.0 / 9.0, 8.0 / 9.0, 1.0,
        ]

        XCTAssertEqual(values.count, expected.count)
        for (actual, expected) in zip(values, expected) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testWaitingPromptUsesPreviousStationCopy() {
        XCTAssertEqual(
            StationPrompt.normalized("Waiting for your turn"),
            "WAITING FOR PREVIOUS STATION INPUT"
        )
        XCTAssertEqual(
            StationPrompt.normalized("What is your name?"),
            "What is your name?"
        )
    }

    func testFocusControlGateSuppressesControlAndEventDuplicates() {
        var gate = StationFocusControlGate()
        let control: [String: Any] = [
            "ts": 100,
            "src": "station",
            "action": "yesNoFocused",
            "left": "YES",
            "right": "NO",
            "prompt": "Ready?",
            "seq": 4,
        ]
        var duplicate = control
        duplicate["ts"] = 101

        XCTAssertTrue(gate.accept(control))
        XCTAssertFalse(gate.accept(duplicate))
    }

    func testFocusControlGateDropsOlderOutOfOrderControl() {
        var gate = StationFocusControlGate()
        XCTAssertTrue(gate.accept([
            "ts": 200,
            "action": "yesNoFocused",
            "left": "YES",
            "right": "NO",
        ]))
        XCTAssertFalse(gate.accept([
            "ts": 199,
            "action": "textFocused",
        ]))
    }

    func testFocusControlGateAllowsARealLayoutChange() {
        var gate = StationFocusControlGate()
        XCTAssertTrue(gate.accept(["ts": 200, "action": "yesNoFocused", "left": "YES", "right": "NO"]))
        XCTAssertTrue(gate.accept(["ts": 201, "action": "choiceFocused", "left": "LOVE", "right": "SEX"]))
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
}
