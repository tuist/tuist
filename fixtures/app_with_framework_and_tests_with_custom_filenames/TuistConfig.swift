import ProjectDescription

let config = TuistConfig(
  generationOptions: [
    .generateManifest,
    .prefixProjectNames(with: "AwesomePrefix-"),
    .suffixProjectNames(with: "-AwesomeSuffix")
  ]
)