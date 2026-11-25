//
//  TorrentListView.swift
//  ehviewer apple
//
//  种子列表 — 对齐 Android GalleryDetailScene 的 torrent 对话框
//  上传时间字段来自上游 2026-04-30「种子下载列表添加上传时间」
//

import SwiftUI
import EhModels
import EhAPI

struct TorrentListView: View {
    let gid: Int64
    let token: String
    let torrentUrl: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var torrents: [TorrentInfo] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("トレント一覧を読み込み中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("トレント一覧を読み込めません", systemImage: "arrow.down.doc")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("再試行") { Task { await load() } }
                    }
                } else if torrents.isEmpty {
                    ContentUnavailableView(
                        "トレントはありません",
                        systemImage: "arrow.down.doc",
                        description: Text("このギャラリーにはまだ誰もトレントをアップロードしていません。")
                    )
                } else {
                    List(torrents) { torrent in
                        row(torrent)
                    }
                }
            }
            .navigationTitle("トレント")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await load() }
            .overlay(alignment: .bottom) {
                if copied {
                    Text("リンクをコピーしました")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
    }

    private func row(_ torrent: TorrentInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(torrent.name)
                .font(.callout)
                .lineLimit(3)

            if !torrent.posted.isEmpty {
                Label(torrent.posted, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if let url = URL(string: torrent.url) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("ダウンロード", systemImage: "arrow.down.circle")
                    }
                    ShareLink(item: url) {
                        Label("共有", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    copy(torrent.url)
                } label: {
                    Label("リンクをコピー", systemImage: "doc.on.doc")
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            torrents = try await EhAPI.shared.getTorrentList(url: torrentUrl, gid: gid, token: token)
        } catch {
            loadError = EhError.localizedMessage(for: error)
        }
        isLoading = false
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { copied = false }
        }
    }
}
