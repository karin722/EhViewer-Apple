import EhDatabase
import EhSettings
import SwiftUI
import UniformTypeIdentifiers

/// Separate from the existing Apple settings JSON import.
struct AndroidLibraryImportControl: View {
    @State private var showsFilePicker = false
    @State private var isWorking = false
    @State private var preview: Preview?
    @State private var showsOutcome = false
    @State private var outcomeTitle = ""
    @State private var outcomeBody = ""

    private struct Preview: Identifiable, Sendable {
        let id = UUID()
        let source: AndroidLibraryImport
        let summary: AndroidLibraryImportSummary
        let historyLimit: Int
    }

    var body: some View {
        Button {
            #if EH_OFFLINE_UI_FIXTURE && targetEnvironment(simulator)
            if let fixture = EhOfflineUIFixture.injectedImportURL {
                preparePreview(fixture)
                return
            }
            #endif
            showsFilePicker = true
        } label: {
            HStack {
                Text("Android からお気に入りと履歴をインポート")
                if isWorking { ProgressView().controlSize(.small) }
            }
        }
        .accessibilityIdentifier("settings-android-library-import")
        .disabled(isWorking)
        // Some file providers mark SQLite exports as generic data. Validate
        // inside the importer rather than relying on extension/UTI alone.
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): preparePreview(url)
            case .failure: showFailure(.cannotRead)
            }
        }
        .sheet(item: $preview, onDismiss: {
            // Present results only after the sheet finishes dismissing, including
            // the case where the transaction returns before its animation.
            if !outcomeTitle.isEmpty { showsOutcome = true }
        }) { candidate in
            NavigationStack {
                Form {
                    Section {
                        Text("Android 版のローカルお気に入りと閲覧履歴のみをインポートし、Apple 版の既存レコードは上書きしません。ブックマーク、ダウンロードファイル、アカウント情報はインポートしません。")
                    }
                    Section("インポートのプレビュー") {
                        LabeledContent("ローカルお気に入り", value: Self.describe(candidate.summary.favorites))
                        LabeledContent("閲覧履歴", value: Self.describe(candidate.summary.history))
                        if candidate.summary.history.overHistoryLimit > 0 {
                            Text("\(candidate.summary.history.overHistoryLimit) 件の履歴が現在の上限（\(candidate.historyLimit) 件）を超えているため、今回はインポートされません。先に詳細設定で上限を引き上げることができます。")
                                .foregroundStyle(.secondary)
                        }
                        Text("インポートで既存の履歴は削除されません。インポート後の通常の閲覧も履歴の上限に従います。")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Android のデータをインポート")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { preview = nil }
                            .disabled(isWorking)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("インポート") { apply(candidate) }
                            .disabled(isWorking || candidate.summary.importableCount == 0)
                    }
                }
                .interactiveDismissDisabled(isWorking)
            }
        }
        .alert(outcomeTitle, isPresented: $showsOutcome) {
            Button("OK", role: .cancel) { outcomeTitle = "" }
        } message: {
            Text(outcomeBody)
        }
    }

    private static func describe(_ counts: AndroidLibraryImportCounts) -> String {
        "新規 \(counts.new) · 既存 \(counts.existing) · 無効 \(counts.invalid)"
    }

    private func preparePreview(_ url: URL) {
        guard !isWorking else { return }
        isWorking = true
        outcomeTitle = ""
        let historyLimit = AppSettings.shared.historyInfoSize
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let (source, summary) = try await Task.detached(priority: .userInitiated) {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw AndroidLibraryImportError.cannotRead
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let source = try AndroidLibraryImport(exportAt: url)
                    let summary = try EhDatabase.shared.previewAndroidLibrary(source, historyLimit: historyLimit)
                    return (source, summary)
                }.value
                preview = Preview(source: source, summary: summary, historyLimit: historyLimit)
            } catch {
                showFailure((error as? AndroidLibraryImportError) ?? .destinationUnavailable)
            }
        }
    }

    private func apply(_ candidate: Preview) {
        guard !isWorking else { return }
        isWorking = true
        let historyLimit = AppSettings.shared.historyInfoSize
        Task { @MainActor in
            defer { isWorking = false; preview = nil }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try EhDatabase.shared.importAndroidLibrary(candidate.source, historyLimit: historyLimit)
                }.value
                if summary.favorites.new > 0 {
                    GalleryActionService.shared.localFavoritesDidImport()
                }
                if summary.history.new > 0 {
                    NotificationCenter.default.post(name: .galleryHistoryChanged, object: nil)
                }
                outcomeTitle = summary.importableCount > 0 ? "インポート完了" : "新しいレコードはありません"
                outcomeBody = "ローカルお気に入り：\(Self.describe(summary.favorites))\n閲覧履歴：\(Self.describe(summary.history))"
                if summary.history.overHistoryLimit > 0 {
                    outcomeBody += "\nほかに \(summary.history.overHistoryLimit) 件の履歴が上限を超えたため、インポートされませんでした。"
                }
            } catch {
                outcomeTitle = "インポートできませんでした"
                outcomeBody = AndroidLibraryImportError.destinationUnavailable.localizedDescription
            }
        }
    }

    private func showFailure(_ error: AndroidLibraryImportError) {
        outcomeTitle = "インポートできませんでした"
        outcomeBody = error.localizedDescription
        showsOutcome = true
    }
}
