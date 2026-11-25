//
//  LogExportView.swift
//  ehviewer apple
//
//  日志导出视图 — 从 SettingsView 连点版本号 5 次触发
//

import SwiftUI
import UniformTypeIdentifiers

struct LogExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = "読み込み中..."
    @State private var logSize: String = ""
    @State private var logFiles: [URL] = []
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 状态栏
                HStack {
                    Label("ログファイル: \(logFiles.count) 個", systemImage: "doc.text")
                    Spacer()
                    Text(logSize)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                // 日志内容预览
                ScrollView {
                    Text(logContent)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("診断ログ")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        exportLog()
                    } label: {
                        Label("エクスポート", systemImage: "square.and.arrow.up")
                    }
                    .disabled(logFiles.isEmpty)

                    Button(role: .destructive) {
                        LogManager.shared.clearLogs()
                        loadLogs()
                    } label: {
                        Label("クリア", systemImage: "trash")
                    }
                }
            }
            .task { loadLogs() }
            #if os(iOS)
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            #endif
        }
    }

    private func loadLogs() {
        logFiles = LogManager.shared.allLogFiles()
        let size = LogManager.shared.totalLogSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        logSize = formatter.string(fromByteCount: size)

        if logFiles.isEmpty {
            logContent = "(ログはまだありません)"
            return
        }

        // 只加载最新的日志文件内容 (最多 200 行)
        if let latest = logFiles.first,
           let content = try? String(contentsOf: latest, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n")
            if lines.count > 200 {
                logContent = "… (全 \(lines.count) 行、最新 200 行を表示)\n\n"
                    + lines.suffix(200).joined(separator: "\n")
            } else {
                logContent = content
            }
        } else {
            logContent = "(ログを読み込めません)"
        }
    }

    private func exportLog() {
        guard let url = LogManager.shared.exportCombinedLog() else { return }

        #if os(iOS)
        exportURL = url
        showShareSheet = true
        #elseif os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.title = "診断ログをエクスポート"
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        #endif
    }
}

// MARK: - iOS ShareSheet wrapper

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
