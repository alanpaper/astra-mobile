import SwiftUI

/// 欢迎页：绑定入口 + 已绑定桌面端列表
struct WelcomeView: View {
    @EnvironmentObject var store: DesktopStore
    @EnvironmentObject var appState: AppState
    @State private var pasteError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        appState.showScanner = true
                    } label: {
                        Label("扫描桌面端二维码", systemImage: "qrcode.viewfinder")
                            .font(.body.weight(.semibold))
                    }
                    Button {
                        bindFromPasteboard()
                    } label: {
                        Label("粘贴链接绑定", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("绑定桌面端")
                } footer: {
                    Text("在桌面端 Astra 的「手机遥控」页生成设备密钥二维码后扫描；密钥只存于本机 Keychain。")
                }

                if !store.desktops.isEmpty {
                    Section("已绑定的桌面端") {
                        ForEach(store.desktops) { desktop in
                            Button {
                                store.select(desktop.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(desktop.label)
                                        .font(.body.monospaced())
                                        .foregroundStyle(.primary)
                                    Text("添加于 \(desktop.addedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indices in
                            for index in indices {
                                store.remove(store.desktops[index].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Astra")
            .alert("无法绑定",
                   isPresented: Binding(get: { pasteError != nil },
                                        set: { if !$0 { pasteError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(pasteError ?? "")
            }
        }
    }

    private func bindFromPasteboard() {
        guard let raw = UIPasteboard.general.string, !raw.isEmpty else {
            pasteError = "剪贴板为空"
            return
        }
        guard let target = BindTarget.parse(raw) else {
            pasteError = "剪贴板内容不是 Astra 绑定链接\n（应为 http://host:port/m#secret）"
            return
        }
        store.bind(target)
    }
}
