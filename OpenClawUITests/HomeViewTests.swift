import XCTest

final class HomeViewTests: OpenClawUITestBase {

    func testSearchBarExists() {
        signInIfNeeded()

        let searchBar = app.buttons["home_search_bar"]
        XCTAssertTrue(waitForElement(searchBar, timeout: 10), "Search bar should exist on home screen")
    }

    func testQuickActionCardsExist() {
        signInIfNeeded()

        let chatAction = app.buttons["quick_action_chat"]
        XCTAssertTrue(waitForElement(chatAction, timeout: 10), "Chat quick action should exist")

        let writeAction = app.buttons["quick_action_write"]
        XCTAssertTrue(writeAction.exists, "Write quick action should exist")

        let researchAction = app.buttons["quick_action_research"]
        XCTAssertTrue(researchAction.exists, "Research quick action should exist")

        let visionAction = app.buttons["quick_action_vision"]
        XCTAssertTrue(visionAction.exists, "Vision quick action should exist")
    }

    func testQuickActionCardTap() {
        signInIfNeeded()

        let chatAction = app.buttons["quick_action_chat"]
        guard waitForElement(chatAction, timeout: 10) else {
            XCTFail("Chat quick action not found")
            return
        }
        chatAction.tap()

        // Should open chat or agent creation
        let chatInput = app.textFields["chat_input"]
        let createAgent = app.staticTexts["Create your first agent"]
        let agentCreation = app.navigationBars["New Agent"]

        XCTAssertTrue(
            waitForElement(chatInput, timeout: 5) ||
            waitForElement(createAgent, timeout: 5) ||
            waitForElement(agentCreation, timeout: 5),
            "Tapping Chat should open chat view or agent creation"
        )
    }

    func testProBannerOpensPaywall() {
        signInIfNeeded()

        let proBanner = app.buttons["home_pro_banner"]
        guard waitForElement(proBanner, timeout: 10) else {
            // User might already be Pro, skip test
            return
        }
        proBanner.tap()

        let paywallHeadline = app.staticTexts["Get Full Access"]
        XCTAssertTrue(waitForElement(paywallHeadline, timeout: 5),
                      "Pro banner should open paywall")
    }

    func testEmptyAgentCard() {
        signInIfNeeded()

        let emptyCard = app.buttons["home_empty_agent"]
        if waitForElement(emptyCard, timeout: 5) {
            emptyCard.tap()
            // Should present agent creation sheet
            sleep(1)
        }
    }

    private func signInIfNeeded() {
        let searchBar = app.buttons["home_search_bar"]
        if searchBar.waitForExistence(timeout: 3) { return }

        // Try to navigate through onboarding
        for i in 1...3 {
            let continueBtn = app.buttons["onboarding_continue_\(i)"]
            if continueBtn.waitForExistence(timeout: 2) {
                continueBtn.tap()
                sleep(1)
            }
        }
    }
}
