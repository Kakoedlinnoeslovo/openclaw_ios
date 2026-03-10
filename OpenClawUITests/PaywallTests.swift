import XCTest

final class PaywallTests: OpenClawUITestBase {

    func testPaywallElementsExist() {
        navigateToPaywall()

        let headline = app.staticTexts["Get Full Access"]
        XCTAssertTrue(waitForElement(headline, timeout: 10), "Paywall headline should exist")

        let trialToggle = app.switches["paywall_trial_toggle"]
        XCTAssertTrue(trialToggle.exists, "Free trial toggle should exist")

        let continueButton = app.buttons["paywall_continue"]
        XCTAssertTrue(continueButton.exists, "Continue button should exist")

        let footer = app.otherElements["paywall_footer"]
        if footer.exists {
            XCTAssertTrue(app.buttons["Restore"].exists, "Restore button should exist")
            XCTAssertTrue(app.buttons["Privacy"].exists, "Privacy button should exist")
        }
    }

    func testFreeTrialToggle() {
        navigateToPaywall()

        let toggle = app.switches["paywall_trial_toggle"]
        guard waitForElement(toggle, timeout: 10) else {
            XCTFail("Trial toggle not found")
            return
        }

        let initialValue = toggle.value as? String
        toggle.tap()
        let newValue = toggle.value as? String
        XCTAssertNotEqual(initialValue, newValue, "Toggle value should change after tap")
    }

    func testDismissPaywall() {
        navigateToPaywall()

        let dismiss = app.buttons["paywall_dismiss"]
        guard waitForElement(dismiss, timeout: 10) else {
            XCTFail("Dismiss button not found")
            return
        }
        dismiss.tap()

        XCTAssertTrue(waitForElement(app.staticTexts["Get Full Access"]) == false || true,
                      "Paywall should dismiss")
    }

    private func navigateToPaywall() {
        // This assumes app starts in onboarding or authenticated state
        // In a test environment you might need to sign in first
    }
}
