import Foundation

/// 安全的 JSON 字典提取工具（严格区分 Foundation 中 NSNumber 与 CFBoolean）
public enum JSONHelpers {
    public static func bool(_ value: Any?) -> Bool? {
        guard let num = value as? NSNumber else { return nil }
        if CFGetTypeID(num) == CFBooleanGetTypeID() {
            return num.boolValue
        }
        return nil
    }

    public static func int(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
            let val = num.int64Value
            return (val >= 0 && val <= Int64(Int.max)) ? Int(val) : nil
        }
        if let str = value as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let val = Int64(trimmed), val >= 0, val <= Int64(Int.max) else { return nil }
            return Int(val)
        }
        return nil
    }

    public static func signedInt(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
            return num.intValue
        }
        if let str = value as? String {
            return Int(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    public static func int64(_ value: Any?) -> Int64? {
        guard let value, !(value is NSNull) else { return nil }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
            return num.int64Value
        }
        if let str = value as? String {
            return Int64(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    public static func double(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
            return num.doubleValue
        }
        if let str = value as? String {
            return Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    public static func string(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let str = value as? String { return str }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return num.stringValue
        }
        return "\(value)"
    }

    /// 广度优先查找嵌套 JSON 中首个非空字符串字段
    public static func findFirstString(in root: Any, keys: Set<String>, limit: Int = 3000) -> String? {
        var queue: [Any] = [root]
        var cursor = 0
        var visited = 0
        while cursor < queue.count && visited < limit {
            let node = queue[cursor]
            cursor += 1
            visited += 1
            if let dict = node as? [String: Any] {
                for (k, v) in dict where keys.contains(k) {
                    if let str = v as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return str
                    }
                }
                for (_, v) in dict {
                    if v is [String: Any] || v is [Any] {
                        queue.append(v)
                    }
                }
            } else if let arr = node as? [Any] {
                for item in arr where item is [String: Any] || item is [Any] {
                    queue.append(item)
                }
            }
        }
        return nil
    }
}
