import Foundation
import SwiftData

/// 单位。原始值必须是 String，SwiftData 对 String 枚举支持最稳。
enum MeasureUnit: String, CaseIterable, Identifiable {
    case millimeter = "mm"
    case centimeter = "cm"
    case meter = "m"
    case gram = "g"
    case kilogram = "kg"
    case second = "s"
    case celsius = "°C"
    case other = "—"

    var id: String { rawValue }

    /// 换算到同类基本单位的倍数（mm/cm → m，g/kg → kg）。
    /// 无量纲或未知单位返回 1，这样图表里按原文比较。
    var toBaseFactor: Double {
        switch self {
        case .millimeter: return 0.001
        case .centimeter: return 0.01
        case .meter: return 1
        case .gram: return 0.001
        case .kilogram: return 1
        case .second, .celsius, .other: return 1
        }
    }
}

/// 一条测量记录。
@Model
final class Measurement {
    var experiment: String
    var label: String
    var value: Double
    var unitRaw: String
    var note: String
    var createdAt: Date

    init(
        experiment: String,
        label: String,
        value: Double,
        unit: MeasureUnit,
        note: String = "",
        createdAt: Date = .now
    ) {
        self.experiment = experiment
        self.label = label
        self.value = value
        self.unitRaw = unit.rawValue
        self.note = note
        self.createdAt = createdAt
    }

    var unit: MeasureUnit { MeasureUnit(rawValue: unitRaw) ?? .other }

    /// 换算成基本单位后的数值，用于跨记录比较。
    var baseValue: Double { value * unit.toBaseFactor }
}
