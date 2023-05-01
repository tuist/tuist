struct XCTestPlan: Decodable {
    struct Target: Decodable {
        let projectPath: String
        let name: String

        enum CodingKeys: CodingKey {
            case containerPath
            case name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let containerPath = try container.decode(String.self, forKey: .containerPath)
            let containerInfo = containerPath.split(separator: ":")
            switch containerInfo.count {
            case 1:
                projectPath = containerPath
            case 2 where containerInfo[0] == "container":
                projectPath = String(containerInfo[1])
            default:
                throw DecodingError.valueNotFound(
                    String.self,
                    .init(codingPath: container.codingPath, debugDescription: "Invalid containerPath")
                )
            }
            name = try container.decode(String.self, forKey: .name)
        }
    }

    struct TestTarget: Decodable {
        let enabled: Bool
        let target: Target

        enum CodingKeys: CodingKey {
            case enabled
            case target
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            target = try container.decode(XCTestPlan.Target.self, forKey: .target)
        }
    }

    let testTargets: [TestTarget]
}
