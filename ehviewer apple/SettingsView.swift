//
//  SettingsView.swift
//  ehviewer apple
//
//  设置视图
//

import SwiftUI
import EhSettings
import EhDownload
import EhDatabase
import EhSpider
import EhAPI
import EhCookie
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SettingsView: View {
    @State private var vm = SettingsViewModel()
    @State private var showSettingsBackupImportPicker = false
    @State private var settingsBackupImportMessage: String?
    @Environment(\.openURL) private var openURL

    /// 被推入父导航栈时，不创建自己的 NavigationStack，避免嵌套
    private var isPushed: Bool = false

    /// 只渲染某一组设置。设置项本身有近百个，全部铺在一页里要滚很久才能找到；
    /// 「我的」页按主题分成了七个入口，每个入口进来只看自己那一组。
    ///
    /// 用 scope 过滤而不是把 SettingsView 拆成七个文件：这些分区共用同一份
    /// @State 与 ViewModel，拆开就得把状态复制七份或提升到外部，两者都更糟。
    enum Scope {
        case all
        case appearance      // 外观
        case listThumbnail   // 列表与缩略图
        case downloads       // 下载与存储
        case reading         // 阅读
        case favorites       // 收藏
        case privacy         // 隐私与锁定
        case network         // 网络与容灾
        case tagDatabase     // 标签翻译数据库

        var title: String {
            switch self {
            case .all:           return "設定"
            case .appearance:    return "外観"
            case .listThumbnail: return "リストとサムネイル"
            case .downloads:     return "ダウンロードとストレージ"
            case .reading:       return "読む"
            case .favorites:     return "お気に入り"
            case .privacy:       return "プライバシーとロック"
            case .network:       return "ネットワークと障害対策"
            case .tagDatabase:   return "タグ翻訳データベース"
            }
        }
    }

    private var scope: Scope = .all

    init(scope: Scope) {
        self.scope = scope
        self.isPushed = true
    }

    init(isPushed: Bool = false) {
        self.isPushed = isPushed
    }

    var body: some View {
        if isPushed {
            settingsInnerContent
        } else {
            NavigationStack {
                settingsInnerContent
            }
        }
    }

    private var settingsInnerContent: some View {
        #if os(macOS)
        macSettingsContent
            .navigationTitle("設定")
            .onAppear { vm.checkLoginState() }
        #else
        Form {
            switch scope {
            case .all:
                accountSection
                siteSection
                filterSection
                displaySection
                listThumbnailSection
                favoritesSection
                networkSection
                readingSection
                downloadSection
                cacheSection
                securitySection
                advancedSection
                aboutSection
            case .appearance:
                displaySection
            case .listThumbnail:
                listThumbnailSection
            case .downloads:
                downloadSection
                cacheSection
            case .reading:
                readingSection
            case .favorites:
                favoritesSection
            case .privacy:
                securitySection
            case .network:
                networkSection
                filterSection
            case .tagDatabase:
                advancedSection
            }
        }
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.checkLoginState() }
        #endif
    }

    // MARK: - macOS 分栏设置布局
    #if os(macOS)
    @State private var selectedSettingsTab: SettingsTab = .account

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case account = "アカウント"
        case site = "サイト"
        case display = "外観"
        case favorites = "お気に入り"
        case network = "ネットワーク"
        case reading = "読む"
        case download = "ダウンロード"
        case cache = "キャッシュ"
        case security = "プライバシーとセキュリティ"
        case advanced = "詳細"
        case about = "このアプリについて"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .account: return "person.circle"
            case .site: return "globe"
            case .display: return "paintbrush"
            case .favorites: return "heart"
            case .network: return "network"
            case .reading: return "book"
            case .download: return "arrow.down.circle"
            case .cache: return "internaldrive"
            case .security: return "lock.shield"
            case .advanced: return "gearshape.2"
            case .about: return "info.circle"
            }
        }
    }

    private var macSettingsContent: some View {
        HStack(spacing: 0) {
            // 左侧侧边栏
            List(SettingsTab.allCases, selection: $selectedSettingsTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            // 右侧内容区
            ScrollView {
                Form {
                    macSettingsTabContent
                }
                .formStyle(.grouped)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    @ViewBuilder
    private var macSettingsTabContent: some View {
        switch selectedSettingsTab {
        case .account:
            accountSection
        case .site:
            siteSection
        case .display:
            displaySection
        case .favorites:
            favoritesSection
        case .network:
            networkSection
        case .reading:
            readingSection
        case .download:
            downloadSection
        case .cache:
            cacheSection
        case .security:
            securitySection
        case .advanced:
            advancedSection
        case .about:
            aboutSection
        }
    }
    #endif

    // MARK: - Account

    private var accountSection: some View {
        Section("アカウント") {
            if vm.isLoggedIn {
                HStack(spacing: 12) {
                    // 用户头像 (对齐 Android: 从论坛资料页获取)
                    if let avatarURL = vm.avatarURL {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            case .failure:
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.accentColor)
                            default:
                                ProgressView()
                                    .frame(width: 40, height: 40)
                            }
                        }
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = vm.displayName, !name.isEmpty {
                            Text(name)
                                .font(.subheadline.bold())
                        } else {
                            Text("ログイン済み")
                                .font(.subheadline.bold())
                        }
                        HStack(spacing: 8) {
                            if let uid = vm.userId, !uid.isEmpty {
                                Text("UID: \(uid)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(vm.hasExAccess ? "ExHentai が利用可能です" : "E-Hentai のみ (未ログイン)")
                                .font(.caption)
                                .foregroundStyle(vm.hasExAccess ? Color.green : .secondary)
                        }
                    }
                }

                // 身份 Cookies (对齐 Android: identity_cookie)
                NavigationLink("認証 Cookie") {
                    identityCookiesView
                }

                Button("ログアウト", role: .destructive) {
                    vm.showLogoutConfirm = true
                }
            } else {
                Button("ログイン") {
                    vm.showLogin = true
                }
            }
        }
        .confirmationDialog("ログアウトしますか？", isPresented: $vm.showLogoutConfirm, titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) {
                vm.logout()
            }
        }
        .sheet(isPresented: $vm.showLogin) {
            LoginView()
        }
    }

    // MARK: - Site

    private var siteSection: some View {
        Section("サイト") {
            Picker("デフォルトのサイト", selection: $vm.gallerySite) {
                Text("E-Hentai").tag(0)
                Text("ExHentai").tag(1)
            }

            // EH 站点设置 (对齐 Android: u_config)
            Button {
                let site = AppSettings.shared.gallerySite
                let url = site == .exHentai
                    ? "https://exhentai.org/uconfig.php"
                    : "https://e-hentai.org/uconfig.php"
                openURL(URL(string: url)!)
            } label: {
                HStack {
                    Text("EH サイト設定")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 账号资料 + 图片配额 (对齐 Android GetProfileScene)
            NavigationLink("アカウント情報と閲覧上限") {
                ProfileView()
            }

            // 我的标签 (对齐 Android MyTagsActivity) —— 原生页面，不再跳浏览器
            NavigationLink("マイタグ") {
                MyTagsView()
            }

            // 站内公告 (对齐 Android NewsScene)
            NavigationLink("サイトのお知らせ") {
                EhNewsView()
            }

            Picker("リスト表示モード", selection: $vm.listMode) {
                Text("リスト").tag(0)
                Text("コンパクト").tag(1)
                Text("グリッド").tag(2)
            }

            // 详情页封面大小 (对齐 Android Settings.KEY_DETAIL_SIZE)
            Picker("詳細画面のカバー", selection: Binding(
                get: { AppSettings.shared.detailSize },
                set: { AppSettings.shared.detailSize = $0 }
            )) {
                Text("標準").tag(0)
                Text("大きめ").tag(1)
            }

            Toggle("日本語タイトルを表示", isOn: $vm.showJpnTitle)

            // 标签翻译设置
            Toggle("タグの翻訳を表示", isOn: $vm.showTagTranslations)
            
            if vm.showTagTranslations {
                HStack {
                    Text("タグデータベース")
                    Spacer()
                    if vm.isUpdatingTagDb {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(vm.tagDbStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button {
                    Task { await vm.updateTagDatabase() }
                } label: {
                    HStack {
                        Text("タグ翻訳データベースを更新")
                        Spacer()
                        if vm.tagDbUpdateSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .disabled(vm.isUpdatingTagDb)

                // 标签翻译来源标注 (对齐 Android: tag_translations_source)
                Button {
                    openURL(URL(string: "https://github.com/EhTagTranslation")!)
                } label: {
                    HStack {
                        Text("追加翻訳（EhTagTranslator 提供）")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink("タグフィルター") {
                FilterView()
            }

            // 屏蔽列表 (对齐 Android: BlackListActivity)
            NavigationLink("ブロックリスト") {
                FilterView()
            }

            // 移动网络提醒 (对齐 Android Settings.KEY_CELLULAR_NETWORK_WARNING)
            Toggle("モバイル通信でのダウンロード前に確認", isOn: Binding(
                get: { AppSettings.shared.cellularNetworkWarning },
                set: { AppSettings.shared.cellularNetworkWarning = $0 }
            ))
        }
    }

    // MARK: - Filter / Search (对齐 Android: 默认分类/排除标签命名空间/排除语言)
    // 这三项是服务端配置，通过 uconfig Cookie 下发 —— 改完立即重新同步
    private var filterSection: some View {
        Section {
            NavigationLink("デフォルトの検索カテゴリ") {
                defaultCategoriesView
                    .onDisappear { EhConfigSync.apply() }
            }

            NavigationLink("除外するタグの名前空間") {
                excludedNamespacesView
                    .onDisappear { EhConfigSync.apply() }
            }

            NavigationLink("除外する言語") {
                excludedLanguagesView
                    .onDisappear { EhConfigSync.apply() }
            }
        } header: {
            Text("検索フィルター")
        } footer: {
            Text("E-Hentai アカウントのサーバー側設定に保存され、Web 版にも反映されます。")
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        Section("ネットワーク") {
            // App 内代理 (对齐 Android advanced_settings.xml 的 ProxyPreference)。
            // 此前只能被动显示系统代理，没法给 App 单独指一个。
            Picker("プロキシ", selection: $vm.proxyMode) {
                Text("システムに合わせる").tag(0)
                Text("手動 HTTP").tag(1)
            }
            .pickerStyle(.segmented)

            if vm.proxyMode == 1 {
                HStack {
                    Text("アドレス")
                    TextField("127.0.0.1", text: $vm.proxyHost)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                HStack {
                    Text("ポート")
                    TextField("7890", value: $vm.proxyPort, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Button("プロキシ設定を適用") {
                    Task { await EhAPI.shared.applyProxySettings() }
                    EhToast.success(AppSettings.shared.manualProxyIsUsable
                                    ? "\(AppSettings.shared.proxyHost):\(AppSettings.shared.proxyPort) に切り替えました"
                                    : "アドレスまたはポートが不完全なため、引き続きシステム設定に従います")
                }
                Text("HTTP/HTTPS プロキシのみ対応しています。URLSession は SOCKS に対応していないため、"
                     + "ここには SOCKS の選択肢はありません。押しても効かないスイッチを置くよりはましです。"
                     + "アドレスまたはポートが未入力の場合は「システムに合わせる」として扱われ、ネットワークが使えなくなることはありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("ドメインフロンティング", isOn: $vm.domainFronting)

            Toggle("DNS over HTTPS", isOn: $vm.dnsOverHttps)

            Toggle("内蔵 Hosts", isOn: $vm.builtInHosts)

            Toggle("内蔵 ExH Hosts", isOn: Binding(
                get: { AppSettings.shared.builtExHosts },
                set: { AppSettings.shared.builtExHosts = $0 }
            ))

            // 自定义 Hosts (对齐 Android HostsActivity)
            NavigationLink("カスタム Hosts") {
                HostsView()
            }
            
            // 网络诊断按钮
            Button {
                vm.runNetworkDiagnostics()
            } label: {
                HStack {
                    Text("ネットワーク診断")
                    Spacer()
                    if vm.isDiagnosing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !vm.diagnosisResult.isEmpty {
                        Image(systemName: vm.diagnosisSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(vm.diagnosisSuccess ? .green : .orange)
                    }
                }
            }
            .disabled(vm.isDiagnosing)
            
            if !vm.diagnosisResult.isEmpty {
                Text(vm.diagnosisResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Display (对齐 Android Settings: 外观)

    private var displaySection: some View {
        Section("外観") {
            // 深色模式 (对齐 Android Settings.KEY_THEME)
            Picker("テーマ", selection: Binding(
                get: { AppSettings.shared.theme },
                set: { AppSettings.shared.theme = $0 }
            )) {
                Text("システムに合わせる").tag(0)
                Text("ライト").tag(1)
                Text("ダーク").tag(2)
            }

            // 启动页面 (对齐 Android Settings.KEY_LAUNCH_PAGE)
            Picker("起動時の画面", selection: Binding(
                get: { AppSettings.shared.launchPage },
                set: { AppSettings.shared.launchPage = $0 }
            )) {
                Text("ホーム").tag(0)
                Text("人気").tag(1)
                Text("ランキング").tag(2)
                Text("お気に入り").tag(3)
                Text("ダウンロード").tag(4)
                Text("履歴").tag(5)
            }

            Toggle("ギャラリーのページ数を表示", isOn: Binding(
                get: { AppSettings.shared.showGalleryPages },
                set: { AppSettings.shared.showGalleryPages = $0 }
            ))

            Toggle("コメント欄を表示", isOn: Binding(
                get: { AppSettings.shared.showGalleryComment },
                set: { AppSettings.shared.showGalleryComment = $0 }
            ))

            Toggle("評価を表示", isOn: Binding(
                get: { AppSettings.shared.showGalleryRating },
                set: { AppSettings.shared.showGalleryRating = $0 }
            ))

            // 这两项对齐 Android show_eh_limits / show_eh_events。
            // 此前只在 AppSettings 里声明过，没有任何界面读它们，
            // 也没有开关——「我的」页的配额卡片和站内公告入口一直是写死显示的。
            Toggle("画像の閲覧上限を表示", isOn: Binding(
                get: { AppSettings.shared.showEhLimits },
                set: { AppSettings.shared.showEhLimits = $0 }
            ))

            Toggle("サイトのお知らせへの入口を表示", isOn: Binding(
                get: { AppSettings.shared.showEhEvents },
                set: { AppSettings.shared.showEhEvents = $0 }
            ))

            Toggle("閲覧の進捗を表示", isOn: Binding(
                get: { AppSettings.shared.showReadProgress },
                set: { AppSettings.shared.showReadProgress = $0 }
            ))
        }
    }

    /// 列表与缩略图。
    ///
    /// 设计稿把它与「外观」分成两个二级页。此前我让两个入口落到同一组，
    /// 理由是缩略图大小同时影响列表与详情；但那条理由对用户不成立——
    /// 他点「列表与缩略图」就是想调列表，不该先滚过一堆主题与显示开关。
    private var listThumbnailSection: some View {
        Section("リストとサムネイル") {
            Picker("サムネイルのサイズ", selection: Binding(
                get: { AppSettings.shared.thumbSize },
                set: { AppSettings.shared.thumbSize = $0 }
            )) {
                Text("小").tag(0)
                Text("中").tag(1)
                Text("大").tag(2)
            }

            // 缩略图分辨率 —— 走 uconfig Cookie (tp)
            Picker("サムネイルの解像度", selection: Binding(
                get: { AppSettings.shared.thumbResolution },
                set: {
                    AppSettings.shared.thumbResolution = $0
                    EhConfigSync.apply()
                }
            )) {
                Text("標準").tag(0)
                Text("高画質").tag(1)
            }

            // 已接入: GalleryListView 读取并传给 GalleryRow
            Toggle("サムネイルのリンクを修正", isOn: Binding(
                get: { AppSettings.shared.fixThumbUrl },
                set: { AppSettings.shared.fixThumbUrl = $0 }
            ))

            // 大屏幕列表布局 (对齐 Android: 全宽单列表布局选项)
            Picker("ワイド画面レイアウト", selection: Binding(
                get: { AppSettings.shared.wideScreenListMode },
                set: { AppSettings.shared.wideScreenListMode = $0 }
            )) {
                Text("2 カラム (リスト+詳細)").tag(0)
                Text("全幅のシングルリスト").tag(1)
            }
        }
    }

    // MARK: - Favorites (对齐 Android Settings: 收藏)

    private var favoritesSection: some View {
        Section("お気に入り") {
            // 默认收藏夹 (对齐 Android Settings.KEY_DEFAULT_FAV_SLOT)
            Picker("デフォルトのお気に入りフォルダー", selection: Binding(
                get: { AppSettings.shared.defaultFavSlot },
                set: { AppSettings.shared.defaultFavSlot = $0 }
            )) {
                Text("毎回確認").tag(-2)
                // 本地收藏 (slot -1)。收藏对话框一直支持它，
                // 这个 Picker 却漏了，导致「默认放本地收藏」设不出来。
                Text("ローカルお気に入り").tag(-1)
                ForEach(0..<10) { slot in
                    Text(AppSettings.shared.favCatName(slot)).tag(slot)
                }
            }

            NavigationLink("お気に入りフォルダー名") {
                favCatNamesView
            }

            AndroidLibraryImportControl()
        }
    }

    private var favCatNamesView: some View {
        List {
            ForEach(0..<10, id: \.self) { slot in
                HStack {
                    Text("お気に入りフォルダー \(slot)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("名前", text: Binding(
                        get: { AppSettings.shared.favCatName(slot) },
                        set: { AppSettings.shared.setFavCatName(slot, $0) }
                    ))
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .navigationTitle("お気に入りフォルダー名")
    }

    // MARK: - Reading

    private var readingSection: some View {
        Section("読む") {
            Picker("閲覧方向", selection: Binding(
                get: { ReadingDirection(persistedRawValue: AppSettings.shared.readingDirection) },
                set: { direction in
                    guard let value = direction.persistedUpdate(from: AppSettings.shared.readingDirection) else { return }
                    AppSettings.shared.readingDirection = value
                }
            )) {
                ForEach(ReadingDirection.allCases, id: \.rawValue) { direction in
                    Text(ReaderGestureGuidance(direction: direction).directionTitle).tag(direction)
                }
            }

            // 页面缩放 (对齐 Android Settings.KEY_PAGE_SCALING)
            Picker("ページの拡大縮小", selection: Binding(
                get: { AppSettings.shared.pageScaling },
                set: { AppSettings.shared.pageScaling = $0 }
            )) {
                Text("画面に合わせる").tag(0)
                Text("幅に合わせる").tag(1)
                Text("高さに合わせる").tag(2)
                Text("元のサイズ").tag(3)
                Text("縦横比を維持").tag(4)
            }

            // 起始位置 (对齐 Android Settings.KEY_START_POSITION)
            Picker("開始位置", selection: Binding(
                get: { AppSettings.shared.startPosition },
                set: { AppSettings.shared.startPosition = $0 }
            )) {
                Text("デフォルト").tag(0)
                Text("上").tag(1)
                Text("右上").tag(2)
                Text("下").tag(3)
                Text("右下").tag(4)
                Text("中央").tag(5)
            }

            // 屏幕旋转 (对齐 Android Settings.KEY_SCREEN_ROTATION)
            Picker("画面の回転", selection: Binding(
                get: { AppSettings.shared.screenRotation },
                set: { newValue in
                    AppSettings.shared.screenRotation = newValue
                    // 立即应用旋转设置
                    #if os(iOS)
                    applyScreenRotation(newValue)
                    #endif
                }
            )) {
                Text("システムに合わせる").tag(0)
                Text("縦向きに固定").tag(1)
                Text("横向きに固定").tag(2)
            }

            Stepper("先読みページ数: \(vm.preloadImage)", value: $vm.preloadImage, in: 1...10)

            Toggle("画面を常にオンにする", isOn: $vm.keepScreenOn)

            Toggle("フルスクリーンで読む", isOn: Binding(
                get: { AppSettings.shared.readingFullscreen },
                set: { AppSettings.shared.readingFullscreen = $0 }
            ))

            Toggle("時計を表示", isOn: Binding(
                get: { AppSettings.shared.showClock },
                set: { AppSettings.shared.showClock = $0 }
            ))

            Toggle("進捗を表示", isOn: Binding(
                get: { AppSettings.shared.showProgress },
                set: { AppSettings.shared.showProgress = $0 }
            ))

            Toggle("バッテリー残量を表示", isOn: Binding(
                get: { AppSettings.shared.showBattery },
                set: { AppSettings.shared.showBattery = $0 }
            ))

            Toggle("ページ間隔を表示", isOn: Binding(
                get: { AppSettings.shared.showPageInterval },
                set: { AppSettings.shared.showPageInterval = $0 }
            ))

            #if DEBUG && os(iOS)
            Toggle("音量ボタンでページ送り", isOn: Binding(
                get: { AppSettings.shared.volumePage },
                set: { AppSettings.shared.volumePage = $0 }
            ))

            if AppSettings.shared.volumePage {
                Toggle("音量ボタンの方向を反転", isOn: Binding(
                    get: { AppSettings.shared.reverseVolumePage },
                    set: { AppSettings.shared.reverseVolumePage = $0 }
                ))
            }
            #endif

            // 自定义亮度 (对齐 Android Settings.KEY_CUSTOM_SCREEN_LIGHTNESS)
            Toggle("カスタム明るさ", isOn: Binding(
                get: { AppSettings.shared.customScreenLightness },
                set: { AppSettings.shared.customScreenLightness = $0 }
            ))

            if AppSettings.shared.customScreenLightness {
                Slider(value: Binding(
                    get: { Double(AppSettings.shared.screenLightness) },
                    set: { AppSettings.shared.screenLightness = Int($0) }
                ), in: 0...100, step: 1) {
                    Text("明るさ: \(AppSettings.shared.screenLightness)%")
                }
            }

            // 自动翻页间隔 (对齐 Android Settings.KEY_AUTO_PAGE_INTERVAL)
            Stepper("自動ページ送りの間隔: \(vm.autoPageInterval)s", value: $vm.autoPageInterval, in: AppSettings.autoPageIntervalRange)

            // 色彩滤镜 (对齐 Android Settings.KEY_COLOR_FILTER)
            Toggle("カラーフィルター (目の保護)", isOn: Binding(
                get: { AppSettings.shared.colorFilter },
                set: { AppSettings.shared.colorFilter = $0 }
            ))

            if AppSettings.shared.colorFilter {
                Picker("フィルターの強度", selection: Binding(
                    get: { AppSettings.shared.colorFilterColor },
                    set: { AppSettings.shared.colorFilterColor = $0 }
                )) {
                    Text("弱").tag(0x14000000)
                    Text("中").tag(0x20000000)
                    Text("強").tag(0x40000000)
                }
            }
        }
    }

    // MARK: - Download

    private var downloadSection: some View {
        Section("ダウンロード") {
            #if os(macOS)
            // macOS: 自定义下载路径
            HStack {
                Text("ダウンロード先")
                Spacer()
                Text(vm.downloadPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("変更...") {
                    vm.chooseDownloadPath()
                }
                .buttonStyle(.link)
            }
            #endif

            Stepper("同時接続数: \(vm.multiThread)", value: $vm.multiThread, in: 1...5)

            Stepper("タイムアウト (秒): \(vm.downloadTimeout)", value: $vm.downloadTimeout, in: 10...120, step: 10)

            // 下载延迟 (对齐 Android Settings.KEY_DOWNLOAD_DELAY)
            Stepper("ダウンロード間隔: \(vm.downloadDelay) ms", value: $vm.downloadDelay, in: 0...2000, step: 100)

            // 图片分辨率 —— 走 uconfig Cookie (xr)，改完立即同步
            Picker("画像の解像度", selection: Binding(
                get: { AppSettings.shared.imageResolution },
                set: {
                    AppSettings.shared.imageResolution = $0
                    EhConfigSync.apply()
                }
            )) {
                ForEach(ImageResolution.allCases) { resolution in
                    Text(resolution.displayName).tag(resolution)
                }
            }

            // 下载原图 (对齐 Android Settings.KEY_DOWNLOAD_ORIGIN_IMAGE)
            Toggle("オリジナル画像をダウンロード", isOn: Binding(
                get: { AppSettings.shared.downloadOriginImage },
                set: { AppSettings.shared.downloadOriginImage = $0 }
            ))

            // 阅读时同步下载 (对齐 Android 上游 2026-06-16 sync_download_while_reading)
            Toggle("閲覧時に自動ダウンロード", isOn: Binding(
                get: { AppSettings.shared.syncDownloadWhileReading },
                set: { AppSettings.shared.syncDownloadWhileReading = $0 }
            ))
            // 这行字此前写的是「顺手存进下载目录」，读起来像一种缓存优化，
            // 但它的实际后果是每翻一本都进下载列表、占用永久空间、不受缓存
            // 上限约束。开关的名字和说明都要把这件事讲清楚。
            Text("閲覧したページをダウンロードフォルダーに保存し、ギャラリーがダウンロードリストに表示されます。"
                 + "永続的な容量を使用し、下の閲覧キャッシュの上限は適用されません。"
                 + "通信量を節約したいだけならオンにする必要はありません。閲覧キャッシュが閲覧済みの画像を自動的に再利用します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            #if os(iOS)
            // 灵动岛 (Live Activity) 下载进度显示
            Toggle("Dynamic Island にダウンロード進捗を表示", isOn: Binding(
                get: { AppSettings.shared.showLiveActivity },
                set: { AppSettings.shared.showLiveActivity = $0 }
            ))
            #endif


            // 恢复下载项目 (对齐 Android: restore_download_items)
            Button {
                vm.restoreDownloadItems()
            } label: {
                HStack {
                    Text("ダウンロード項目を復元")
                    Spacer()
                    if vm.isRestoring {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(vm.isRestoring)

            if let msg = vm.restoreResultMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 清除冗余数据 (对齐 Android: clean_redundancy)
            Button {
                vm.cleanRedundancy()
            } label: {
                HStack {
                    Text("ダウンロードの不要なデータを消去")
                    Spacer()
                    if vm.isCleaning {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(vm.isCleaning)
            .confirmationDialog(
                "\(vm.cleanOrphanCount) 個の不要なフォルダー (\(vm.cleanOrphanSize)) が見つかりました。削除しますか？",
                isPresented: $vm.showCleanConfirm,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    vm.confirmCleanRedundancy()
                }
                Button("キャンセル", role: .cancel) {
                    vm.cancelClean()
                }
            }

            if let msg = vm.cleanResultMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Cache

    private var cacheSection: some View {
        Section("キャッシュ") {
            // 阅读缓存大小 (对齐 Android Settings.KEY_READ_CACHE_SIZE)
            Picker("閲覧キャッシュのサイズ", selection: Binding(
                get: { AppSettings.shared.readCacheSize },
                set: { AppSettings.shared.readCacheSize = $0 }
            )) {
                Text("40 MB").tag(40)
                Text("80 MB").tag(80)
                Text("120 MB").tag(120)
                Text("160 MB").tag(160)
                Text("240 MB").tag(240)
                Text("320 MB").tag(320)
                Text("480 MB").tag(480)
                Text("640 MB").tag(640)
            }

            Text("閲覧した画像は閲覧キャッシュに保存され、同じギャラリーを再度読むときに再ダウンロードは不要です。"
                 + "上限を超えると古いものから自動的に削除され、システムの空き容量が少ないときはまとめて回収されます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("閲覧キャッシュの使用量")
                Spacer()
                Text(vm.readCacheUsage)
                    .foregroundStyle(.secondary)
            }

            Button("閲覧キャッシュを消去") {
                SpiderDen.clearReadCache()
                vm.refreshCacheSizes()
                EhToast.success("閲覧キャッシュを消去しました")
            }

            HStack {
                Text("ディスクキャッシュ")
                Spacer()
                Text(vm.diskCacheSize)
                    .foregroundStyle(.secondary)
            }

            // 清除内存缓存 (对齐 Android: clear_memory_cache)
            Button("メモリキャッシュを消去") {
                vm.clearMemoryCache()
            }

            Button("ディスクキャッシュを消去") {
                vm.clearCache()
            }
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section("プライバシーとセキュリティ") {
            // 隐私遮罩（对齐 Android enable_secure）
            Toggle("バックグラウンド時に内容を隠す", isOn: Binding(
                get: { AppSettings.shared.enableSecureScreen },
                set: { AppSettings.shared.enableSecureScreen = $0 }
            ))
            Text("アプリを離れるとすぐに画面を覆い、App スイッチャーのプレビューに閲覧中の内容が表示されないようにします。"
                 + "iOS ではアプリがスクリーンショットを禁止できないため、この設定では意図的なスクリーンショットは防げません。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("アプリロックを有効にする", isOn: Binding(
                get: { AppSettings.shared.enableSecurity },
                set: { AppSettings.shared.enableSecurity = $0 }
            ))

            if AppSettings.shared.enableSecurity {
                Picker("ロックまでの時間", selection: Binding(
                    get: { AppSettings.shared.securityDelay },
                    set: { AppSettings.shared.securityDelay = $0 }
                )) {
                    Text("すぐに").tag(0)
                    Text("30 秒").tag(30)
                    Text("1 分").tag(60)
                    Text("5 分").tag(300)
                    Text("15 分").tag(900)
                }
            }
        }
    }

    // MARK: - Advanced (对齐 Android Settings: 高级)

    private var advancedSection: some View {
        Section("詳細") {
            // 历史记录容量 (对齐 Android Settings.KEY_HISTORY_INFO_SIZE)
            Stepper("履歴の上限: \(vm.historyInfoSize)", value: $vm.historyInfoSize, in: 100...2000, step: 100)

            // 解析失败时把原始 HTML 存进日志目录，方便反馈问题
            Toggle("解析エラーの状況を保存", isOn: Binding(
                get: { AppSettings.shared.saveParseErrorBody },
                set: { AppSettings.shared.saveParseErrorBody = $0 }
            ))

            // 导出数据 (对齐 Android: export_data)
            Button("Apple 版の設定をエクスポート（JSON）") {
                exportSettingsBackup()
            }

            // 导入数据 (对齐 Android: import_data)
            Button("Apple 版の設定をインポート（JSON）") {
                settingsBackupImportMessage = nil
                showSettingsBackupImportPicker = true
            }
            .fileImporter(
                isPresented: $showSettingsBackupImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleSettingsBackupImport(result)
            }
            if let settingsBackupImportMessage {
                Text(settingsBackupImportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportSettingsBackup() {
        guard let jsonData = try? SettingsBackup.exportJSON(from: .standard) else { return }

        #if os(iOS)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer_settings.json")
        try? jsonData.write(to: tempURL)

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #else
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ehviewer_settings.json"
        panel.title = "設定をエクスポート"
        if panel.runModal() == .OK, let url = panel.url {
            try? jsonData.write(to: url)
        }
        #endif
    }

    private func handleSettingsBackupImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        guard url.startAccessingSecurityScopedResource() else {
            settingsBackupImportMessage = "選択したバックアップファイルにアクセスできないため、設定は変更されていません。"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let report = try SettingsBackup.restoreJSON(data, into: .standard)
            var message: String
            if report.appliedCount > 0 {
                vm.reloadSettingsAfterBackupImport()
                message = "\(report.appliedCount) 項目の設定をインポートしました。"
            } else {
                message = "復元できる設定がないため、既存の設定は変更されていません。"
            }
            if report.skippedObsoleteMediaScan {
                message += "\n旧バージョンのメディアスキャン設定はスキップしました。Apple 版には対応する機能がありません。"
            }
            if report.skippedUnknownCount > 0 {
                message += "\n認識できない \(report.skippedUnknownCount) 個のフィールドをスキップしました。"
            }
            settingsBackupImportMessage = message
        } catch SettingsBackup.RestoreError.invalidValue(_) {
            settingsBackupImportMessage = "バックアップに不正な形式の設定値があるため、設定は変更されていません。"
        } catch {
            settingsBackupImportMessage = "有効な Apple 版設定のバックアップを読み込めないため、設定は変更されていません。"
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("このアプリについて") {
            // 免责声明（对齐 Android about_settings.xml 的 declaration）。
            // 这条是法律意义上的声明，不是装饰：这个 App 不是 E-Hentai 官方的，
            // 用户该知道自己在用谁做的东西。
            Text("本アプリは E-Hentai.org とは一切の提携・協力関係がなく、"
                 + "公開 Web インターフェースに基づくサードパーティ製クライアントです。コンテンツはすべて E-Hentai によるもので、"
                 + "本アプリはいかなるコンテンツもホスト・制作していません。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("バージョン")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                vm.versionTapCount += 1
                if vm.versionTapCount >= 5 {
                    vm.versionTapCount = 0
                    vm.showLogExport = true
                }
            }

            // 检查更新 (对齐 Android Settings -> 检查更新)
            Button {
                AppUpdateChecker.shared.checkManually()
            } label: {
                HStack {
                    Text("アップデートを確認")
                    Spacer()
                    if AppUpdateChecker.shared.isChecking {
                        ProgressView()
                    }
                }
            }
            .disabled(AppUpdateChecker.shared.isChecking)

            Button("ソースコード") {
                openURL(URL(string: "https://github.com/felixchaos/EhViewer-Apple")!)
            }

            NavigationLink("オープンソースライセンス") {
                licensesView
            }
        }
        .sheet(isPresented: $vm.showLogExport) {
            LogExportView()
        }
        .onChange(of: vm.gallerySite) { _, _ in
            // 站点切换通知: 放在 View 层而非 ViewModel.didSet 中
            // 因为 @Observable 宏使 didSet 在 init() 中也会触发，导致 GalleryListView 误刷新
            NotificationCenter.default.post(name: GalleryActionService.siteChangedNotification, object: nil)
        }
        .alert("新しいバージョンがあります", isPresented: Bindable(AppUpdateChecker.shared).showUpdateAlert) {
            if let info = AppUpdateChecker.shared.updateAvailable {
                Button("ダウンロードへ") {
                    openURL(info.downloadURL)
                }
                Button("キャンセル", role: .cancel) {}
            }
        } message: {
            if let info = AppUpdateChecker.shared.updateAvailable {
                Text("v\(info.version)\n\n\(AppUpdatePlatform.current.installationHint)\n\n\(info.releaseNotes)")
            }
        }
        .alert("アップデートを確認", isPresented: .init(
            get: {
                if let err = AppUpdateChecker.shared.checkError {
                    return err != ""
                }
                return false
            },
            set: { newValue in
                if !newValue { AppUpdateChecker.shared.checkError = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if AppUpdateChecker.shared.checkError == "already_latest" {
                Text("現在、利用可能な新しいバージョンはありません（v\(AppUpdateChecker.shared.currentVersion)）")
            } else {
                Text(AppUpdateChecker.shared.checkError ?? "")
            }
        }
    }

    private var licensesView: some View {
        List {
            // 本项目
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("EhViewer-Apple")
                            .font(.headline)
                        Spacer()
                        Text("Apache-2.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Copyright © 2024 felixchaos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("""
Licensed under the Apache License, Version 2.0 (the "License"); \
you may not use this file except in compliance with the License. \
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software \
distributed under the License is distributed on an "AS IS" BASIS, \
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. \
See the License for the specific language governing permissions and \
limitations under the License.
""")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("本プロジェクト")
            }

            // 致谢
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EhViewer")
                        .font(.subheadline.bold())
                    Text("オリジナルの Android 版 EhViewer プロジェクト")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("EhViewer_CN_SXJ")
                        .font(.subheadline.bold())
                    Text("EhViewer 中国語フォーク。本プロジェクトはその UI デザインと機能ロジックを参考にしています")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("謝辞")
            }

            // 第三方库
            Section {
                ForEach(licensedLibraries, id: \.name) { lib in
                    DisclosureGroup {
                        Text(lib.licenseText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } label: {
                        HStack {
                            Text(lib.name)
                                .font(.subheadline)
                            Spacer()
                            Text(lib.license)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("サードパーティのオープンソースライブラリ")
            }
        }
        .navigationTitle("オープンソースライセンス")
    }

    private struct LicensedLibrary {
        let name: String
        let license: String
        let licenseText: String
    }

    private var licensedLibraries: [LicensedLibrary] {
        [
            LicensedLibrary(
                name: "GRDB.swift",
                license: "MIT",
                licenseText: """
Copyright (C) 2015-2024 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy \
of this software and associated documentation files (the "Software"), to deal \
in the Software without restriction, including without limitation the rights \
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
copies of the Software, and to permit persons to whom the Software is \
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all \
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
SOFTWARE.
"""
            ),
            LicensedLibrary(
                name: "SwiftSoup",
                license: "MIT",
                licenseText: """
Copyright (c) 2016 Nabil Chatbi

Permission is hereby granted, free of charge, to any person obtaining a copy \
of this software and associated documentation files (the "Software"), to deal \
in the Software without restriction, including without limitation the rights \
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
copies of the Software, and to permit persons to whom the Software is \
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all \
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
SOFTWARE.
"""
            ),
            LicensedLibrary(
                name: "SDWebImageSwiftUI",
                license: "MIT",
                licenseText: """
Copyright (c) 2019 lizhuoli1126@126.com

Permission is hereby granted, free of charge, to any person obtaining a copy \
of this software and associated documentation files (the "Software"), to deal \
in the Software without restriction, including without limitation the rights \
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
copies of the Software, and to permit persons to whom the Software is \
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all \
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
SOFTWARE.
"""
            ),
        ]
    }

    // MARK: - Screen Rotation Helper

    #if os(iOS)
    /// 立即应用屏幕旋转设置 (对齐 Android setRequestedOrientation)
    private func applyScreenRotation(_ mode: Int) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }

        let orientations: UIInterfaceOrientationMask
        switch mode {
        case 1:
            orientations = .portrait
        case 2:
            orientations = .landscape
        default:
            orientations = .allButUpsideDown
        }

        let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        windowScene.requestGeometryUpdate(geometryPreferences) { error in
            debugLog("[SettingsView] 回転更新エラー: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Identity Cookies View (对齐 Android: IdentityCookiePreference)

    private var identityCookiesView: some View {
        List {
            let ehCookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://e-hentai.org")!) ?? []
            let exCookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://exhentai.org")!) ?? []

            Section("E-Hentai Cookies") {
                ForEach(ehCookies, id: \.name) { cookie in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cookie.name)
                            .font(.subheadline.bold())
                        Text(cookie.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contextMenu {
                        Button("コピー") {
                            #if os(iOS)
                            UIPasteboard.general.string = "\(cookie.name)=\(cookie.value)"
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("\(cookie.name)=\(cookie.value)", forType: .string)
                            #endif
                        }
                    }
                }
                if ehCookies.isEmpty {
                    Text("Cookie なし")
                        .foregroundStyle(.secondary)
                }
            }

            Section("ExHentai Cookies") {
                ForEach(exCookies, id: \.name) { cookie in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cookie.name)
                            .font(.subheadline.bold())
                        Text(cookie.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contextMenu {
                        Button("コピー") {
                            #if os(iOS)
                            UIPasteboard.general.string = "\(cookie.name)=\(cookie.value)"
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("\(cookie.name)=\(cookie.value)", forType: .string)
                            #endif
                        }
                    }
                }
                if exCookies.isEmpty {
                    Text("Cookie なし")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("認証 Cookie")
    }

    // MARK: - Default Categories View (对齐 Android: DefaultCategoryActivity)

    private var defaultCategoriesView: some View {
        let allCategories: [(String, Int)] = [
            ("同人誌 (Doujinshi)", 1),
            ("漫画 (Manga)", 2),
            ("イラスト CG (Artist CG)", 4),
            ("ゲーム CG (Game CG)", 8),
            ("洋物 (Western)", 512),
            ("非エロ (Non-H)", 256),
            ("画像セット (Image Set)", 16),
            ("Cosplay", 32),
            ("アジア (Asian Porn)", 64),
            ("その他 (Misc)", 128),
        ]

        return List {
            ForEach(allCategories, id: \.1) { name, bit in
                let isEnabled = (AppSettings.shared.defaultCategories & bit) != 0
                Toggle(name, isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue {
                            AppSettings.shared.defaultCategories |= bit
                        } else {
                            AppSettings.shared.defaultCategories &= ~bit
                        }
                    }
                ))
            }
        }
        .navigationTitle("デフォルトの検索カテゴリ")
    }

    // MARK: - Excluded Tag Namespaces View (对齐 Android: ExcludedTagNamespacesActivity)

    private var excludedNamespacesView: some View {
        let namespaces: [(String, Int)] = [
            ("Reclass", 1),
            ("Language", 2),
            ("Parody", 4),
            ("Character", 8),
            ("Group", 16),
            ("Artist", 32),
            ("Male", 64),
            ("Female", 128),
            ("Mixed", 256),
            ("Cosplayer", 512),
            ("Other", 1024),
            ("Temp", 2048),
        ]

        return List {
            Section {
                Text("選択した名前空間は検索結果のタグ一覧から除外されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(namespaces, id: \.1) { name, bit in
                let isExcluded = (AppSettings.shared.excludedTagNamespaces & bit) != 0
                Toggle(name, isOn: Binding(
                    get: { isExcluded },
                    set: { newValue in
                        if newValue {
                            AppSettings.shared.excludedTagNamespaces |= bit
                        } else {
                            AppSettings.shared.excludedTagNamespaces &= ~bit
                        }
                    }
                ))
            }
        }
        .navigationTitle("除外するタグの名前空間")
    }

    // MARK: - Excluded Languages View (对齐 Android: ExcludedLanguagesActivity)

    private var excludedLanguagesView: some View {
        let languages = [
            "Japanese", "English", "Chinese", "Dutch", "French",
            "German", "Hungarian", "Italian", "Korean", "Polish",
            "Portuguese", "Russian", "Spanish", "Thai", "Vietnamese",
            "N/A", "Other",
        ]

        return List {
            Section {
                Text("選択した言語は検索結果から除外されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(languages.enumerated()), id: \.offset) { index, lang in
                let bit = 1 << index
                let currentExcluded = Int(AppSettings.shared.excludedLanguages ?? "0") ?? 0
                let isExcluded = (currentExcluded & bit) != 0
                Toggle(lang, isOn: Binding(
                    get: { isExcluded },
                    set: { newValue in
                        var current = Int(AppSettings.shared.excludedLanguages ?? "0") ?? 0
                        if newValue {
                            current |= bit
                        } else {
                            current &= ~bit
                        }
                        AppSettings.shared.excludedLanguages = String(current)
                    }
                ))
            }
        }
        .navigationTitle("除外する言語")
    }
}

// MARK: - ViewModel

@MainActor
@Observable
class SettingsViewModel {
    var isLoggedIn = false
    var hasExAccess = false
    var displayName: String?
    var userId: String?
    var avatarURL: URL?
    var isFetchingProfile = false
    var showLogoutConfirm = false
    var showLogin = false

    var gallerySite: Int = 0 {
        didSet {
            let newSite = EhSite(rawValue: gallerySite) ?? .eHentai
            AppSettings.shared.gallerySite = newSite
            // ⚠️ 不在 didSet 中发送通知 — @Observable 宏使 didSet 在 init() 中也会触发
            // 通知改由 SettingsView.body 的 .onChange(of: vm.gallerySite) 发送
        }
    }
    var listMode: Int = 0 {
        didSet { AppSettings.shared.listMode = ListMode(rawValue: listMode) ?? .list }
    }
    var showJpnTitle: Bool = false {
        didSet { AppSettings.shared.showJpnTitle = showJpnTitle }
    }
    var showTagTranslations: Bool = true {
        didSet { AppSettings.shared.showTagTranslations = showTagTranslations }
    }
    
    // 标签数据库状态
    var isUpdatingTagDb = false
    var tagDbUpdateSuccess = false
    var tagDbStatus: String {
        let db = EhTagDatabase.shared
        if db.isLoaded {
            if let version = db.version {
                return "読み込み済み (\(version.prefix(10)))"
            }
            return "読み込み済み"
        }
        return "未読み込み"
    }
    
    func updateTagDatabase() async {
        isUpdatingTagDb = true
        tagDbUpdateSuccess = false
        
        do {
            try await EhTagDatabase.shared.updateDatabase(forceUpdate: true)
            await MainActor.run {
                self.tagDbUpdateSuccess = true
                self.isUpdatingTagDb = false
            }
        } catch {
            debugLog("[SettingsVM] Failed to update tag database: \(error)")
            await MainActor.run {
                self.isUpdatingTagDb = false
            }
        }
    }
    
    /// 代理三项走 ViewModel 而不是直接读 AppSettings：
    /// AppSettings 的这些属性是 @ObservationIgnored 的，直接在 body 里读，
    /// 改了不会触发重绘——切到「手动 HTTP」之后地址/端口输入框不会出现。
    var proxyMode: Int = 0 {
        didSet {
            AppSettings.shared.proxyMode = proxyMode
            Task { await EhAPI.shared.applyProxySettings() }
        }
    }
    var proxyHost: String = "" {
        didSet { AppSettings.shared.proxyHost = proxyHost }
    }
    var proxyPort: Int = 0 {
        didSet { AppSettings.shared.proxyPort = proxyPort }
    }

    var domainFronting: Bool = false {
        didSet { AppSettings.shared.domainFronting = domainFronting }
    }
    var dnsOverHttps: Bool = false {
        didSet { AppSettings.shared.dnsOverHttps = dnsOverHttps }
    }
    var builtInHosts: Bool = false {
        didSet { AppSettings.shared.builtInHosts = builtInHosts }
    }
    var preloadImage: Int = 5 {
        didSet { AppSettings.shared.preloadImage = preloadImage }
    }
    var keepScreenOn: Bool = false {
        didSet { AppSettings.shared.keepScreenOn = keepScreenOn }
    }
    var multiThread: Int = 3 {
        didSet { AppSettings.shared.multiThreadDownload = multiThread }
    }
    var downloadTimeout: Int = 60 {
        didSet { AppSettings.shared.downloadTimeout = downloadTimeout }
    }
    var downloadDelay: Int = 0 {
        didSet { AppSettings.shared.downloadDelay = downloadDelay }
    }
    var autoPageInterval: Int = 5 {
        didSet { AppSettings.shared.autoPageInterval = autoPageInterval }
    }
    var historyInfoSize: Int = 100 {
        didSet { AppSettings.shared.historyInfoSize = historyInfoSize }
    }

    // 日志导出 (连点 5 次版本号触发)
    var versionTapCount = 0
    var showLogExport = false

    // 网络诊断状态
    var isDiagnosing = false
    var diagnosisResult = ""
    var diagnosisSuccess = false

    var diskCacheSize: String = "計算中..."
    /// 阅读缓存（Caches/spider_image）已用空间。
    /// 此前设置里只显示 URLCache 的占用，而阅读器的图根本不在那儿，
    /// 所以「缓存大小」这一项和用户实际感受到的占用对不上。
    var readCacheUsage: String = "計算中..."

    func calculateCacheSize() {
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useMB, .useGB]
        byteFormatter.countStyle = .file
        diskCacheSize = byteFormatter.string(fromByteCount: Int64(URLCache.shared.currentDiskUsage))
        readCacheUsage = byteFormatter.string(fromByteCount: SpiderDen.readCacheUsage())
    }

    func refreshCacheSizes() { calculateCacheSize() }

    func clearCache() {
        // 清除内存缓存
        GalleryCache.shared.clearAll()
        // 清除 URL 磁盘缓存
        URLCache.shared.removeAllCachedResponses()
        calculateCacheSize()
    }

    #if os(macOS)
    var downloadPath: String {
        if let path = UserDefaults.standard.string(forKey: "downloadPath"), !path.isEmpty {
            return path
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("download").path
    }

    func chooseDownloadPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "ダウンロード先フォルダーを選択"
        panel.prompt = "選択"

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "downloadPath")
        }
    }
    #endif

    init() {
        // 从 AppSettings 加载初始值
        // ⚠️ @Observable 宏会使 didSet 在 init 中也被触发 (属性变为计算属性)
        // 因此 didSet 中不应有副作用操作 (如发通知)，仅写回 AppSettings 是安全的 (幂等)
        gallerySite = AppSettings.shared.gallerySite.rawValue
        listMode = AppSettings.shared.listMode.rawValue
        showJpnTitle = AppSettings.shared.showJpnTitle
        showTagTranslations = AppSettings.shared.showTagTranslations
        proxyMode = AppSettings.shared.proxyMode
        proxyHost = AppSettings.shared.proxyHost
        proxyPort = AppSettings.shared.proxyPort
        domainFronting = AppSettings.shared.domainFronting
        dnsOverHttps = AppSettings.shared.dnsOverHttps
        builtInHosts = AppSettings.shared.builtInHosts
        preloadImage = AppSettings.shared.preloadImage
        keepScreenOn = AppSettings.shared.keepScreenOn
        multiThread = AppSettings.shared.multiThreadDownload
        downloadTimeout = AppSettings.shared.downloadTimeout
        downloadDelay = AppSettings.shared.downloadDelay
        autoPageInterval = AppSettings.shared.autoPageInterval
        historyInfoSize = AppSettings.shared.historyInfoSize
        
        checkLoginState()
        calculateCacheSize()
    }

    func checkLoginState() {
        let ehCookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://e-hentai.org")!) ?? []
        isLoggedIn = ehCookies.contains { $0.name == "ipb_member_id" }

        // ExH 访问权限: 只要已登录(有 memberId + passHash)就允许切换到 ExHentai
        // igneous Cookie 只有首次访问 exhentai.org 后才会被种下
        // Android 端同样允许已登录用户自由切换站点
        let exCookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://exhentai.org")!) ?? []
        let hasIgneous = exCookies.contains { $0.name == "igneous" && !$0.value.isEmpty && $0.value != "mystery" }
        hasExAccess = isLoggedIn || hasIgneous

        // 加载保存的用户信息
        displayName = AppSettings.shared.displayName
        userId = AppSettings.shared.userId
        if let avatarStr = AppSettings.shared.avatar, let url = URL(string: avatarStr) {
            avatarURL = url
        }

        // 如果没有保存 UID，尝试从 Cookie 读取
        if userId == nil || userId?.isEmpty == true {
            if let memberId = ehCookies.first(where: { $0.name == "ipb_member_id" })?.value {
                userId = memberId
                AppSettings.shared.userId = memberId
            }
        }

        // 如果已登录但没有头像/用户名，异步获取
        if isLoggedIn && (avatarURL == nil || displayName == nil || displayName?.isEmpty == true) {
            fetchProfileIfNeeded()
        }
    }

    /// 异步获取用户资料 (displayName + avatar)
    func fetchProfileIfNeeded() {
        guard !isFetchingProfile else { return }
        isFetchingProfile = true
        Task {
            do {
                let profile = try await EhAPI.shared.getProfile()
                await MainActor.run {
                    if let name = profile.displayName, !name.isEmpty {
                        self.displayName = name
                        AppSettings.shared.displayName = name
                    }
                    if let avatar = profile.avatar, let url = URL(string: avatar) {
                        self.avatarURL = url
                        AppSettings.shared.avatar = avatar
                    }
                    self.isFetchingProfile = false
                }
            } catch {
                debugLog("[SettingsVM] ユーザー情報の取得に失敗: \(error)")
                await MainActor.run {
                    self.isFetchingProfile = false
                }
            }
        }
    }

    func logout() {
        // 走 EhCookieManager.signOut，而不是自己再抄一遍清 Cookie 的逻辑。
        //
        // 这里原来是手写的：只删 HTTPCookieStorage 里的 Cookie，不碰钥匙串。
        // 认证凭据改存钥匙串之后，这等于「注销只在本次运行有效」——
        // 重启 App，EhCookieManager.init 从钥匙串把凭据恢复回来，用户又登录了。
        // 借出去的设备上这是实打实的隐私泄漏。
        // This settings flow clears credentials without changing RootView's AppState.
        // Invalidate in-flight cloud favorite effects before ending the account session.
        GalleryStatusCache.shared.resetCloudState()
        GalleryCache.shared.clearAccountSnapshots()
        EhCookieManager.shared.signOut()
        isLoggedIn = false
        hasExAccess = false
        displayName = nil
        userId = nil
        avatarURL = nil
        AppSettings.shared.isLogin = false
        AppSettings.shared.displayName = nil
        AppSettings.shared.userId = nil
        AppSettings.shared.avatar = nil
    }
    
    /// 网络诊断
    func runNetworkDiagnostics() {
        guard !isDiagnosing else { return }
        isDiagnosing = true
        diagnosisResult = ""
        diagnosisSuccess = false
        
        Task {
            var results: [String] = []
            var allSuccess = true
            
            // 1. DNS 解析测试
            let hosts = ["e-hentai.org", "exhentai.org"]
            for host in hosts {
                let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
                var resolved = DarwinBoolean(false)
                CFHostStartInfoResolution(hostRef, .addresses, nil)
                if let addresses = CFHostGetAddressing(hostRef, &resolved)?.takeUnretainedValue() as? [Data], !addresses.isEmpty {
                    // 提取 IP 地址
                    if let addr = addresses.first {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        addr.withUnsafeBytes { ptr in
                            let sockaddr = ptr.bindMemory(to: sockaddr.self).baseAddress!
                            getnameinfo(sockaddr, socklen_t(addr.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                        }
                        let ip = String(cString: hostname)
                        results.append("✓ \(host) → \(ip)")
                    }
                } else {
                    results.append("✗ \(host) DNS の解決に失敗")
                    allSuccess = false
                }
            }
            
            // 2. HTTPS 连接测试
            for host in hosts {
                let url = URL(string: "https://\(host)/")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.httpMethod = "HEAD"
                
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 || httpResponse.statusCode == 302 {
                            results.append("✓ \(host) HTTPS 接続は正常")
                        } else {
                            results.append("⚠ \(host) HTTP \(httpResponse.statusCode)")
                        }
                    }
                } catch let error as NSError {
                    if error.domain == NSURLErrorDomain {
                        switch error.code {
                        case NSURLErrorTimedOut:
                            results.append("✗ \(host) 接続タイムアウト")
                        case NSURLErrorCannotConnectToHost:
                            results.append("✗ \(host) 接続できません")
                        case NSURLErrorSecureConnectionFailed:
                            results.append("✗ \(host) TLS エラー (ブロックされている可能性)")
                        case NSURLErrorServerCertificateUntrusted:
                            results.append("✗ \(host) 証明書が信頼されていません")
                        default:
                            results.append("✗ \(host) エラー: \(error.localizedDescription)")
                        }
                    } else {
                        results.append("✗ \(host) エラー: \(error.localizedDescription)")
                    }
                    allSuccess = false
                }
            }
            
            // 3. 代理检测
            #if os(iOS)
            let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
            if let httpProxy = proxySettings?["HTTPProxy"] as? String, !httpProxy.isEmpty {
                results.append("ℹ HTTP プロキシを検出: \(httpProxy)")
            }
            #endif
            
            await MainActor.run {
                self.diagnosisResult = results.joined(separator: "\n")
                self.diagnosisSuccess = allSuccess
                self.isDiagnosing = false
            }
        }
    }

    // MARK: - 下载管理 (对齐 Android)

    // MARK: - 恢复/清理 状态
    var isRestoring = false
    var restoreResultMessage: String?
    var isCleaning = false
    var cleanResultMessage: String?
    var showCleanConfirm = false
    var cleanOrphanCount = 0
    var cleanOrphanSize: String = ""

    /// 恢复下载项目 (对齐 Android: RestoreDownloadPreference)
    /// 扫描下载目录中的 .ehviewer 文件，将不在数据库中的画廊重新加入下载记录
    func restoreDownloadItems() {
        guard !isRestoring else { return }
        isRestoring = true
        restoreResultMessage = nil

        Task {
            let downloadDir = DownloadManager.shared.downloadDirectory
            var restoredCount = 0
            var errorCount = 0

            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: downloadDir, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run {
                    self.restoreResultMessage = "ダウンロードフォルダーを読み込めません"
                    self.isRestoring = false
                }
                return
            }

            // 获取数据库中已有的 gid 集合
            let existingGids: Set<Int64>
            do {
                let records = try EhDatabase.shared.getAllDownloads()
                existingGids = Set(records.map { $0.gid })
            } catch {
                await MainActor.run {
                    self.restoreResultMessage = "データベースの読み込みに失敗: \(error.localizedDescription)"
                    self.isRestoring = false
                }
                return
            }

            for dir in contents where dir.hasDirectoryPath {
                let ehviewerFile = dir.appendingPathComponent(".ehviewer")
                guard fm.fileExists(atPath: ehviewerFile.path) else { continue }

                // 读取 SpiderInfo 以获取 gid/token/pages
                // 只要头部字段 —— 这里会遍历整个下载目录，逐本解析上万条 pToken 纯属浪费
                // (对齐上游 2026-08-21「添加读取画廊信息头的功能」)
                guard let spiderInfo = SpiderInfoFile.readHeader(from: dir) else { continue }
                // 跳过已在数据库中的
                if existingGids.contains(spiderInfo.gid) { continue }
                if OfflineGallery.isImported(gid: spiderInfo.gid, token: spiderInfo.token) {
                    do {
                        if try await DownloadManager.shared.restoreOfflineGallery(spiderInfo, from: dir) {
                            restoredCount += 1
                        }
                    } catch {
                        errorCount += 1
                    }
                    continue
                }
                guard spiderInfo.gid > 0, !spiderInfo.token.isEmpty else { continue }

                // 从目录名提取标题: 格式为 "gid-title"
                let dirName = dir.lastPathComponent
                let prefix = "\(spiderInfo.gid)-"
                let title = dirName.hasPrefix(prefix) ? String(dirName.dropFirst(prefix.count)) : dirName

                // 统计已下载页数
                let imageFiles = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
                    .map { $0.filter { url in
                        let ext = url.pathExtension.lowercased()
                        return ["jpg", "jpeg", "png", "gif", "webp"].contains(ext)
                    }.count } ?? 0

                let record = DownloadRecord(
                    gid: spiderInfo.gid,
                    token: spiderInfo.token,
                    title: title,
                    pages: spiderInfo.pages,
                    state: imageFiles >= spiderInfo.pages ? DownloadManager.stateFinish : DownloadManager.stateNone,
                    date: Date()
                )

                do {
                    try EhDatabase.shared.insertDownload(record)
                    restoredCount += 1
                } catch {
                    errorCount += 1
                }
            }

            await MainActor.run {
                if restoredCount > 0 {
                    self.restoreResultMessage = "\(restoredCount) 件のダウンロード項目を復元しました" + (errorCount > 0 ? " (\(errorCount) 件失敗)" : "")
                } else {
                    self.restoreResultMessage = "復元が必要なダウンロード項目はありません"
                }
                self.isRestoring = false
            }
        }
    }

    /// 清除冗余数据 (对齐 Android: CleanRedundancyPreference)
    /// 扫描下载目录，找出不在数据库记录中的孤立文件夹，提示用户确认删除
    func cleanRedundancy() {
        guard !isCleaning else { return }
        isCleaning = true
        cleanResultMessage = nil

        Task {
            let downloadDir = DownloadManager.shared.downloadDirectory
            let fm = FileManager.default

            guard let contents = try? fm.contentsOfDirectory(
                at: downloadDir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run {
                    self.cleanResultMessage = "ダウンロードフォルダーを読み込めません"
                    self.isCleaning = false
                }
                return
            }

            // 获取数据库中所有 gid
            let dbGids: Set<Int64>
            do {
                let records = try EhDatabase.shared.getAllDownloads()
                dbGids = Set(records.map { $0.gid })
            } catch {
                await MainActor.run {
                    self.cleanResultMessage = "データベースの読み込みに失敗しました"
                    self.isCleaning = false
                }
                return
            }

            // 找出孤立目录 (目录名以 gid- 开头，但 gid 不在数据库中)
            var orphanDirs: [URL] = []
            var totalSize: Int64 = 0
            for dir in contents where dir.hasDirectoryPath {
                let dirName = dir.lastPathComponent
                // 尝试提取 gid (格式: "gid-title")
                if let dashRange = dirName.firstIndex(of: "-"),
                   let gid = Int64(dirName[dirName.startIndex..<dashRange]) {
                    if !dbGids.contains(gid) {
                        orphanDirs.append(dir)
                        // 计算目录大小
                        if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
                            let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }
                            for fileURL in fileURLs {
                                let size = (try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
                                totalSize += Int64(size)
                            }
                        }
                    }
                }
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            let sizeStr = formatter.string(fromByteCount: totalSize)

            await MainActor.run {
                if orphanDirs.isEmpty {
                    self.cleanResultMessage = "不要なデータはありません"
                    self.isCleaning = false
                } else {
                    self.cleanOrphanCount = orphanDirs.count
                    self.cleanOrphanSize = sizeStr
                    self.showCleanConfirm = true
                    // isCleaning 保持 true 直到用户确认或取消
                }
            }
        }
    }

    /// 确认清除冗余数据 — 实际删除孤立目录
    func confirmCleanRedundancy() {
        Task {
            let downloadDir = DownloadManager.shared.downloadDirectory
            let fm = FileManager.default

            guard let contents = try? fm.contentsOfDirectory(
                at: downloadDir, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run {
                    self.cleanResultMessage = "消去に失敗しました"
                    self.isCleaning = false
                }
                return
            }

            let dbGids: Set<Int64>
            do {
                let records = try EhDatabase.shared.getAllDownloads()
                dbGids = Set(records.map { $0.gid })
            } catch {
                await MainActor.run {
                    self.cleanResultMessage = "消去に失敗しました"
                    self.isCleaning = false
                }
                return
            }

            var deletedCount = 0
            for dir in contents where dir.hasDirectoryPath {
                let dirName = dir.lastPathComponent
                if let dashRange = dirName.firstIndex(of: "-"),
                   let gid = Int64(dirName[dirName.startIndex..<dashRange]),
                   !dbGids.contains(gid) {
                    try? fm.removeItem(at: dir)
                    deletedCount += 1
                }
            }

            await MainActor.run {
                self.cleanResultMessage = "\(deletedCount) 個の不要なフォルダーを消去しました"
                self.isCleaning = false
            }
        }
    }

    func cancelClean() {
        isCleaning = false
        cleanResultMessage = nil
    }

    /// 清除内存缓存
    func clearMemoryCache() {
        GalleryCache.shared.clearAll()
    }

    func reloadSettingsAfterBackupImport() {
        // 重新加载 ViewModel 的存储属性
        gallerySite = AppSettings.shared.gallerySite.rawValue
        listMode = AppSettings.shared.listMode.rawValue
        showJpnTitle = AppSettings.shared.showJpnTitle
        showTagTranslations = AppSettings.shared.showTagTranslations
        proxyMode = AppSettings.shared.proxyMode
        proxyHost = AppSettings.shared.proxyHost
        proxyPort = AppSettings.shared.proxyPort
        domainFronting = AppSettings.shared.domainFronting
        dnsOverHttps = AppSettings.shared.dnsOverHttps
        builtInHosts = AppSettings.shared.builtInHosts
        preloadImage = AppSettings.shared.preloadImage
        keepScreenOn = AppSettings.shared.keepScreenOn
        multiThread = AppSettings.shared.multiThreadDownload
        downloadTimeout = AppSettings.shared.downloadTimeout
        downloadDelay = AppSettings.shared.downloadDelay
        autoPageInterval = AppSettings.shared.autoPageInterval
        historyInfoSize = AppSettings.shared.historyInfoSize
    }
}

#Preview {
    SettingsView()
}
