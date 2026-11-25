import XCTest

final class DetailDownloadManagementUITests: XCTestCase {
    @MainActor func testCompletedDownloadManagementCancellationAndOfflineRead() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["EH_OFFLINE_UI_FIXTURE"] = "1"
        app.launchEnvironment["EH_FIXTURE_LOCAL_READER"] = "1"
        app.launch()

        let row = app.staticTexts["Synthetic Gallery"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let manage = app.buttons["gallery-detail-download"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ダウンロードを管理、ダウンロード済み"), object: manage)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 6), .completed)
        manage.tap()
        let remove = app.buttons["オフラインファイルを削除…"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let confirm = app.alerts["オフラインファイルを削除しますか？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6))
        XCTAssertTrue(confirm.buttons["ダウンロードファイルを削除"].exists)
        confirm.buttons["キャンセル"].tap()
        XCTAssertTrue(manage.waitForExistence(timeout: 6))
        XCTAssertEqual(manage.label, "ダウンロードを管理、ダウンロード済み", "Cancelling must keep the download.")
        manage.tap()
        let offline = app.buttons["オフラインで読む"].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 5))
        offline.tap()
        XCTAssertTrue(app.buttons["reader-close"].waitForExistence(timeout: 8))
    }
}
