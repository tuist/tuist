import ProjectDescription

let config = Config(
    cache: .cache(profiles: [
        .profile(
            name: "DeviceOnly",
            configuration: "Debug"
        ),
    ])
)
