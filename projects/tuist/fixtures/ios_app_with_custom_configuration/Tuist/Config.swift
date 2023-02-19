import ProjectDescription

let config = Config(
    cache: .cache(
        profiles: [.profile(name: "Simulator", configuration: "debug", device: "iPhone 14 Pro")],
        path: .relativeToRoot("TuistCache")
    )
)
