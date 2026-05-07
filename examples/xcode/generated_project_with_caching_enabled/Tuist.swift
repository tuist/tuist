import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    url: "http://localhost:8080",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    ),
)
