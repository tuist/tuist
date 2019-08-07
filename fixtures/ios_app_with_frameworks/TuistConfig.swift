import ProjectDescription

let config = TuistConfig(
  generationOptions: [
    .generateManifest,
    .xcodeProjectName("AwesomePrefix-\(.projectName)-AwesomeSuffix")
  ]
)