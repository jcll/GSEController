import XCTest

@MainActor
final class GSEControllerUITests: XCTestCase {
    // Smoke tests only. These intentionally cover one representative flow per
    // high-value UI path so the suite stays useful without becoming the default
    // every-change test lane.
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateEditStartAndSwitchProfile() throws {
        let app = XCUIApplication()
        launch(app)

        let newProfileButton = app.buttons["new-profile-button"]
        XCTAssertTrue(newProfileButton.waitForExistence(timeout: 5))
        newProfileButton.click()

        let blankTemplate = app.buttons["template-blank"]
        XCTAssertTrue(blankTemplate.waitForExistence(timeout: 5))
        blankTemplate.click()

        let nameField = app.textFields["group-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        replaceText(in: nameField, with: "Smoke Profile")

        let saveButton = app.buttons["save-group-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.click()

        let startButton = app.buttons["start-stop-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))
        XCTAssertTrue(startButton.isEnabled)
        startButton.click()

        XCTAssertTrue(waitFor(label: "Stop", on: startButton, timeout: 5))

        let guardianRow = app.descendants(matching: .any)["profile-row-guardian-druid"]
        XCTAssertTrue(guardianRow.waitForExistence(timeout: 2))
        guardianRow.click()

        XCTAssertTrue(waitFor(value: "Guardian Druid", on: nameField, timeout: 5))
        XCTAssertTrue(waitFor(label: "Start", on: startButton, timeout: 5))
    }

    func testUnsavedProfileChangeCanBeCancelledOrDiscarded() throws {
        let app = XCUIApplication()
        launch(app)

        app.buttons["new-profile-button"].click()
        let blankTemplate = app.buttons["template-blank"]
        XCTAssertTrue(blankTemplate.waitForExistence(timeout: 5))
        blankTemplate.click()

        let nameField = app.textFields["group-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        replaceText(in: nameField, with: "Unsaved Smoke")

        let guardianRow = app.descendants(matching: .any)["profile-row-guardian-druid"]
        XCTAssertTrue(guardianRow.waitForExistence(timeout: 5))
        guardianRow.click()

        let cancelButton = app.buttons["unsaved-cancel-button"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.click()
        XCTAssertTrue(waitFor(value: "Unsaved Smoke", on: nameField, timeout: 5))

        guardianRow.click()
        let discardButton = app.buttons["unsaved-discard-button"]
        XCTAssertTrue(discardButton.waitForExistence(timeout: 5))
        discardButton.click()
        XCTAssertTrue(waitFor(value: "Guardian Druid", on: nameField, timeout: 5))
    }

    func testNumericRateEntryUpdatesBindingSummary() throws {
        let app = XCUIApplication()
        launch(app)

        let rateField = app.textFields["binding-rate-field"].firstMatch
        XCTAssertTrue(rateField.waitForExistence(timeout: 5))
        replaceNumber(in: rateField, with: "123")
        XCTAssertTrue(waitFor(value: "123", on: rateField, timeout: 5))
    }

    private func launch(_ app: XCUIApplication) {
        app.launchArguments.append("--uitesting")
        app.launchEnvironment["UITEST_DEFAULTS_SUITE"] = "com.test.gsecontroller.ui.\(UUID().uuidString)"
        app.launch()
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        element.typeText(text)
    }

    private func replaceNumber(in element: XCUIElement, with text: String) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()
        for _ in 0..<8 {
            element.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        }
        element.typeText(text)
        element.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
    }

    private func waitFor(label expectedLabel: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expectedLabel)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitFor(value expectedValue: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitFor(labelContaining expectedSubstring: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", expectedSubstring)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
