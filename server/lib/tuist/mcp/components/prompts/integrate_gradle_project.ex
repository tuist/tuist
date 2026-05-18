defmodule Tuist.MCP.Components.Prompts.IntegrateGradleProject do
  @moduledoc """
  Guides you through integrating Tuist into an existing Gradle project.
  """

  use Tuist.MCP.Prompt,
    name: "integrate_gradle_project",
    arguments: [
      %{name: "account_handle", description: "The Tuist account or organization handle."},
      %{name: "project_handle", description: "The Tuist project handle."},
      %{
        name: "features",
        description:
          "Optional comma-separated feature list. Supported values: remote_cache, build_insights, test_insights, flaky_tests, test_sharding."
      }
    ]

  @impl EMCP.Prompt
  def description, do: "Guides you through integrating Tuist into an existing Gradle project."

  @impl EMCP.Prompt
  def template(_conn, args) do
    account_handle = Map.get(args, "account_handle")
    project_handle = Map.get(args, "project_handle")
    features = Map.get(args, "features")

    %{
      messages: [
        Tuist.MCP.Prompt.message(prompt_text(account_handle, project_handle, features))
      ]
    }
  end

  defp prompt_text(account_handle, project_handle, features) do
    project =
      if account_handle && project_handle,
        do: "`#{account_handle}/#{project_handle}`",
        else: "the target Tuist project"

    feature_instruction =
      case features do
        value when is_binary(value) and value != "" ->
          "The user requested these features: `#{value}`. Integrate those features and skip unrelated optional setup."

        _ ->
          "Ask the user which supported Tuist Gradle features they want, or infer the smallest useful set from their request before editing."
      end

    """
    # Integrate Tuist Gradle Project

    Help the user integrate Tuist into an existing Gradle project for #{project}.

    ## Workflow

    1. Confirm the project handle. If the Tuist organization or project does not exist yet, use `create_organization` and `create_project` with `build_system=gradle`.
    2. Install the Tuist Gradle plugin in the Gradle project following the repository's existing plugin-management style.
    3. Configure the Tuist plugin with the project full handle, preferably through `tuist.toml` so the CLI and Gradle plugin share the same project identity.
    4. #{feature_instruction}

    ## Supported integrations

    ### Remote build cache

    Enable Gradle's build cache in `gradle.properties`:

    ```properties
    org.gradle.caching=true
    ```

    Configure remote cache uploads. Prefer local read-only cache usage and CI uploads:

    ```kotlin
    tuist {
        buildCache {
            push = System.getenv("CI") != null
        }
    }
    ```

    On CI, authenticate with a Tuist token before running Gradle, and disable the local Gradle build cache on CI:

    ```kotlin
    buildCache {
        local {
            isEnabled = System.getenv("CI") == null
        }
    }
    ```

    Verify task cache behavior by running a Gradle build first, then use `list_gradle_builds` to find the uploaded build and `list_gradle_build_tasks` to inspect task cache outcomes.

    ### Build insights

    Build insights are available once the Tuist Gradle plugin is applied. Use `uploadInBackground` when the user wants explicit upload behavior:

    ```kotlin
    tuist {
        uploadInBackground = false
    }
    ```

    The default behavior uploads in the background locally and in the foreground on CI.

    ### Test insights

    Test insights are collected automatically from Gradle `Test` tasks once the Tuist Gradle plugin is applied. No additional configuration is needed beyond plugin setup unless the user wants to tune `uploadInBackground`.

    ### Flaky tests and quarantine

    Tuist detects flaky tests from retries and cross-run history. If the project does not already retry tests, suggest adding the Gradle Test Retry plugin:

    ```kotlin
    plugins {
        id("org.gradle.test-retry") version "1.6.2"
    }

    tasks.test {
        retry {
            maxRetries = 3
            maxFailures = 5
            failOnPassedAfterRetry = false
        }
    }
    ```

    Quarantine is enabled automatically on CI and disabled locally. Configure it explicitly only when requested:

    ```kotlin
    tuist {
        testQuarantine {
            enabled = true
        }
    }
    ```

    ### Test sharding

    Use test sharding when the user wants to distribute Gradle tests across CI runners. Add a CI build phase that prepares shard plans:

    ```sh
    ./gradlew tuistPrepareTestShards -PtuistShardMax=5
    ```

    Then run each test shard with `TUIST_SHARD_INDEX` set:

    ```sh
    TUIST_SHARD_INDEX=0 ./gradlew test
    ```

    Tune sharding with `-PtuistShardMax`, `-PtuistShardMin`, and `-PtuistShardMaxDuration`. Let Tuist derive the shard reference from CI unless the workflow needs `TUIST_SHARD_REFERENCE`.

    ## Verification

    After implementing the selected features, run the smallest relevant Gradle verification:
    - Plugin setup or build insights: run a normal Gradle build.
    - Remote cache: run a clean build twice before calling `list_gradle_builds` and `list_gradle_build_tasks` to inspect cache task behavior.
    - Test insights, flaky tests, or quarantine: run the relevant `Test` task.
    - Test sharding: run `tuistPrepareTestShards` and one shard execution command.

    Keep the implementation aligned with the user's Gradle DSL (`settings.gradle`, `settings.gradle.kts`, `build.gradle`, or `build.gradle.kts`) and avoid rewriting unrelated build logic.
    """
  end
end
