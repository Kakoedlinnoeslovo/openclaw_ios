import XCTest

final class OnboardingFlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testPage1ContinueButton() {
        let continueButton = app.buttons["onboarding_continue_1"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8), "Page 1 Continue button should exist")

        XCTAssertTrue(
            app.staticTexts["daily tasks"].exists || app.staticTexts["Set up AI agents for"].exists,
            "Page 1 headline text should be visible"
        )
    }

    func testNavigateThroughMarketingSteps() {
        XCTAssertTrue(app.buttons["onboarding_continue_1"].waitForExistence(timeout: 8))
        app.buttons["onboarding_continue_1"].tap()

        XCTAssertTrue(app.buttons["onboarding_skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding_skip"].tap()

        XCTAssertTrue(app.buttons["Work"].waitForExistence(timeout: 5))
        app.buttons["Work"].tap()
        app.buttons["onboarding_continue_3"].tap()

        XCTAssertTrue(app.buttons["Coding"].waitForExistence(timeout: 5))
        app.buttons["Coding"].tap()
        app.buttons["onboarding_continue_4"].tap()

        let continue5 = app.buttons["onboarding_continue_5"]
        XCTAssertTrue(continue5.waitForExistence(timeout: 5), "Loading step continue should appear")
        continue5.tap()

        let allSetContinue = app.buttons["onboarding_continue_all_set"]
        XCTAssertTrue(allSetContinue.waitForExistence(timeout: 5), "All set step continue should appear")
        let allSetTitle = app.descendants(matching: .any)["onboarding_all_set_title"]
        XCTAssertTrue(allSetTitle.waitForExistence(timeout: 3), "All set headline should be visible")
        allSetContinue.tap()

        XCTAssertTrue(
            app.staticTexts["Sign in with Apple"].waitForExistence(timeout: 8) ||
                app.buttons["Sign in with Apple"].waitForExistence(timeout: 2),
            "Apple sign-in step should appear"
        )
    }
}
