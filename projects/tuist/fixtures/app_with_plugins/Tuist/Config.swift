import ProjectDescription

 let config = Config(
     plugins: [
         .local(path: .relativeToManifest("../../LocalPlugin")),
         // TODO: Add to docs that it should not be with .git suffix
         .git(url: "https://github.com/fortmarek/ExampleTuistPlugin", tag: "0.2.0")
     ],
     generationOptions: []
 )
