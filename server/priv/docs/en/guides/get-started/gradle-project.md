---
{
  "title": "Gradle project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Gradle project to Tuist remote caching, build insights, and test insights."
}
---
# Gradle project {#gradle-project}

Add Tuist to an existing Gradle project without changing its project structure or build tasks. The Tuist Gradle plugin connects Gradle's build cache and build data to the same Tuist project used by your team and continuous integration environments.

## Adoption steps {#adoption-steps}

1. <.localized_link href="/guides/install-tuist">Install the Tuist command-line interface</.localized_link>, then follow the <.localized_link href="/guides/install-gradle-plugin">Gradle plugin installation guide</.localized_link> to run `tuist init` and add the `dev.tuist` plugin to `settings.gradle.kts`.
2. Run `./gradlew help` to confirm that Gradle can load the project and the Tuist plugin configuration.
3. Enable Gradle's build cache by adding `org.gradle.caching=true` to `gradle.properties`, as described in the <.localized_link href="/guides/features/cache/gradle-cache">Gradle cache guide</.localized_link>.
4. Decide where artifacts may be uploaded. A common setup allows continuous integration to upload while developer machines remain read-only.
5. Authenticate teammates and continuous integration by following the <.localized_link href="/guides/install-gradle-plugin#authenticate">plugin authentication steps</.localized_link>.

The plugin also enables <.localized_link href="/guides/features/build-insights/gradle">Gradle build insights</.localized_link> and <.localized_link href="/guides/features/test-insights/gradle">Gradle test insights</.localized_link>. These results are uploaded after builds and test tasks without replacing your existing Gradle commands.

## Verify your setup {#verify-your-setup}

1. Run a cacheable build in an authenticated clean environment:

   ```bash
   ./gradlew clean build --build-cache --info
   ```

2. Run the same revision and command in a second clean environment. Keep the local Gradle cache disabled there if you specifically want to verify the remote cache.
3. Confirm that cacheable tasks report `FROM-CACHE` in the second build.
4. Open the Tuist project dashboard and confirm that the build and its task data appear. Run the project's test tasks and confirm that their results appear under test insights.

If tasks execute again, use Gradle's `--info` output to identify non-cacheable tasks, then check the <.localized_link href="/guides/features/cache/gradle-cache">remote cache configuration</.localized_link> and authentication before changing your build logic.
