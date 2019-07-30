import ProjectDescription

let config = TuistConfig(
  generationOptions: [
    .generateManifest,
    .xcodeProjectName("AwesomePrefix-\(TemplateString.Token.projectName)-AwesomeSuffix")
  ]
)
