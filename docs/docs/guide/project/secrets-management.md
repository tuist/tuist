# Secrets Management

Most projects have the need to consume secrets (API Keys, Tokens, etc). Putting these directly in the codebase or the application package in plain-text is discouraged as it poses security risk of the keys getting misused if the code repository leaks or an attacker dumps and decrypts the App binary. 

Common solutions involve generating some scrambled version of these keys in code and decrypting them at runtime. 

## Arkana
[Arkana](https://github.com/rogerluan/arkana) can be used in it's SPM mode and consumed in Tuist through `Package.swift`. It provides similar feature-set and functionality as [cocoapods-keys](https://github.com/orta/cocoapods-keys) without the dependency on CocoaPods.

First create a `.arkana.yml` configuration file at the root of the project
```bash
import_name: 'TuxieKeys' # Name of the SPM Package for your encrypted keys
namespace: 'Keys' # Namespace for the keys you want to create
result_path: 'TuxieKeys' # Path where you want the SPM containing the encrypted keys to be created
global_secrets: # Add the list of keys you want Arakana to fetch from 
  - <Key1>
```

Then create a `.env` file at the same location containing the key-value pairs for your secrets. Ensure to have this under `.gitignore` so that you don't commit it to your codebase. This file will have to be distributed to your team incase they need to use these secrets during development.
```bash
<Key 1>=<Key 1 Value>
```

Add the Arkana gem to your Gemfile and run `bundle install`

Then run `bundle exec arkana` to generate the SPM named `TuxieKeys` containing your secrets.

To consume this SPM in our Tuist project, we need to mention the Generated SPM package in `Package.swift`
```swift
let package = Package(
    name: "PackageName",
    dependencies: [
        .package(name: "ArkanaKeys", path: "path/to/your/dependencies/ArkanaKeys")
        ...
    ]
)
```

and in the dependencies of a target consume it as 
```swift
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "TuxieKeys"), 
            ]
        ),
    ]
)
```

Then running `tuist install` and then `tuist generate` should give us a workspace where we can import and use our encrypted secrets as follows
```swift
import TuxieKeys

let secret1 = TuxieKeys.Keys.Global().key1
```

> [!TIP]
>The more advanced usage instructions are documented in the [Arkana ReadMe](https://github.com/rogerluan/arkana?tab=readme-ov-file#usage)
