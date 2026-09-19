import ProjectDescription

enum SettingsDictionaryMergePolicy {
    case inheritFromProject
    case appendArrays
}

extension ProjectDescription.SettingsDictionary {
    mutating func merge(
        _ other: ProjectDescription.SettingsDictionary,
        policy: SettingsDictionaryMergePolicy
    ) {
        for (key, newValue) in other {
            switch policy {
            case .inheritFromProject:
                guard newValue.containsInherited else {
                    self[key] = newValue
                    continue
                }

                guard let existingValue = self[key] else {
                    continue
                }
                self[key] = existingValue.inheriting
            case .appendArrays:
                guard let existingValue = self[key],
                      case let .array(existingArray) = existingValue,
                      case let .array(newArray) = newValue
                else {
                    self[key] = newValue
                    continue
                }
                self[key] = .array(existingArray + newArray)
            }
        }
    }
}

extension ProjectDescription.SettingValue {
    fileprivate var containsInherited: Bool {
        switch self {
        case let .string(value):
            value.contains("$(inherited)")
        case let .array(values):
            values.contains { $0.contains("$(inherited)") }
        @unknown default:
            false
        }
    }

    fileprivate var inheriting: Self {
        let inherited = "$(inherited)"
        switch self {
        case let .string(value):
            guard !value.contains(inherited) else {
                return self
            }
            return .array([inherited, value])
        case let .array(values):
            return .array([inherited] + values.filter { $0 != inherited })
        @unknown default:
            return self
        }
    }
}
