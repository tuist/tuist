import ProjectDescription

enum SettingsDictionaryArrayMergePolicy {
    case replaceUnlessInherited
    case append
}

extension ProjectDescription.SettingsDictionary {
    mutating func merge(
        _ other: ProjectDescription.SettingsDictionary,
        arrayMergePolicy: SettingsDictionaryArrayMergePolicy
    ) {
        for (key, newValue) in other {
            guard let existingValue = self[key],
                  case let .array(existingArray) = existingValue,
                  case let .array(newArray) = newValue
            else {
                self[key] = newValue
                continue
            }

            let inherited = "$(inherited)"
            switch arrayMergePolicy {
            case .replaceUnlessInherited:
                guard newArray.contains(inherited) else {
                    self[key] = newValue
                    continue
                }

                let combined = existingArray.filter { $0 != inherited } + newArray.filter { $0 != inherited }
                self[key] = .array([inherited] + combined)
            case .append:
                self[key] = .array(existingArray + newArray)
            }
        }
    }
}
