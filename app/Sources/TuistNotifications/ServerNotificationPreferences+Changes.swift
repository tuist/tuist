import TuistServer

/// Applies a change locally the way the server resolves it, so the UI can update before the server responds.
extension ServerNotificationPreferences {
    mutating func setAccountEnabled(_ enabled: Bool, accountHandle: String) {
        guard let index = accounts.firstIndex(where: { $0.handle == accountHandle }) else { return }
        accounts[index].enabled = enabled
        accounts[index].resolveProjects()
    }

    mutating func setProjectSetting(_ setting: ProjectSetting, accountHandle: String, projectHandle: String) {
        guard let index = accounts.firstIndex(where: { $0.handle == accountHandle }),
              let projectIndex = accounts[index].projects.firstIndex(where: { $0.handle == projectHandle })
        else { return }
        accounts[index].projects[projectIndex].setting = setting
        accounts[index].resolveProjects()
    }

    func account(_ handle: String) -> Account? {
        accounts.first { $0.handle == handle }
    }
}

extension ServerNotificationPreferences.Account {
    /// The setting that makes a project `enabled`: following the account when it agrees, an override otherwise.
    func projectSetting(enabled: Bool) -> ServerNotificationPreferences.ProjectSetting {
        enabled == self.enabled ? .default : enabled ? .on : .off
    }

    func project(_ handle: String) -> ServerNotificationPreferences.Project? {
        projects.first { $0.handle == handle }
    }

    fileprivate mutating func resolveProjects() {
        for index in projects.indices {
            projects[index].enabled = switch projects[index].setting {
            case .default: enabled
            case .on: true
            case .off: false
            }
        }
    }
}
