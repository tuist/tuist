import ProjectDescription

let setup = Setup([
    .custom(name: "My Custom Tool", meet: ["touch", "/tmp/my_test_tool"], isMet: ["ls", "/tmp/my_test_tool"]),
    .carthage(platforms: [.iOS], useXCFrameworks: true, noUseBinaries: true),
])
