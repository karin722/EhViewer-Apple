//
//  CredentialStorageTests.swift
//  ehviewer appleTests
//
//  登录凭据从 Cookie 容器搬到钥匙串之后的两条不变量：
//    1. 钥匙串存取要能往返，且 clear 之后读不回来
//    2. 三个认证 Cookie 必须是会话 Cookie（不落盘），其余的仍然持久
//
//  第 2 条尤其要有测试守着：它靠的是 HTTPCookie 的 discard 属性，
//  哪天有人给 setCookie 加回 .expires，pass hash 就会又明文落进容器，
//  而这种回归在界面上完全看不出来。
//

import Testing
import Foundation
import EhCookie
@testable import ehviewer_apple

/// `.serialized`：这几条都在读写钥匙串里同一个 service/account，
/// 默认的并行执行会互相踩——一条刚 clear 完，另一条的 save 就跑了。
@Suite(.serialized)
struct CredentialStorageTests {

    // MARK: - 钥匙串往返

    /// `.enabled(if:)` 而不是在函数体里 return：未签名的本地构建
    /// （CODE_SIGNING_ALLOWED=NO）拿不到 application-identifier，钥匙串会返回
    /// errSecMissingEntitlement。那种环境下这几条测不了，应当显示为「跳过」，
    /// 而不是悄悄通过——悄悄通过就等于这几条断言在 CI 上从来没跑过。
    @Test(.enabled(if: EhCredentialStore.isAvailable))
    func keychainRoundTrip() throws {
        EhCredentialStore.clear()

        let creds = EhCredentials(memberId: "12345", passHash: "deadbeef", igneous: "abc")
        #expect(EhCredentialStore.save(creds))

        let loaded = EhCredentialStore.load()
        #expect(loaded == creds)

        EhCredentialStore.clear()
        #expect(EhCredentialStore.load() == nil)
    }

    /// 第二次登录要覆盖而不是失败。
    /// SecItemAdd 对已存在的项返回 errSecDuplicateItem——直接 add 会静默失败，
    /// 用户换了账号还在用旧凭据。
    @Test(.enabled(if: EhCredentialStore.isAvailable))
    func keychainOverwritesExisting() throws {
        EhCredentialStore.clear()

        #expect(EhCredentialStore.save(EhCredentials(memberId: "1", passHash: "old")))
        #expect(EhCredentialStore.save(EhCredentials(memberId: "2", passHash: "new")))

        let loaded = EhCredentialStore.load()
        #expect(loaded?.memberId == "2")
        #expect(loaded?.passHash == "new")

        EhCredentialStore.clear()
    }

    /// 空凭据等同于清除，不该在钥匙串里留一条空记录
    @Test(.enabled(if: EhCredentialStore.isAvailable))
    func savingEmptyClears() throws {
        #expect(EhCredentialStore.save(EhCredentials(memberId: "1", passHash: "x")))
        #expect(EhCredentialStore.save(EhCredentials()))
        #expect(EhCredentialStore.load() == nil)
    }

    // MARK: - 认证 Cookie 不落盘

    /// 认证 Cookie 必须是会话 Cookie。
    ///
    /// HTTPCookie 的 isSessionOnly 为 true 时不会被写进容器里的
    /// Cookies.binarycookies —— 这正是把 pass hash 从磁盘上拿掉的机制。
    @Test func authCookiesAreSessionOnly() async throws {
        let manager = EhCookieManager.shared
        let domain = EhCookieManager.domainEhentai

        manager.setCookie(name: EhCookieManager.keyIPBPassHash, value: "hash-under-test",
                          domain: domain)
        manager.setCookie(name: EhCookieManager.keyIPBMemberId, value: "42", domain: domain)
        manager.setCookie(name: EhCookieManager.keyNW, value: "1", domain: domain)

        // setCookie 走的是异步写队列，等它排空
        try await confirmCookiePresent(name: EhCookieManager.keyIPBPassHash, domain: domain)

        let url = URL(string: "https://e-hentai.org")!
        let stored = HTTPCookieStorage.shared.cookies(for: url) ?? []

        let passHash = stored.first { $0.name == EhCookieManager.keyIPBPassHash }
        let memberId = stored.first { $0.name == EhCookieManager.keyIPBMemberId }
        let nw = stored.first { $0.name == EhCookieManager.keyNW }

        // 关键不变量：认证 Cookie 的存放方式必须和钥匙串可用性一致。
        //
        // 钥匙串可用 → 会话 Cookie（不落盘），持久副本在钥匙串里；
        // 钥匙串不可用 → 退回持久 Cookie。两者必须匹配，不匹配就意味着
        // 凭据既没进钥匙串、也没落盘，用户每次启动都要重新登录。
        let expectSession = EhCredentialStore.isAvailable
        #expect(passHash?.isSessionOnly == expectSession)
        #expect(memberId?.isSessionOnly == expectSession)

        // 非认证 Cookie 永远持久，否则每次启动都要重新注入
        #expect(nw?.isSessionOnly == false)

        // 无论哪条分支，凭据都必须还能读回来——这是「不会把人登出」的直接断言
        #expect(manager.passHash == "hash-under-test")

        manager.signOut()
    }


    // MARK: - 注销 / 收编

    /// 注销必须连钥匙串一起清 —— 测的是**界面上那个注销按钮实际走的代码**。
    ///
    /// 直接测 EhCookieManager.signOut() 是没用的：它一直都清钥匙串。
    /// 真正的 bug 在 SettingsViewModel.logout()，它自己手写了一遍清 Cookie
    /// 的逻辑、绕开了 signOut，于是凭据留在钥匙串里，重启后
    /// EhCookieManager.init 又把用户恢复成登录状态。所以这里必须调 logout()。
    @Test(.enabled(if: EhCredentialStore.isAvailable))
    @MainActor
    func logoutClearsKeychain() async throws {
        let manager = EhCookieManager.shared
        manager.setCookie(name: EhCookieManager.keyIPBMemberId, value: "42",
                          domain: EhCookieManager.domainEhentai)
        manager.setCookie(name: EhCookieManager.keyIPBPassHash, value: "hash",
                          domain: EhCookieManager.domainEhentai)
        try await settle()
        #expect(manager.persistCredentials())
        #expect(EhCredentialStore.load() != nil)

        SettingsViewModel().logout()
        try await settle()

        #expect(EhCredentialStore.load() == nil,
                "ログアウト後もキーチェーンに認証情報が残っており、次回起動時に黙ってログイン状態に復元されてしまう")
    }

    /// URLSession 自动落盘的持久认证 Cookie 必须被收编成会话 Cookie。
    ///
    /// 账号密码登录走 URLSession，它的 httpCookieStorage 就是 shared，
    /// 服务端的 Set-Cookie 带真实过期时间，在任何 App 代码跑起来之前就
    /// 已经以持久 Cookie 落盘了。secureAuthCookies 负责把它收回来。
    @Test(.enabled(if: EhCredentialStore.isAvailable))
    func secureAuthCookiesConvertsPersistedCookies() async throws {
        let manager = EhCookieManager.shared
        manager.signOut()
        try await settle()

        // 模拟 URLSession 的行为：直接塞一条带过期时间的持久 Cookie
        let persistent = HTTPCookie(properties: [
            .name: EhCookieManager.keyIPBPassHash,
            .value: "persisted-hash",
            .domain: EhCookieManager.domainEhentai,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(86_400),
        ])!
        HTTPCookieStorage.shared.setCookie(persistent)
        let memberId = HTTPCookie(properties: [
            .name: EhCookieManager.keyIPBMemberId,
            .value: "42",
            .domain: EhCookieManager.domainEhentai,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(86_400),
        ])!
        HTTPCookieStorage.shared.setCookie(memberId)

        let url = URL(string: "https://e-hentai.org")!
        #expect(HTTPCookieStorage.shared.cookies(for: url)?
            .first { $0.name == EhCookieManager.keyIPBPassHash }?.isSessionOnly == false,
            "前提条件：これはまず永続 Cookie であるはず")

        #expect(manager.secureAuthCookies())
        try await settle()

        let after = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let hash = after.first { $0.name == EhCookieManager.keyIPBPassHash }
        #expect(hash?.isSessionOnly == true, "pass hash がまだ永続 Cookie としてコンテナに残っている")
        #expect(hash?.value == "persisted-hash", "取り込みの過程で値を失ってはいけない")
        #expect(EhCredentialStore.load()?.passHash == "persisted-hash")

        manager.signOut()
    }


    /// 「重启之后还得是登录状态」—— 这条是这次改动的命门。
    ///
    /// 认证 Cookie 改成会话 Cookie 之后，进程重启时罐子里是空的，全靠
    /// EhCookieManager.init 从钥匙串同步补回来。补回来这件事有两个前提，
    /// 缺一个用户就会看到「明明登录着却显示未登录、配额也读不到」：
    ///   1. 写入必须是同步的（setCookie 走异步写队列，排在队列里不算数）
    ///   2. 必须有人在读 Cookie 之前碰过 EhCookieManager（否则单例都没建）
    /// 这里模拟第 2 步之后立刻同步读，等价于 App 启动时那条路径。
    @Test(.enabled(if: EhCredentialStore.isAvailable))
    func credentialsAreReadableSynchronouslyAfterRestore() async throws {
        let manager = EhCookieManager.shared
        manager.signOut()
        try await settle()

        // 先造出「上次运行留下的钥匙串凭据」
        #expect(EhCredentialStore.save(EhCredentials(
            memberId: "42", passHash: "restored-hash", igneous: nil)))

        // 清掉罐子里的会话副本，模拟进程重启
        let url = URL(string: "https://e-hentai.org")!
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        #expect(manager.passHash == nil, "前提条件：Cookie ストアは空のはず")

        // 先把异步写队列灌满：如果恢复走的是那条队列，它就得排在这些后面，
        // 下面的同步读必然读不到。同步写则直接落罐，不受影响。
        // 不这样做的话，异步写往往在断言之前就跑完了，测试挡不住回归
        // （试过：把同步写改回异步，测试照样通过）。
        for i in 0..<200 {
            manager.setCookie(name: "queue_filler_\(i)", value: "1", domain: "e-hentai.org")
        }

        // 启动路径做的事：碰一下单例，然后**立刻同步**读
        manager.ensureCredentialsRestored()
        manager.restoreCredentialsFromKeychainForTesting()

        #expect(manager.passHash == "restored-hash",
                "復元が同期的でない —— 起動時にログイン状態を読むと空のストアが見える")
        #expect(manager.isSignedIn, "再起動後もログイン状態のままであるべき")

        manager.signOut()
    }

    /// 等异步写队列落地
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    /// 等 setCookie 的异步写队列落地
    private func confirmCookiePresent(name: String, domain: String) async throws {
        let url = URL(string: "https://\(domain.trimmingCharacters(in: .init(charactersIn: ".")))")!
        for _ in 0..<50 {
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            if cookies.contains(where: { $0.name == name }) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Cookie \(name) が想定時間内に書き込まれなかった")
    }
}
