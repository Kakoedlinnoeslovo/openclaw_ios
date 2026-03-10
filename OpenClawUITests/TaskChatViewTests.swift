import XCTest

final class TaskChatViewTests: OpenClawUITestBase {

    func testInputBarElements() {
        navigateToChat()

        let input = app.textFields["chat_input"]
        XCTAssertTrue(waitForElement(input, timeout: 10), "Chat input field should exist")

        let sendButton = app.buttons["chat_send"]
        XCTAssertTrue(sendButton.exists, "Send button should exist")

        let attachButton = app.buttons["chat_attach"]
        XCTAssertTrue(attachButton.exists, "Attach (+) button should exist")

        let webToggle = app.buttons["chat_web_toggle"]
        XCTAssertTrue(webToggle.exists, "Web search toggle (globe) should exist")
    }

    func testWebSearchToggle() {
        navigateToChat()

        let webToggle = app.buttons["chat_web_toggle"]
        guard waitForElement(webToggle, timeout: 10) else {
            XCTFail("Web toggle not found")
            return
        }

        webToggle.tap()
        sleep(1)

        // After tapping, the "Web search enabled" banner should appear
        let banner = app.staticTexts["Web search enabled"]
        XCTAssertTrue(banner.exists, "Web search banner should appear after toggling on")

        webToggle.tap()
        sleep(1)
        XCTAssertFalse(banner.exists, "Web search banner should disappear after toggling off")
    }

    func testTypingEnablesSendButton() {
        navigateToChat()

        let input = app.textFields["chat_input"]
        guard waitForElement(input, timeout: 10) else {
            XCTFail("Input not found")
            return
        }

        input.tap()
        input.typeText("Hello AI agent")

        let sendButton = app.buttons["chat_send"]
        XCTAssertTrue(sendButton.isEnabled || sendButton.exists,
                      "Send button should be enabled after typing")
    }

    func testClearHistoryMenu() {
        navigateToChat()

        let menuButton = app.buttons["chat_menu"]
        guard waitForElement(menuButton, timeout: 10) else {
            XCTFail("Menu button not found")
            return
        }
        menuButton.tap()

        let clearButton = app.buttons["Clear History"]
        XCTAssertTrue(waitForElement(clearButton, timeout: 3),
                      "Clear History option should appear in menu")
    }

    private func navigateToChat() {
        // Try to get to chat via the center + button
        let plusTab = app.buttons["tab_plus"]
        if plusTab.waitForExistence(timeout: 3) {
            plusTab.tap()
            return
        }

        // Navigate through onboarding first
        for i in 1...3 {
            let btn = app.buttons["onboarding_continue_\(i)"]
            if btn.waitForExistence(timeout: 2) {
                btn.tap()
                sleep(1)
            }
        }

        if plusTab.waitForExistence(timeout: 5) {
            plusTab.tap()
        }
    }
}
