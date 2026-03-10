import XCTest

final class TabBarTests: OpenClawUITestBase {

    func testAllTabsExist() {
        signInIfNeeded()

        let homeTab = app.buttons["tab_home"]
        XCTAssertTrue(waitForElement(homeTab, timeout: 10), "Home tab should exist")

        let plusTab = app.buttons["tab_plus"]
        XCTAssertTrue(plusTab.exists, "Center + tab should exist")

        let historyTab = app.buttons["tab_history"]
        XCTAssertTrue(historyTab.exists, "History tab should exist")
    }

    func testSwitchToHistoryTab() {
        signInIfNeeded()

        let historyTab = app.buttons["tab_history"]
        guard waitForElement(historyTab, timeout: 10) else {
            XCTFail("History tab not found")
            return
        }
        historyTab.tap()

        // Should show History view
        let historyTitle = app.navigationBars["History"]
        let emptyState = app.otherElements["history_empty"]
        XCTAssertTrue(
            waitForElement(historyTitle, timeout: 5) || waitForElement(emptyState, timeout: 5),
            "History view should appear after tapping History tab"
        )
    }

    func testCenterPlusButton() {
        signInIfNeeded()

        let plusTab = app.buttons["tab_plus"]
        guard waitForElement(plusTab, timeout: 10) else {
            XCTFail("Center + button not found")
            return
        }
        plusTab.tap()

        // Should open quick chat or agent creation
        let chatInput = app.textFields["chat_input"]
        let agentCreation = app.staticTexts["Create your first agent"]

        sleep(2)
        XCTAssertTrue(
            chatInput.exists || agentCreation.exists || app.navigationBars.count > 0,
            "Center + should open chat or creation flow"
        )
    }

    func testSwitchBackToHome() {
        signInIfNeeded()

        let historyTab = app.buttons["tab_history"]
        guard waitForElement(historyTab, timeout: 10) else { return }
        historyTab.tap()
        sleep(1)

        let homeTab = app.buttons["tab_home"]
        homeTab.tap()
        sleep(1)

        let searchBar = app.buttons["home_search_bar"]
        XCTAssertTrue(waitForElement(searchBar, timeout: 5),
                      "Home view should reappear after switching back")
    }

    private func signInIfNeeded() {
        let homeTab = app.buttons["tab_home"]
        if homeTab.waitForExistence(timeout: 3) { return }

        for i in 1...3 {
            let btn = app.buttons["onboarding_continue_\(i)"]
            if btn.waitForExistence(timeout: 2) {
                btn.tap()
                sleep(1)
            }
        }
    }
}
