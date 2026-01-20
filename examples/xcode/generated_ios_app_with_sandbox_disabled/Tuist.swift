import ProjectDescription

let disableSandbox = Environment.disableSandbox.getBoolean(default: true)
let config = Config(project: .tuist(generationOptions: .options(disableSandbox: disableSandbox)))
