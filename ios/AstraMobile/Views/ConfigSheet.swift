import SwiftUI

/// 配置 sheet（原生复刻页面 cfgSheet）：本机名称 / 思考 / 模型来源 / 放权
struct ConfigSheet: View {
    @EnvironmentObject var store: ShellStore

    @State private var nameDraft = ""

    private let effortOptions: [(String, String, String)] = [
        ("minimal", "Minimal", "最省"),
        ("low", "Low", "低"),
        ("medium", "Medium", "中（默认）"),
        ("high", "High", "最强"),
    ]
    private let autoModeOptions: [(String, String, String)] = [
        ("off", "关", "所有工具弹卡确认"),
        ("project", "项目内", "项目目录内自动批准"),
        ("workspace", "工作区内", "工作空间内自动批准"),
        ("all", "全部", "全部自动批准"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let config = store.config {
                    Form { sections(config) }
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("等待桌面端配置…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("模型与思考")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { nameDraft = store.senderName }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func sections(_ config: BridgeConfig) -> some View {
        // 本机名称：多设备扫同一码时区分消息来源
        Section("本机名称") {
            HStack {
                TextField("设备名（最多 12 字）", text: $nameDraft)
                    .maxLength($nameDraft, 12)
                Button("保存") {
                    let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.senderName = trimmed
                }
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }

        Section("思考模式") {
            Picker("思考", selection: bindingBool(
                get: { config.thinkingEnabled },
                set: { store.setThinking(enabled: $0) })) {
                Text("开").tag(true)
                Text("关").tag(false)
            }
            .pickerStyle(.segmented)
        }

        Section("思考力度") {
            ForEach(effortOptions, id: \.0) { value, title, subtitle in
                optionRow(title: title, subtitle: subtitle, selected: config.thinkingEffort == value) {
                    store.setThinkingEffort(value)
                }
            }
        }

        Section("模型来源") {
            ForEach(config.runningModels, id: \.port) { model in
                optionRow(title: model.label, subtitle: "本地运行", selected: config.sourceType == "model" && config.modelPort == model.port) {
                    store.setModelPort(model.port)
                }
            }
            ForEach(config.providers, id: \.id) { provider in
                optionRow(title: provider.name, subtitle: provider.activeModel ?? "API", selected: config.sourceType == "provider" && config.providerId == provider.id && config.overrideModel == nil) {
                    store.setModelProvider(provider.id)
                }
            }
        }

        // 当前 provider 的可选模型（override）
        if config.sourceType == "provider", config.providerId != nil, !config.providerModels.isEmpty {
            Section("该提供者的模型") {
                ForEach(config.providerModels, id: \.self) { model in
                    optionRow(title: model, subtitle: nil, selected: config.overrideModel == model) {
                        store.setOverrideModel(model)
                    }
                }
            }
        }

        Section("权限放权") {
            ForEach(autoModeOptions, id: \.0) { value, title, subtitle in
                optionRow(title: title, subtitle: subtitle, selected: config.autoMode == value) {
                    store.setAutoMode(value)
                }
            }
        }

        Section {
            Text("改动即时同步到 PC，影响之后发送的消息；正在运行的一轮不受影响。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func optionRow(title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func bindingBool(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: set)
    }
}

extension View {
    /// 限制输入长度（本机名称最多 12 字）—— iOS16 单参 onChange 版本
    func maxLength(_ text: Binding<String>, _ limit: Int) -> some View {
        onChange(of: text.wrappedValue) { newValue in
            if newValue.count > limit {
                text.wrappedValue = String(newValue.prefix(limit))
            }
        }
    }
}
