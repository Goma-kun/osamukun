import SwiftUI
#if os(macOS)
import ServiceManagement
#endif

/// 設定。Mac は呼び出しキー・貼り付けの許可・ログイン時に起動。
/// 言語は OS の設定に従う（日本語なら日本語、それ以外は英語）ので、ここでは選ばせない
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    #if os(macOS)
    @State private var combo = HotKey.shared.combo
    @State private var recording = false
    @State private var trusted = Paster.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var monitor: Any?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    #endif

    var body: some View {
        Form {
            #if os(macOS)
            Section {
                LabeledContent(String(localized: "呼び出しキー")) {
                    HStack(spacing: 8) {
                        Text(recording ? String(localized: "キーを押してください…") : combo.display)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(recording ? Theme.dirtyBg : Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                        Button(recording ? String(localized: "やめる") : String(localized: "変更…")) { recording ? stopRecording() : startRecording() }
                        if combo != .default {
                            Button(String(localized: "既定に戻す")) { apply(.default) }
                        }
                    }
                }
                Text("どのアプリを使っていても、このキーで検索パネルが開きます。⌘・⌥・⌃ のどれかを含むキーにしてください。")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } header: { Text("呼び出し") }

            Section {
                LabeledContent(String(localized: "直接貼り付け")) {
                    HStack(spacing: 8) {
                        Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(trusted ? Theme.savedFg : Theme.dirtyFg)
                        Text(trusted ? String(localized: "許可されています") : String(localized: "まだ許可されていません"))
                    }
                }
                if !trusted {
                    HStack {
                        Button(String(localized: "許可する…")) { Paster.requestTrust() }.buttonStyle(.borderedProminent)
                        Button(String(localized: "システム設定を開く")) { Paster.openAccessibilitySettings() }
                    }
                }
                Text("選んだ本文を、直前に使っていたアプリへそのまま貼り付けるには、システム設定 › プライバシーとセキュリティ › アクセシビリティ で「おさむくん」をオンにしてください。許可が無いときはクリップボードにコピーするところまで行い、⌘V は自分で押す形になります。おさむくんは画面の内容を読みません。")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } header: { Text("貼り付け") }

            Section {
                Toggle(String(localized: "ログイン時におさむくんを起動"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            } header: { Text("起動") }
            #endif

            Section {
                LabeledContent(String(localized: "バージョン"), value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent(String(localized: "定型文"), value: String(localized: "\(model.templates.count)件"))
                Text("データはこの Mac の中にだけ保存されます。外部に送ることはありません。")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } header: { Text("このアプリについて") }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .onReceive(tick) { _ in trusted = Paster.isTrusted }
        .onDisappear { stopRecording() }
        #endif
    }

    #if os(macOS)
    private func startRecording() {
        recording = true
        HotKey.shared.unregister()   // 録音中は今のキーを外して、同じキーを押し直せるようにする
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { Task { @MainActor in stopRecording() }; return nil }
            guard let c = HotKey.Combo.from(e) else { return nil }
            Task { @MainActor in apply(c) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKey.shared.register()
    }

    private func apply(_ c: HotKey.Combo) {
        stopRecording()
        HotKey.shared.set(c)
        combo = c
        if !HotKey.shared.register() {
            model.showToast(String(localized: "このキーは登録できませんでした。別のキーにしてください"), isError: true)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            model.showToast(String(localized: "ログイン時の起動を変更できませんでした：\(error.localizedDescription)"), isError: true)
        }
    }
    #endif
}
