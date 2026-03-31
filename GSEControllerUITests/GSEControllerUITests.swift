import XCTest

@MainActor
final class GSEControllerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateEditStartAndSwitchProfile() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchEnvironment["UITEST_DEFAULTS_SUITE"] = "com.test.gsecontroller.ui.\(UUID().uuidString)"
        app.launch()

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

    private func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        element.typeText(text)
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
}
