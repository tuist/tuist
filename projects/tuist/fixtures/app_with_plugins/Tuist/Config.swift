import ProjectDescription

 let config = Config(
     plugins: [
         .local(path: .relativeToManifest("../../LocalPlugin")),
         .git(url: "https://github.com/fortmarek/ExampleTuistPlugin.git", tag: "0.2.0")
     ],
     generationOptions: []
 )
