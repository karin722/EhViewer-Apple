//
//  FilterView.swift
//  ehviewer apple
//
//  标签过滤管理视图
//

import SwiftUI
import EhDatabase

struct FilterView: View {
    @State private var vm = FilterViewModel()
    @State private var showAddSheet = false

    var body: some View {
        List {
            Section {
                Text("ルールに一致したギャラリーはすべてのリスト（ホーム、検索、購読、ランキング）から非表示になります。"
                     + "ルールはこのデバイスでのみ有効で、E-Hentai アカウントには同期されません。")
                    .font(EhFont.caption)
                    .foregroundStyle(EhColor.secondaryLabel)
            }

            // 快速屏蔽 (对齐 Android BlackListActivity)
            Section("よく使うブロック") {
                ForEach(vm.quickBlockPresets, id: \.tag) { preset in
                    Button {
                        vm.toggleQuickBlock(tag: preset.tag)
                    } label: {
                        HStack(spacing: EhSpacing.row) {
                            Image(systemName: vm.isTagBlocked(preset.tag)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vm.isTagBlocked(preset.tag)
                                                 ? EhColor.accent : EhColor.tertiaryLabel)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName).foregroundStyle(EhColor.label)
                                Text(preset.tag)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(EhColor.tertiaryLabel)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // 按类型分组，而不是按「已启用 / 已禁用」分。
            //
            // 原来那样分有两个问题：同一条规则会在两个区之间跳来跳去，
            // 用户找不到刚才那条；而且要判断「我到底屏蔽了哪些标签」，
            // 得把两个区合起来看。按类型分组之后，「我屏蔽了哪些标签」
            // 一眼就能数清，启用与否由行上的开关表达。
            ForEach(Self.modeOrder, id: \.self) { mode in
                let rules = vm.filters.filter { $0.mode == mode }
                if !rules.isEmpty {
                    Section(Self.modeTitle(mode)) {
                        ForEach(rules, id: \.id) { filter in
                            FilterRow(filter: filter) { isOn in
                                vm.setEnabled(filter, isOn)
                            }
                        }
                        .onDelete { offsets in
                            vm.delete(rules: rules, at: offsets)
                        }
                    }
                }
            }

            if vm.filters.isEmpty {
                Section {
                    Text("ルールはまだありません。右上から追加するか、ギャラリーの詳細画面でタグを長押しして「このタグをブロック」を選んでください。")
                        .font(EhFont.caption)
                        .foregroundStyle(EhColor.secondaryLabel)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("フィルター")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("ルールを追加")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFilterSheet(vm: vm)
        }
        .task { vm.loadFilters() }
    }

    private static let modeOrder = [2, 3, 0, 1, 4, 5]

    static func modeTitle(_ mode: Int) -> String {
        switch mode {
        case 0: return "タイトルに含む"
        case 1: return "アップローダー"
        case 2: return "ラベル"
        case 3: return "タグの名前空間"
        case 4: return "アップローダータグ"
        case 5: return "言語"
        default: return "その他"
        }
    }
}

// MARK: - Filter Row

struct FilterRow: View {
    let filter: FilterRecord
    /// 开关真正生效的回调。
    ///
    /// 此前这里是 `Toggle("", isOn: .constant(filter.enable))` 配
    /// `.onChange(of: filter.enable)`：常量绑定不会变，onChange 观察的又是
    /// 模型值——点开关什么都不会发生。整个控件是死的。
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { filter.enable }, set: { onToggle($0) })) {
            // 规则用等宽字体：过滤规则常含通配符与冒号，
            // 比例字体下 `l` `1` `I` 这类字符难以核对
            Text(filter.text ?? "")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(filter.enable ? EhColor.label : EhColor.tertiaryLabel)
        }
        .tint(EhColor.accentFill)
    }
}

// MARK: - Add Filter Sheet

struct AddFilterSheet: View {
    @Bindable var vm: FilterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var filterText = ""
    @State private var filterMode = 2  // 默认标签过滤

    private let filterModes: [(Int, String)] = [
        (0, "タイトル"),
        (1, "アップローダー"),
        (2, "ラベル"),
        (3, "タグの名前空間"),
        (4, "アップローダータグ"),
        (5, "言語")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("フィルター内容") {
                    TextField("フィルターするテキストを入力", text: $filterText)

                    Picker("フィルターの種類", selection: $filterMode) {
                        ForEach(filterModes, id: \.0) { mode, name in
                            Text(name).tag(mode)
                        }
                    }
                }

                Section {
                    Text(filterDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("フィルターを追加")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        vm.addFilter(text: filterText, mode: filterMode)
                        dismiss()
                    }
                    .disabled(filterText.isEmpty)
                }
            }
        }
    }

    private var filterDescription: String {
        switch filterMode {
        case 0: return "このテキストを含むタイトルはフィルターされます"
        case 1: return "このアップローダーのギャラリーはフィルターされます"
        case 2: return "このタグを含むギャラリーはフィルターされます (形式: namespace:tag)"
        case 3: return "この名前空間のタグを含むギャラリーはフィルターされます"
        case 4: return "このアップローダータグを含むギャラリーはフィルターされます"
        case 5: return "この言語のギャラリーはフィルターされます"
        default: return ""
        }
    }
}

// MARK: - ViewModel

@Observable
class FilterViewModel {
    var filters: [FilterRecord] = []

    // 快速屏蔽预设 (对齐 Android BlackList)
    struct QuickBlockPreset {
        let displayName: String
        let tag: String
    }

    let quickBlockPresets: [QuickBlockPreset] = [
        QuickBlockPreset(displayName: "ふたなり (Futanari)", tag: "female:futanari"),
        QuickBlockPreset(displayName: "R-18G (猟奇)", tag: "mixed:guro"),
        QuickBlockPreset(displayName: "獣姦 (Bestiality)", tag: "female:bestiality"),
        QuickBlockPreset(displayName: "ケモノ (Furry)", tag: "male:furry"),
        QuickBlockPreset(displayName: "NTR (寝取られ)", tag: "female:netorare"),
        QuickBlockPreset(displayName: "薬物 (Drug)", tag: "female:drugs"),
    ]

    func isTagBlocked(_ tag: String) -> Bool {
        filters.contains { $0.mode == 2 && $0.text == tag && $0.enable }
    }

    /// 常用屏蔽是个开关，不是单向按钮：点第二下要能取消。
    /// 此前只有「屏蔽」按钮，屏蔽完变成一个对勾，想撤销得去下面的列表里找。
    func toggleQuickBlock(tag: String) {
        if let existing = filters.first(where: { $0.mode == 2 && $0.text == tag }) {
            if let id = existing.id { try? EhDatabase.shared.deleteFilter(id: id) }
            loadFilters()
            notifyChanged()
            EhToast.info("「\(tag)」のブロックを解除しました")
        } else {
            addFilter(text: tag, mode: 2)
        }
    }

    func loadFilters() {
        do {
            filters = try EhDatabase.shared.getAllFilters()
        } catch {
            debugLog("Failed to load filters: \(error)")
        }
    }

    func addFilter(text: String, mode: Int) {
        let record = FilterRecord(mode: mode, text: text, enable: true)
        do {
            try EhDatabase.shared.insertFilter(record)
            loadFilters()
            notifyChanged()
            EhToast.success("ルールを追加しました")
        } catch {
            EhToast.failure("ルールの追加に失敗しました")
            debugLog("Failed to add filter: \(error)")
        }
    }

    /// 原地改启用状态。此前是「删掉再插入」，id 会变、列表顺序会跳。
    func setEnabled(_ filter: FilterRecord, _ enabled: Bool) {
        var updated = filter
        updated.enable = enabled
        do {
            try EhDatabase.shared.updateFilter(updated)
            loadFilters()
            notifyChanged()
        } catch {
            EhToast.failure("このルールは変更できません")
            debugLog("Failed to toggle filter: \(error)")
        }
    }

    func delete(rules: [FilterRecord], at offsets: IndexSet) {
        for index in offsets {
            guard let id = rules[index].id else { continue }
            try? EhDatabase.shared.deleteFilter(id: id)
        }
        loadFilters()
        notifyChanged()
    }

    /// 让过滤引擎重新加载 —— 不发这个通知，改完规则要重启 App 才生效
    private func notifyChanged() {
        NotificationCenter.default.post(name: .galleryFiltersChanged, object: nil)
    }


}

#Preview {
    NavigationStack {
        FilterView()
    }
}
