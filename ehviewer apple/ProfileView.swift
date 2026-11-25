//
//  ProfileView.swift
//  ehviewer apple
//
//  账号资料 + 图片配额 — 对齐 Android GetProfileScene / HomeScene 的配额面板
//
//  `getProfile` 以前只用来在登录后取一次头像和昵称，`getHomeDetail` / `resetLimit`
//  更是写好后从来没有任何界面调用过。图片配额是 E-Hentai 最常被关心的状态之一
//  （超了就 509，看不了图），值得有个能随时查看和重置的地方。
//

import SwiftUI
import EhModels
import EhAPI
import EhCookie
import EhSettings

struct ProfileView: View {
    @State private var profile: ProfileResult?
    @State private var quota: HomeDetail?
    @State private var isLoading = true
    @State private var isResetting = false
    @State private var errorMessage: String?
    @State private var resetResult: String?

    var body: some View {
        Form {
            accountSection
            quotaSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("アカウント情報")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 账号

    /// 账号名。取不到昵称时按真实登录状态给话，不要说成未登录。
    private var displayNameText: String {
        if let name = profile?.displayName ?? AppSettings.shared.displayName, !name.isEmpty {
            return name
        }
        return EhCookieManager.shared.isSignedIn ? "ログイン済み" : "未ログイン"
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    // 拿不到昵称不等于没登录。
                    //
                    // 昵称只能从 forums.e-hentai.org 取，而论坛在 Cloudflare 的
                    // JS 挑战后面，纯 URLSession 过不去（实测 403 "Just a moment..."）。
                    // 这里原本一律回落到「未登录」——用户明明登录着，却被告知
                    // 没登录，然后去反复排查登录问题。
                    Text(displayNameText)
                        .font(.headline)
                    if let uid = AppSettings.shared.userId, !uid.isEmpty {
                        Text("UID \(uid)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let url = profile?.avatar ?? AppSettings.shared.avatar
        CachedAsyncImage(url: URL(string: url ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.tertiary)
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    // MARK: - 图片配额

    @ViewBuilder
    private var quotaSection: some View {
        Section {
            if let quota, quota.totalLimit > 0 {
                let used = Double(quota.currentUsed)
                let total = Double(quota.totalLimit)
                let ratio = min(1, max(0, used / total))

                VStack(alignment: .leading, spacing: 10) {
                    // 大数字给「还剩多少」而不是「已用多少」：
                    // 用户真正要判断的是「今天还能不能接着看」
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(quota.totalLimit - quota.currentUsed)")
                            .font(EhFont.display)
                            .foregroundStyle(ratio > 0.9 ? EhColor.danger : EhColor.label)
                        Text("残り / 全 \(quota.totalLimit)")
                            .font(EhFont.meta)
                            .foregroundStyle(EhColor.tertiaryLabel)
                    }

                    ZStack(alignment: .leading) {
                        Capsule().fill(EhColor.fill)
                        GeometryReader { geo in
                            Capsule()
                                // 快满了变色 —— 超了就是 509，看不了图
                                .fill(ratio > 0.9 ? EhColor.danger
                                      : (ratio > 0.7 ? EhColor.warning : EhColor.accentFill))
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 6)

                    Text("本日の使用量 \(quota.currentUsed)")
                        .font(EhFont.meta)
                        .foregroundStyle(EhColor.secondaryLabel)
                }
                .padding(.vertical, 6)

                if quota.resetCost > 0 {
                    Button {
                        Task { await reset() }
                    } label: {
                        HStack {
                            Text("上限をリセット")
                            Spacer()
                            if isResetting {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("\(quota.resetCost) GP 消費")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isResetting)
                }

                if let resetResult {
                    Text(resetResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("閲覧上限を読み込み中…").foregroundStyle(.secondary)
                }
            } else if quota != nil {
                // 请求成功但没有数字额度：这个账号用的是基于 IP 的限制，
                // E-Hentai 本来就不给「已用 X / 上限 Y」，只有买了 Bronze Star
                // 或 More Pages 的账号才有。
                //
                // 这里原本一律显示「读不到配额信息，可能未登录」——把一个
                // 完全正常的状态说成登录出了问题，白白让人去排查登录。
                VStack(alignment: .leading, spacing: 6) {
                    Label("現在、閲覧上限はありません", systemImage: "checkmark.circle")
                        .foregroundStyle(EhColor.success)
                    Text("このアカウントは IP ベースの制限を使用しており、E-Hentai は具体的な数値を提供していません。"
                         + "Bronze Star または More Pages を購入すると上限がアカウントに紐付けられ、ここに使用量が表示されるようになります。")
                        .font(EhFont.caption)
                        .foregroundStyle(EhColor.secondaryLabel)
                }
            } else {
                Text("閲覧上限の情報を読み込めません。ネットワークを確認してから再試行してください。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("画像の閲覧上限")
        } footer: {
            Text("画像を閲覧すると上限を消費し、使い切ると 509 エラーになります。上限は毎日自動で回復し、GP を使ってすぐにリセットすることもできます。")
        }
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        errorMessage = nil
        resetResult = nil

        async let profileTask = try? await EhAPI.shared.getProfile()
        async let quotaTask = try? await EhAPI.shared.getHomeDetail()
        let (p, q) = await (profileTask, quotaTask)

        profile = p
        quota = q

        // 顺手把最新头像/昵称写回设置，其它界面共用
        if let name = p?.displayName, !name.isEmpty { AppSettings.shared.displayName = name }
        if let avatar = p?.avatar, !avatar.isEmpty { AppSettings.shared.avatar = avatar }

        if p == nil && q == nil {
            errorMessage = "リクエストに失敗しました。ネットワークまたはログイン状態を確認してください。"
        }
        isLoading = false
    }

    private func reset() async {
        isResetting = true
        defer { isResetting = false }
        do {
            let updated = try await EhAPI.shared.resetLimit()
            quota = updated
            resetResult = "リセットしました。現在 \(updated.currentUsed) / \(updated.totalLimit)"
        } catch {
            errorMessage = EhError.localizedMessage(for: error)
        }
    }
}
