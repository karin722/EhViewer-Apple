//
//  SecurityView.swift
//  ehviewer apple
//
//  安全锁屏视图 (对应 Android SecurityScene)
//  支持 Face ID / Touch ID / 设备密码解锁
//  Fix F1-1: 无生物识别时自动降级到设备密码; 设备无密码时自动跳过
//  Fix F1-2: 生物识别锁定后显示"使用密码"按钮; 重试锁定 60 秒后自动恢复
//

import SwiftUI
import LocalAuthentication
import EhSettings

/// 安全锁屏视图
/// 应用启动时如果启用了安全功能，需要先通过认证
struct SecurityView: View {
    let onAuthenticated: () -> Void
    
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var retryCount = 0
    /// 是否已被锁定 (生物识别 lockout 或重试次数过多)
    @State private var isLockedOut = false
    /// 锁定倒计时秒数
    @State private var lockoutRemaining = 0
    @State private var lockoutTimer: Timer?
    /// 设备是否完全不支持任何认证 (无生物识别+无密码)
    @State private var deviceHasNoAuth = false
    
    private let maxRetries = 5
    private let lockoutDuration = 60 // 锁定 60 秒后自动恢复
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 锁图标
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
            
            Text("EhViewer")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("続行するには本人確認を行ってください")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            // 生物识别图标
            if !deviceHasNoAuth {
                biometricIcon
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .padding(.top, 24)
            }
            
            if let error = authError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            if deviceHasNoAuth {
                // Fix F1-1: 设备完全不支持任何认证 → 自动禁用安全功能并放行
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("このデバイスには画面ロックのパスコードまたは生体認証が設定されていません")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("セキュリティロックは自動的にオフになりました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("アプリに入る") {
                        // 自动禁用安全功能，防止下次再卡死
                        AppSettings.shared.enableSecurity = false
                        onAuthenticated()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)
            } else {
                // 主解锁按钮: 优先使用生物识别
                if hasBiometrics {
                    Button(action: authenticateWithBiometrics) {
                        HStack {
                            Image(systemName: biometricSystemImage)
                            Text("\(biometricName) でロック解除")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAuthenticating || isLockedOut)
                    .padding(.horizontal, 32)
                }
                
                // Fix F1-2: 始终显示"使用密码解锁"按钮 — 生物识别锁定/失败时的保底路径
                Button(action: authenticateWithPasscode) {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("デバイスのパスコードでロック解除")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(isAuthenticating)
                .padding(.horizontal, 32)
                
                // 锁定倒计时
                if isLockedOut && lockoutRemaining > 0 {
                    Text("生体認証は一時的にロックされています。\(lockoutRemaining) 秒後に再試行できます")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
                
                // 重试计数 (仅生物识别, 密码不限)
                if retryCount > 0 && retryCount < maxRetries && !isLockedOut {
                    Text("生体認証の残り試行回数: \(maxRetries - retryCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkDeviceCapabilities()
            // 自动触发认证
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !deviceHasNoAuth {
                    if hasBiometrics {
                        authenticateWithBiometrics()
                    } else {
                        authenticateWithPasscode()
                    }
                }
            }
        }
        .onDisappear {
            lockoutTimer?.invalidate()
            lockoutTimer = nil
        }
    }
    
    // MARK: - 设备能力检测
    
    /// 检测设备是否支持任何认证方式
    private func checkDeviceCapabilities() {
        let context = LAContext()
        var error: NSError?
        let hasBio = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let hasPasscode = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        
        if !hasBio && !hasPasscode {
            // Fix F1-1: 设备完全无认证能力 → 标记后自动放行
            deviceHasNoAuth = true
        }
    }
    
    // MARK: - 生物识别类型
    
    private var hasBiometrics: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
    
    private var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    
    private var biometricName: String {
        switch biometricType {
        case .none:
            return "パスワード"
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "生体認証"
        }
    }
    
    private var biometricSystemImage: String {
        switch biometricType {
        case .none:
            return "lock.shield"
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        @unknown default:
            return "lock.shield"
        }
    }
    
    @ViewBuilder
    private var biometricIcon: some View {
        switch biometricType {
        case .none:
            Image(systemName: "lock.shield")
        case .faceID:
            Image(systemName: "faceid")
        case .touchID:
            Image(systemName: "touchid")
        case .opticID:
            Image(systemName: "opticid")
        @unknown default:
            Image(systemName: "lock.shield")
        }
    }
    
    // MARK: - 认证 (生物识别)
    
    private func authenticateWithBiometrics() {
        guard !isAuthenticating else { return }
        guard !isLockedOut else { return }
        guard retryCount < maxRetries else {
            startLockout()
            return
        }
        
        isAuthenticating = true
        authError = nil
        
        let context = LAContext()
        context.localizedCancelTitle = "キャンセル"
        // 不显示系统的 "输入密码" 回退按钮, 由我们自己的按钮处理
        context.localizedFallbackTitle = ""
        
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "EhViewer にアクセスするには本人確認を行ってください"
        ) { success, authenticationError in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    onAuthenticated()
                } else {
                    handleBiometricError(authenticationError)
                }
            }
        }
    }
    
    // MARK: - 认证 (设备密码 — Fallback)
    
    /// 使用 deviceOwnerAuthentication 策略弹出系统密码输入界面
    private func authenticateWithPasscode() {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        authError = nil
        
        let context = LAContext()
        context.localizedCancelTitle = "キャンセル"
        
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "EhViewer にアクセスするには本人確認を行ってください"
        ) { success, authenticationError in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    // 密码认证成功 — 同时重置生物识别锁定状态
                    retryCount = 0
                    isLockedOut = false
                    lockoutTimer?.invalidate()
                    lockoutTimer = nil
                    onAuthenticated()
                } else {
                    if let laError = authenticationError as? LAError, laError.code == .userCancel {
                        authError = "認証がキャンセルされました"
                    } else {
                        authError = authenticationError?.localizedDescription ?? "パスコード認証に失敗しました"
                    }
                }
            }
        }
    }
    
    // MARK: - 错误处理
    
    private func handleBiometricError(_ error: Error?) {
        retryCount += 1
        
        guard let laError = error as? LAError else {
            authError = error?.localizedDescription
            return
        }
        
        switch laError.code {
        case .userCancel:
            // 用户取消不算重试
            retryCount -= 1
            authError = "認証がキャンセルされました。ボタンをタップして再試行してください"
        case .userFallback:
            // 用户选择使用密码
            retryCount -= 1
            authenticateWithPasscode()
        case .biometryNotAvailable:
            authError = "生体認証が利用できません。パスコードでロック解除してください"
        case .biometryNotEnrolled:
            authError = "生体認証が設定されていません。パスコードでロック解除してください"
        case .biometryLockout:
            // Fix F1-2: 生物识别被系统锁定 — 引导使用密码
            authError = "生体認証がロックされています。下のパスコードでロック解除してください"
            startLockout()
        case .authenticationFailed:
            if retryCount >= maxRetries {
                startLockout()
            } else {
                authError = "認証に失敗しました。再試行してください"
            }
        default:
            authError = laError.localizedDescription
        }
    }
    
    // MARK: - 锁定管理
    
    /// Fix F1-2: 启动锁定倒计时, 60 秒后自动恢复
    private func startLockout() {
        isLockedOut = true
        lockoutRemaining = lockoutDuration
        authError = "生体認証の試行回数が多すぎます。パスコードでロック解除するか、\(lockoutDuration) 秒お待ちください"
        
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                lockoutRemaining -= 1
                if lockoutRemaining <= 0 {
                    isLockedOut = false
                    retryCount = 0
                    authError = nil
                    lockoutTimer?.invalidate()
                    lockoutTimer = nil
                }
            }
        }
    }
}

#Preview {
    SecurityView(onAuthenticated: { print("Authenticated") })
}
