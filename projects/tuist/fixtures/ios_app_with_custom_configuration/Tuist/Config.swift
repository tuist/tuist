import ProjectDescription

let config = Config(
    cache: .cache(
        profiles: [.profile(name: "Simulator", configuration: "debug", device: "iPhone 13 Pro")],
        path: .relativeToRoot("TuistCache")
    )
)
