import AppKit
import XCTest

@MainActor
final class PackagedAcceptanceUITests: XCTestCase {
  func testCleanLaunchInstallsOneDocklessCompanionAndStatusMenu() throws {
    let app = launchApplication()
    defer {
      app.terminate()
    }
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.aneeshsathe.readyplayertwo"
    )
    let runningApplication = try XCTUnwrap(
      runningApplications.first
    )
    XCTAssertEqual(runningApplications.count, 1)
    XCTAssertEqual(
      runningApplication.activationPolicy,
      NSApplication.ActivationPolicy.accessory
    )

    let companion = app.groups["companion.stage"]
    XCTAssertTrue(companion.waitForExistence(timeout: 5))
    XCTAssertEqual(
      app.groups.matching(identifier: "companion.stage").count,
      1
    )

    let statusItem = app.statusItems["status.menu"]
    XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
    statusItem.click()
    XCTAssertTrue(app.menuItems["status.conversation"].exists)
  }

  func testStatusMenuControlsCompanionAndUnavailableVoiceThenQuits() {
    let app = launchApplication()
    defer {
      if app.state != .notRunning {
        app.terminate()
      }
    }
    let companion = app.groups["companion.stage"]
    XCTAssertTrue(companion.waitForExistence(timeout: 5))
    XCTAssertEqual(companion.value as? String, "Orion, Roaming")

    chooseStatusMenuItem("status.park", in: app)
    waitForValue("Orion, Parked", of: companion)

    chooseStatusMenuItem("status.roam", in: app)
    waitForValue("Orion, Roaming", of: companion)

    chooseStatusMenuItem("status.hide-or-show", in: app)
    waitForNonexistence(of: companion)

    chooseStatusMenuItem("status.hide-or-show", in: app)
    XCTAssertTrue(companion.waitForExistence(timeout: 5))
    waitForValue("Orion, Roaming", of: companion)

    openStatusMenu(in: app)
    let companionMenu = app.menuItems["status.companion"]
    XCTAssertTrue(companionMenu.waitForExistence(timeout: 2))
    companionMenu.hover()
    let athenaItem = app.menuItems["status.avatar.athena"]
    XCTAssertTrue(athenaItem.waitForExistence(timeout: 2))
    athenaItem.click()
    waitForValue("Athena, Roaming", of: companion)

    chooseStatusMenuItem("status.conversation", in: app)
    let conversation = app.groups["conversation.bubble"]
    XCTAssertTrue(conversation.waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.buttons["conversation.retry"].waitForExistence(timeout: 5)
    )

    let endButton = app.buttons["conversation.end"]
    XCTAssertTrue(endButton.exists)
    endButton.click()
    waitForNonexistence(of: conversation)

    chooseStatusMenuItem("status.quit", in: app)
    let quitExpectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { [weak app] _, _ in
        app?.state == .notRunning
      },
      object: nil
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [quitExpectation], timeout: 5),
      .completed
    )
  }

  private func launchApplication() -> XCUIApplication {
    continueAfterFailure = false

    let app = XCUIApplication()
    app.launchArguments = ["-ReadyPlayerTwoPackagedAcceptance"]
    app.launchEnvironment = [
      "READYPLAYERTWO_VOICE_CONFIGURED": "0"
    ]
    app.launch()
    return app
  }

  private func chooseStatusMenuItem(
    _ identifier: String,
    in app: XCUIApplication
  ) {
    openStatusMenu(in: app)
    let item = app.menuItems[identifier]
    XCTAssertTrue(item.waitForExistence(timeout: 2))
    item.click()
  }

  private func openStatusMenu(in app: XCUIApplication) {
    let statusItem = app.statusItems["status.menu"]
    XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
    statusItem.click()
  }

  private func waitForValue(
    _ value: String,
    of element: XCUIElement
  ) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", value),
      object: element
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 5),
      .completed
    )
  }

  private func waitForNonexistence(of element: XCUIElement) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: element
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 5),
      .completed
    )
  }
}
