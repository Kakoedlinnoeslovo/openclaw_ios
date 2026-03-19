import XCTest

final class PaywallTests: OpenClawUITestBase {

    func testPaywallElementsExist() {
        navigateToPaywall()

        let headline = app.descendants(matching: .any)["paywall_headline"]
        XCTAssertTrue(waitForElement(headline, timeout: 10), "Paywall headline should exist")

        let trialToggle = app.switches["paywall_trial_toggle"]
        XCTAssertTrue(trialToggle.exists, "Free trial toggle should exist")

        let continueButton = app.buttons["paywall_continue"]
        XCTAssertTrue(continueButton.exists, "Continue button should exist")

        let restore = app.buttons["paywall_restore"]
        XCTAssertTrue(restore.exists, "Restore button should exist")

        XCTAssertTrue(app.descendants(matching: .any)["paywall_footer"].waitForExistence(timeout: 3) ||
            app.buttons["Terms"].exists ||
            app.staticTexts["Terms"].exists,
            "Footer or Terms link should exist")
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

        sleep(1)
        let headline = app.descendants(matching: .any)["paywall_headline"]
        XCTAssertFalse(headline.exists, "Paywall should dismiss")
    }

    private func navigateToPaywall() {
        let homeSettings = app.buttons["home_settings"]
        guard homeSettings.waitForExistence(timeout: 8) else { return }
        homeSettings.tap()

        let upgrade = app.staticTexts["Upgrade to Pro"]
        guard upgrade.waitForExistence(timeout: 5) else { return }
        upgrade.tap()
    }
}
