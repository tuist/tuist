import ProjectDescription

let config = TuistConfig(
  generationOptions: [
    .xcodeProjectName("AwesomePrefix-\(.projectName)-AwesomeSuffix")
  ]
)
