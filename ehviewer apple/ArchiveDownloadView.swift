//
//  ArchiveDownloadView.swift
//  ehviewer apple
//
//  归档下载 — 对齐 Android GalleryDetailScene 的「Download Archive」对话框
//  (issue #3「希望增加与原版一样的下载到 h@h 选项卡」)
//
//  两条路径，对应页面上的两块内容：
//    · H@H 下载 — 把任务派给你自己的 H@H 客户端，由它在后台落盘，不消耗 GP
//    · 归档下载 — 服务端现打一个 zip，消耗 GP / Credits，拿到直链后交给系统下载
//

import SwiftUI
import EhModels
import EhAPI
import EhSettings

struct ArchiveDownloadView: View {
    let gid: Int64
    let token: String
    /// 详情页解析出的 archiver_key 链接
    let archiveUrl: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isLoading = true
    @State private var loadError: String?

    // H@H
    @State private var paramOr = ""
    @State private var resolutions: [ArchiveResolution] = []
    @State private var dispatchingRes: String?
    @State private var hathMessage: HathMessage?

    // Archiver
    @State private var archiver: ArchiverData?
    @State private var preparingKind: ArchiverKind?
    @State private var readyLink: ReadyLink?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("アーカイブ情報を読み込み中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("アーカイブ情報を読み込めません", systemImage: "archivebox")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("再試行") { Task { await load() } }
                    }
                } else {
                    form
                }
            }
            .navigationTitle("アーカイブダウンロード")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await load() }
            .alert(item: $hathMessage) { message in
                Alert(title: Text(message.title),
                      message: Text(message.body),
                      dismissButton: .default(Text("OK")))
            }
            .sheet(item: $readyLink) { link in
                ArchiveLinkSheet(link: link)
            }
        }
    }

    // MARK: - 表单

    private var form: some View {
        Form {
            // 访客看到的是两块空壳，得说清楚为什么
            if !AppSettings.shared.isLogin {
                Section {
                    Label("アーカイブと H@H はアカウントにログインしないと利用できません。", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if resolutions.isEmpty {
                    Text(AppSettings.shared.isLogin
                         ? "このギャラリーには利用可能な H@H の形式がありません"
                         : "ログインすると選択可能な形式が表示されます")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(resolutions) { item in
                        Button {
                            Task { await dispatchToHath(item) }
                        } label: {
                            HStack {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if dispatchingRes == item.res {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .disabled(dispatchingRes != nil)
                    }
                }
            } header: {
                Text("H@H ダウンロード")
            } footer: {
                Text("タスクはアカウントに紐付けられた H@H クライアントに送られ、バックグラウンドでダウンロードされます。GP は消費しません。事前にサイト上で H@H クライアントを紐付けておく必要があります。")
            }

            if let archiver {
                Section {
                    archiverRow(.original, cost: archiver.originalCost, size: archiver.originalSize,
                                url: archiver.originalUrl)
                    archiverRow(.resample, cost: archiver.resampleCost, size: archiver.resampleSize,
                                url: archiver.resampleUrl)
                } header: {
                    Text("アーカイブダウンロード")
                } footer: {
                    if let funds = archiver.funds, !funds.isEmpty {
                        Text("残高：\(funds)")
                    } else {
                        Text("サーバー側でその場でアーカイブを作成するため、GP または Credits を消費します。")
                    }
                }
            }
        }
    }

    private func archiverRow(_ kind: ArchiverKind, cost: String?, size: String?, url: String?) -> some View {
        Button {
            guard let url else { return }
            Task { await prepareArchive(kind: kind, formUrl: url) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .foregroundStyle(url == nil ? .secondary : .primary)
                    let detail = [size, cost].compactMap { $0 }.filter { !$0.isEmpty }
                    Text(detail.isEmpty ? "利用不可" : detail.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if preparingKind == kind {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(url == nil || preparingKind != nil)
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        loadError = nil

        // 两块内容来自同一个页面，但解析方式不同，分别取
        async let listTask = try? await EhAPI.shared.getArchiveList(url: archiveUrl, gid: gid, token: token)
        async let archiverTask = try? await EhAPI.shared.getArchiver(url: archiveUrl, gid: gid, token: token)
        let (list, archiverData) = await (listTask, archiverTask)

        if let list {
            paramOr = list.paramOr
            resolutions = list.archives.map { ArchiveResolution(res: $0.0, name: $0.1) }
        }
        archiver = archiverData

        if list == nil && archiverData == nil {
            loadError = "リクエストに失敗しました。ネットワークを確認するか、しばらくしてから再試行してください。"
        }
        isLoading = false
    }

    private func dispatchToHath(_ item: ArchiveResolution) async {
        dispatchingRes = item.res
        defer { dispatchingRes = nil }
        do {
            try await EhAPI.shared.downloadArchive(gid: gid, token: token, or: paramOr, res: item.res)
            hathMessage = HathMessage(
                title: "送信しました",
                body: "「\(item.name)」を H@H クライアントに送信しました。ダウンロード完了後、クライアントのローカルフォルダーで確認してください。"
            )
        } catch EhError.noHathClient {
            hathMessage = HathMessage(
                title: "H@H クライアントがありません",
                body: "この機能を使うには、先に E-Hentai のサイトでアカウントに H@H クライアントを紐付ける必要があります。"
            )
        } catch {
            hathMessage = HathMessage(title: "送信に失敗しました", body: EhError.localizedMessage(for: error))
        }
    }

    private func prepareArchive(kind: ArchiverKind, formUrl: String) async {
        preparingKind = kind
        defer { preparingKind = nil }
        do {
            let link = try await EhAPI.shared.downloadArchiver(
                url: formUrl,
                referer: archiveUrl,
                dltype: kind.dltype,
                dlcheck: kind.dlcheck
            )
            if let link, !link.isEmpty {
                readyLink = ReadyLink(url: link, title: kind.title)
            } else {
                hathMessage = HathMessage(title: "ダウンロードリンクを取得できませんでした", body: "サーバーから直接リンクが返されませんでした。残高不足の可能性があります。")
            }
        } catch {
            hathMessage = HathMessage(title: "リクエストに失敗しました", body: EhError.localizedMessage(for: error))
        }
    }
}

// MARK: - 附属类型

struct ArchiveResolution: Identifiable, Hashable {
    /// 表单里的 res 值 (如 "780x")
    let res: String
    /// 展示名 (如 "780x · 12 MB")
    let name: String
    var id: String { res }
}

enum ArchiverKind: String, Identifiable {
    case original, resample
    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "オリジナルアーカイブ"
        case .resample: return "リサンプルアーカイブ"
        }
    }

    /// 对齐 Android ArchiverDownloadDialog
    var dltype: String {
        switch self {
        case .original: return "org"
        case .resample: return "res"
        }
    }

    var dlcheck: String {
        switch self {
        case .original: return "Download Original Archive"
        case .resample: return "Download Resample Archive"
        }
    }
}

struct HathMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

struct ReadyLink: Identifiable {
    let id = UUID()
    let url: String
    let title: String
}

/// 拿到直链后的落地方式
///
/// 归档是服务端现打的 zip，App 内下载下来也没有解压和文件管理界面，
/// 所以交给系统：用浏览器下载能直接存进「文件」，或者分享给别的 App。
private struct ArchiveLinkSheet: View {
    let link: ReadyLink

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(link.url)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("ダウンロードリンクの準備ができました")
                } footer: {
                    Text("リンクには有効期限があります。早めにダウンロードしてください。ブラウザで開くと「ファイル」に直接保存できます。")
                }

                Section {
                    if let url = URL(string: link.url) {
                        Button {
                            openURL(url)
                            dismiss()
                        } label: {
                            Label("ブラウザでダウンロード", systemImage: "safari")
                        }

                        ShareLink(item: url) {
                            Label("リンクを共有", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle(link.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
