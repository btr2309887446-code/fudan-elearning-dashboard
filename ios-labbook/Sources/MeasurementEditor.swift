import SwiftUI
import SwiftData

/// 新建/编辑一条测量记录。
struct MeasurementEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 新建时传进来的是「还没插入数据库」的临时对象，取消时要丢掉它。
    @State private var item: Measurement
    private let isNew: Bool

    @State private var valueText: String
    @FocusState private var valueFocused: Bool

    init(measurement: Measurement, isNew: Bool) {
        _item = State(initialValue: measurement)
        self.isNew = isNew
        valueText = measurement.value == 0 ? "" : String(measurement.value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("实验") {
                    TextField("实验名称", text: $item.experiment)
                        .textInputAutocapitalization(.never)
                }

                Section("测量值") {
                    TextField("标签，如 第 1 次", text: $item.label)
                    HStack {
                        TextField("数值", text: $valueText)
                            .keyboardType(.decimalPad)
                            .focused($valueFocused)
                        Divider()
                        Picker("单位", selection: $item.unitRaw) {
                            ForEach(MeasureUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                Section("备注") {
                    TextField("可选", text: $item.note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        // 新建流程取消时，把这条临时对象删掉，避免留下脏数据
                        if isNew { context.delete(item) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { valueFocused = true }
        }
    }

    private var canSave: Bool {
        !item.experiment.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(valueText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    private func save() {
        guard let value = Double(valueText.replacingOccurrences(of: ",", with: ".")) else { return }
        item.value = value
        // insert 重复调用同一个对象是安全的，SwiftData 会去重
        context.insert(item)
        try? context.save()
        dismiss()
    }
}
