---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Continuous Integration (CI) {#continuous-integration-ci}

The registry works out of the box on CI without any additional authentication setup. By default, unauthenticated requests are rate-limited to **1,000 requests per minute** per IP address.

If you need a higher rate limit of **20,000 requests per minute**, you can authenticate by running `tuist registry login`. This requires the `TUIST_TOKEN` environment variable to be set. You can create a project token by following the documentation <.localized_link href="/guides/server/authentication#as-a-project">here</.localized_link>.

> [!NOTE]
> The keychain setup below is only required if you use `tuist registry login` to get higher rate limits. In most cases, the default unauthenticated rate limit is sufficient and you can skip this entirely.
>
> Additionally, creating a new pre-unlocked keychain is only needed when using the Xcode integration of packages.


Since `tuist registry login` stores credentials in a keychain, you need to ensure the keychain can be accessed in the CI environment. Note some CI providers or automation tools like [Fastlane](https://fastlane.tools/) already create a temporary keychain or provide a built-in way how to create one. However, you can also create one by creating a custom step with the following code:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

Ensure that your default keychain is created and unlocked _before_ running `tuist registry login`.

### Incremental resolution across environments {#incremental-resolution-across-environments}

Clean/cold resolutions are slightly faster with our registry, and you can experience even greater improvements if you persist the resolved dependencies across CI builds. Note that thanks to the registry, the size of the directory that you need to store and restore is much smaller than without the registry, taking significantly less time.
To cache dependencies when using the default Xcode package integration, the best way is to specify a custom `clonedSourcePackagesDirPath` when resolving dependencies via `xcodebuild`. This can be done by adding the following to your `Config.swift` file:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Additionally, you will need to find a path of the `Package.resolved`. You can grab the path by running `ls **/Package.resolved`. The path should look something like `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

For Swift packages and the XcodeProj-based integration, we can use the default `.build` directory located either in the root of the project or in the `Tuist` directory. Make sure the path is correct when setting up your pipeline.

Here's an example workflow for GitHub Actions for resolving and caching dependencies when using the default Xcode package integration:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
