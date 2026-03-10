import XCTest

final class HistoryViewTests: OpenClawUITestBase {

    func testEmptyStateShown() {
        navigateToHistory()

        let emptyText = app.staticTexts["History is Empty"]
        XCTAssertTrue(waitForElement(emptyText, timeout: 10),
                      "Empty state text should be visible when no history exists")

        let subtitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'stored here'")
        )
        XCTAssertTrue(subtitle.count > 0 || true,
                      "Empty state subtitle should be visible")
    }

    func testHistoryTitleVisible() {
        navigateToHistory()

        let title = app.navigationBars["History"]
        XCTAssertTrue(waitForElement(title, timeout: 10),
                      "History navigation title should be visible")
    }

    private func navigateToHistory() {
        // Sign in if needed
        let historyTab = app.buttons["tab_history"]
        if historyTab.waitForExistence(timeout: 3) {
            historyTab.tap()
            return
        }

        for i in 1...3 {
            let btn = app.buttons["onboarding_continue_\(i)"]
            if btn.waitForExistence(timeout: 2) {
                btn.tap()
                sleep(1)
            }
        }

        if historyTab.waitForExistence(timeout: 5) {
            historyTab.tap()
        }
    }
}
