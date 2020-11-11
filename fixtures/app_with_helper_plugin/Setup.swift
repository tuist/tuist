import ProjectDescription
import ProjectDescriptionHelpers
import LocalTuistHelpers

let setup = Setup([
    .custom(name: "My Custom Tool", meet: ["touch", "/tmp/my_test_tool"], isMet: ["ls", "/tmp/my_test_tool"])
])
