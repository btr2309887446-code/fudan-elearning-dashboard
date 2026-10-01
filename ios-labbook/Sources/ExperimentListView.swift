import SwiftUI
import SwiftData
import Charts

struct ExperimentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Measurement.createdAt, order: .reverse)
    private var allItems: [Measurement]

    /// 新建流程：draft 是尚未入库的临时对象，取消时丢弃。
    @State private var draft: Measurement?
    /// 编辑流程：editing 是数据库里已有的对象，取消时不动它。
    @State private var editing: Measurement?

    /// 按实验名分组，同名记录聚在一起。
    private var groups: [(name: String, items: [Measurement])] {
        Dictionary(grouping: allItems, by: \.experiment)
            .map { (name: $0.key, items: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allItems.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("实验记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draft = Measurement(experiment: groups.first?.name ?? "未命名实验",
                                            label: "", value: 0, unit: .centimeter)
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $draft) { item in
                MeasurementEditor(measurement: item, isNew: true)
            }
            .sheet(item: $editing) { item in
                MeasurementEditor(measurement: item, isNew: false)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有数据", systemImage: "ruler")
        } description: {
            Text("点右上角 + 记录你的第一组测量值")
        } actions: {
            Button("记录第一条") {
                draft = Measurement(experiment: "未命名实验", label: "", value: 0, unit: .centimeter)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var listContent: some View {
        List {
            ForEach(groups, id: \.name) { group in
                Section {
                    ForEach(group.items) { item in
                        Button {
                            editing = item
                        } label: {
                            row(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        delete(offsets, in: group.items)
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.items.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if group.items.count >= 2 {
                        chart(for: group.items)
                            .frame(height: 150)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for item: Measurement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label.isEmpty ? "未命名" : item.label)
                    .font(.body)
                Text(item.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(item.value.formatted(.number.precision(.significantDigits(1...4)))) \(item.unit.rawValue)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }

    private func chart(for items: [Measurement]) -> some View {
        // 用 indices 而不是 enumerated()：后者在部分 Xcode 版本上 Chart 的类型推断会失败
        Chart(items.indices, id: \.self) { index in
            let item = items[index]
            LineMark(x: .value("序号", index + 1), y: .value("数值", item.value))
            PointMark(x: .value("序号", index + 1), y: .value("数值", item.value))
        }
        .chartXAxisLabel("测量序号")
        .chartYAxisLabel(items.first?.unit.rawValue ?? "")
    }

    private func delete(_ offsets: IndexSet, in items: [Measurement]) {
        for index in offsets {
            context.delete(items[index])
        }
    }
}
