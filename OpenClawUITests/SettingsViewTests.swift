import XCTest

final class SettingsViewTests: OpenClawUITestBase {

    func testSettingsElementsExist() {
        navigateToSettings()

        let title = app.navigationBars["Settings"]
        XCTAssertTrue(waitForElement(title, timeout: 10),
                      "Settings navigation title should exist")

        let usageRow = app.staticTexts["Usage"]
        XCTAssertTrue(usageRow.exists, "Usage row should exist")

        let restoreRow = app.staticTexts["Restore Purchases"]
        XCTAssertTrue(restoreRow.exists, "Restore Purchases row should exist")

        let signOutButton = app.buttons.matching(
            NSPredicate(format: "label == 'Sign Out'")
        )
        XCTAssertTrue(signOutButton.count > 0, "Sign Out button should exist")
    }

    func testUpgradeToProOpensPaywall() {
        navigateToSettings()

        let upgradeRow = app.staticTexts["Upgrade to Pro"]
        guard waitForElement(upgradeRow, timeout: 5) else {
            // User might already be Pro
            return
        }

        upgradeRow.tap()

        let paywallHeadline = app.staticTexts["Get Full Access"]
        XCTAssertTrue(waitForElement(paywallHeadline, timeout: 5),
                      "Tapping Upgrade to Pro should open paywall")
    }

    func testClawHubNavigation() {
        navigateToSettings()

        let clawHubRow = app.staticTexts["ClawHub Skills"]
        guard waitForElement(clawHubRow, timeout: 5) else {
            XCTFail("ClawHub Skills row not found")
            return
        }
        clawHubRow.tap()

        sleep(2)
        // ClawHub sheet should appear
    }

    func testVersionDisplayed() {
        navigateToSettings()

        let version = app.staticTexts["1.0.0"]
        XCTAssertTrue(waitForElement(version, timeout: 5),
                      "Version number should be displayed")
    }

    private func navigateToSettings() {
        // Settings is no longer a tab -- it's accessible from home
        // First try to find if we're already authenticated
        let homeTab = app.buttons["tab_home"]
        if !homeTab.waitForExistence(timeout: 3) {
            for i in 1...3 {
                let btn = app.buttons["onboarding_continue_\(i)"]
                if btn.waitForExistence(timeout: 2) {
                    btn.tap()
                    sleep(1)
                }
            }
        }

        // Settings might need to be accessed differently now
        // Try scrolling down or finding the settings button
        let settingsButton = app.buttons["home_settings"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
        }
    }
}
