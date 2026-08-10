import ProjectDescription

extension ProjectDescription.SettingsDictionary {
    /// Performs a deep merge of another SettingsDictionary.
    /// - If both values are arrays and the new array contains "$(inherited)", they are concatenated.
    /// - Otherwise, the new value overwrites the old value.
    mutating func deepMerge(_ other: ProjectDescription.SettingsDictionary) {
        for (key, newValue) in other {
            if let existingValue = self[key],
               case let .array(existingArray) = existingValue,
               case let .array(newArray) = newValue,
               newArray.contains("$(inherited)")
            {
                // Combine arrays, removing $(inherited) from both sets to deduplicate,
                // then prepend a single $(inherited) at the start.
                let combined = existingArray.filter { $0 != "$(inherited)" } + newArray.filter { $0 != "$(inherited)" }
                self[key] = .array(["$(inherited)"] + combined)
            } else {
                self[key] = newValue
            }
        }
    }
}
