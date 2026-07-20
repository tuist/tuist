defmodule Tuist.MCP.GradleIntegrationGuide do
  @moduledoc false

  @plugin_version "0.10.0"

  def plugin_version, do: @plugin_version

  def text(args \\ %{}) do
    account_handle = Map.get(args, "account_handle")
    project_handle = Map.get(args, "project_handle")
    server_url = Map.get(args, "server_url") || Tuist.Environment.app_url()
    features = Map.get(args, "features")

    project =
      if account_handle && project_handle,
        do: "`#{account_handle}/#{project_handle}`",
        else: "the Tuist project selected during setup"

    feature_instruction =
      case features do
        value when is_binary(value) and value != "" ->
          "The requested features are `#{value}`. Configure those features and skip unrelated optional setup."

        _ ->
          "For a general build-speed request, configure the remote build cache and build insights first. Add test features only when the user asks for them or the repository has a clear test-performance problem."
      end

    insecure_protocol =
      if String.starts_with?(server_url, "http://") do
        """
                allowInsecureProtocol = true
        """
      else
        ""
      end

    """
    # Optimize an existing Gradle project with Tuist

    Integrate #{project} with the Tuist server at `#{server_url}` using Gradle plugin version `#{@plugin_version}`.

    #{feature_instruction}

    ## 1. Establish a baseline

    Read the repository instructions and existing Gradle settings before editing. Identify the smallest meaningful build task that represents the user's slow workflow. Run it once without Tuist and record elapsed time, executed task count, and existing local cache hits. Preserve the repository's current Kotlin or Groovy file style and plugin-management conventions.

    ## 2. Complete both authentication layers

    [Model Context Protocol](https://modelcontextprotocol.io/) authentication only authorizes this agent to call Tuist tools. It is not a credential for Gradle builds.

    If the Model Context Protocol connection is unauthenticated, fetch the protected-resource metadata advertised by its `401 Unauthorized` response, fetch the authorization-server metadata, read `agent_auth.skill`, and follow Tuist's local [`auth.md`](https://workos.com/auth-md) document through registration and identity-assertion exchange. Prefer anonymous registration when no trusted provider assertion is available. Do not invent an email address or password. Before sending a service-authenticated email or starting an anonymous claim, explicitly ask the user to confirm the email address for their Tuist account; do not derive it from a provider profile, Git configuration, environment variables, or session metadata. Show the verification link and six-digit code together, and tell the user to enter the code on the Tuist page.

    1. Use `list_accounts` to discover account handles, then `list_projects` to reuse an existing Gradle project when appropriate.
    2. If needed, call `create_project` with `build_system=gradle`. Create an organization only when the user explicitly wants one.
    3. Verify command-line authentication against the same server URL:

       ```sh
       tuist auth whoami --url #{server_url}
       ```

    4. If that command is not authenticated, stop and ask the user to run:

       ```sh
       tuist auth login --url #{server_url}
       ```

       Do not invent credentials, reuse a Model Context Protocol token as a build token, or continue to a Gradle verification build. After the user finishes, rerun `tuist auth whoami` yourself.

    Keep the server origin identical everywhere, including the hostname spelling. For example, credentials stored for `localhost` are not discovered when the project uses `127.0.0.1`.

    ## 3. Bind the project and apply the plugin

    Create `tuist.toml` at the repository root so the Tuist command line and Gradle plugin share one identity:

    ```toml
    project = "ACCOUNT_HANDLE/PROJECT_HANDLE"
    url = "#{server_url}"
    ```

    Replace the placeholders with the handle returned by `list_projects` or `create_project`.

    Apply the settings plugin through the repository's existing plugin-management style:

    ```kotlin
    plugins {
        id("dev.tuist") version "#{@plugin_version}"
    }

    tuist {
        uploadInBackground = false

        buildCache {
            push = System.getenv("CI") != null
    #{insecure_protocol}    }
    }

    buildCache {
        local {
            isEnabled = System.getenv("CI") == null
        }
    }
    ```

    `uploadInBackground = false` makes agent-driven validation deterministic. Keep it for local or self-hosted servers when using plugin version `#{@plugin_version}`. Hosted-server users may remove it after verification to restore background uploads for local builds. `allowInsecureProtocol` is required only for a local `http://` server and must not be enabled for `https://`.

    Enable Gradle's build cache in `gradle.properties`:

    ```properties
    org.gradle.caching=true
    ```

    The `CI` variable means the [continuous integration environment](https://docs.gradle.org/current/userguide/ci_systems.html): shared runners upload reproducible entries, local builds read them, and the local Gradle cache is disabled on runners.

    ## 4. Prove the integration

    Use the same meaningful task as the baseline. In headless or print mode, run every measured build in the foreground, set the client's command-tool timeout long enough for the build, and do not end the agent turn while a background build is pending. Start with a foreground upload from a clean state, then run a clean read-only build:

    ```sh
    CI=1 ./gradlew clean TASK --build-cache --no-daemon --console=plain
    ./gradlew clean TASK --build-cache --no-daemon --console=plain
    ```

    Replace `TASK` with the selected task. For Claude Code print mode, pass an explicit long `timeout` to the Bash tool so it does not automatically move the build into a background task and end the turn. If the repository cannot run `clean` and `TASK` in one invocation, run `./gradlew clean` separately immediately before each measured build. If setting `CI=1` changes unrelated repository behavior, temporarily set `push = true` for the first build and restore the continuous-integration-only policy before finishing.

    After each build, call `list_gradle_builds`. Inspect the second build with `get_gradle_build` and `list_gradle_build_tasks`. Do not report success until:

    - both Gradle commands exit successfully,
    - the builds appear under the intended Tuist project,
    - the second build contains remote cache hits for cacheable tasks, and
    - the final files retain the conditional upload policy.

    ## Optional test features

    Test insights are collected automatically from Gradle `Test` tasks after the plugin is applied. For flaky-test detection, use the [Gradle Test Retry plugin](https://github.com/gradle/test-retry-gradle-plugin) only when the project does not already have a retry mechanism. Tuist test quarantine is enabled automatically in continuous integration and disabled locally; configure `testQuarantine.enabled` explicitly only when the user requests an override.

    For test sharding, prepare a plan in continuous integration and run each shard with its assigned index:

    ```sh
    ./gradlew tuistPrepareTestShards -PtuistShardMax=5
    TUIST_SHARD_INDEX=0 ./gradlew test
    ```

    Tune the plan with `-PtuistShardMax`, `-PtuistShardMin`, and `-PtuistShardMaxDuration`. Let Tuist derive the shard reference unless the workflow needs `TUIST_SHARD_REFERENCE`.

    Report the before-and-after duration, executed task count, remote cache hits, files changed, and any tasks that remain uncacheable.
    """
  end
end
