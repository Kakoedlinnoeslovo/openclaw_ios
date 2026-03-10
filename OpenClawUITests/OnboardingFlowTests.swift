import XCTest

final class OnboardingFlowTests: OpenClawUITestBase {

    func testPage1ContinueButton() {
        let continueButton = app.buttons["onboarding_continue_1"]
        XCTAssertTrue(waitForElement(continueButton), "Page 1 Continue button should exist")

        XCTAssertTrue(app.staticTexts["Find Answers to"].exists || app.staticTexts["Your Questions"].exists,
                      "Page 1 headline text should be visible")
    }

    func testNavigateThroughAllPages() {
        let continue1 = app.buttons["onboarding_continue_1"]
        XCTAssertTrue(waitForElement(continue1))
        continue1.tap()

        let continue2 = app.buttons["onboarding_continue_2"]
        XCTAssertTrue(waitForElement(continue2), "Page 2 Continue button should appear")

        XCTAssertTrue(app.staticTexts["Smart AI-Agents"].exists,
                      "Page 2 headline should be visible")
        continue2.tap()

        let continue3 = app.buttons["onboarding_continue_3"]
        XCTAssertTrue(waitForElement(continue3), "Page 3 Continue button should appear")

        XCTAssertTrue(app.staticTexts["OpenClaw"].exists,
                      "Page 3 app name should be visible")
        continue3.tap()

        let signUpText = app.staticTexts["Create account"]
        let signInText = app.staticTexts["Welcome back"]
        XCTAssertTrue(waitForElement(signUpText) || waitForElement(signInText),
                      "Sign up page should appear after page 3")
    }
}
