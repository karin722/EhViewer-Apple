import EhSettings
import Foundation
import Testing
@testable import ehviewer_apple

@MainActor
struct ReaderGestureGuidanceTests {
    @Test func verticalGuidanceDescribesScrollingWithoutClaimingDoubleTapZoom() {
        let guidance = ReaderGestureGuidance(direction: .topToBottom)
        #expect(guidance.directionTitle == "上→下")
        #expect(guidance.leftPageTitle == "前のページ")
        #expect(guidance.rightPageTitle == "次のページ")
        #expect(!guidance.showsDoubleTapZoom)
        #expect(guidance.motionTitle(for: .touch) == "上下にスクロールして読む")
        #expect(guidance.motionTitle(for: .pointer) == "上下にスクロールして読む")
    }

    @Test func horizontalGuidanceTracksReadingDirectionAndInput() {
        let leftToRight = ReaderGestureGuidance(direction: .leftToRight)
        let rightToLeft = ReaderGestureGuidance(direction: .rightToLeft)
        #expect(leftToRight.directionTitle == "左→右")
        #expect(rightToLeft.directionTitle == "右→左")
        #expect(leftToRight.leftPageTitle == "前のページ")
        #expect(leftToRight.rightPageTitle == "次のページ")
        #expect(rightToLeft.leftPageTitle == "次のページ")
        #expect(rightToLeft.rightPageTitle == "前のページ")
        for guidance in [leftToRight, rightToLeft] {
            #expect(guidance.showsDoubleTapZoom)
            #expect(guidance.motionTitle(for: .touch) == "左右にスワイプしてもページをめくれます")
            #expect(guidance.motionTitle(for: .pointer) == "ホイールまたはトラックパッドでページをめくる")
        }
    }
}

@MainActor
struct ReadingDirectionPersistenceTests {
    @Test func threeSelectableDirectionsWriteTheirOriginalValuesOnlyWhenChanged() {
        #expect(ReadingDirection.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(ReadingDirection.leftToRight.persistedUpdate(from: 3) == 0)
        #expect(ReadingDirection.rightToLeft.persistedUpdate(from: 0) == 1)
        #expect(ReadingDirection.topToBottom.persistedUpdate(from: 1) == 2)
        #expect(ReadingDirection.topToBottom.persistedUpdate(from: 3) == nil)
        #expect(ReadingDirection.rightToLeft.persistedUpdate(from: 1) == nil)
    }

    @Test func registeredFreshDefaultRemainsRightToLeft() throws {
        // Inspect only the volatile registration domain, independent of any saved preferences.
        _ = AppSettings.shared
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        let raw = try #require(registered["reading_direction"] as? Int)
        #expect(raw == 1)
        #expect(ReadingDirection(persistedRawValue: raw) == .rightToLeft)
    }

    @Test func legacyBackupStillRoundTripsWithoutRewritingItsVerticalSelection() throws {
        let suiteName = "EhViewer.ReaderDirectionLegacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let archive = Data(#"{"reading_direction":3}"#.utf8)
        let report = try SettingsBackup.restoreJSON(archive, into: defaults)
        #expect(report.appliedCount == 1)
        let stored = defaults.integer(forKey: "reading_direction")
        let selected = ReadingDirection(persistedRawValue: stored)
        #expect(stored == 3)
        #expect(selected == .topToBottom)
        #expect(selected.persistedUpdate(from: stored) == nil)
        let exported = try SettingsBackup.exportJSON(from: defaults)
        let values = try #require(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        #expect(values["reading_direction"] as? Int == 3)
    }
}
