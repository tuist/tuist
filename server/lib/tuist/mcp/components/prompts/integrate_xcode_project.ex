defmodule Tuist.MCP.Components.Prompts.IntegrateXcodeProject do
  @moduledoc """
  Guides you through integrating Tuist into an Xcode project.
  """

  use Tuist.MCP.Prompt,
    name: "integrate_xcode_project",
    arguments: [
      %{name: "account_handle", description: "The Tuist account or organization handle."},
      %{name: "project_handle", description: "The Tuist project handle."},
      %{
        name: "features",
        description:
          "Optional comma-separated feature list. Supported values: xcode_cache, build_insights, test_insights, test_sharding."
      }
    ]

  @impl EMCP.Prompt
  def description, do: "Guides you through integrating Tuist into an Xcode project."

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
    {project, socket_path} =
      if account_handle && project_handle do
        {"`#{account_handle}/#{project_handle}`", "$HOME/.local/state/tuist/#{account_handle}_#{project_handle}.sock"}
      else
        {"the target Tuist project", "$HOME/.local/state/tuist/your_org_your_project.sock"}
      end

    feature_instruction =
      case features do
        value when is_binary(value) and value != "" ->
          "The user requested these features: `#{value}`. Integrate those features and skip unrelated optional setup."

        _ ->
          "Ask the user which supported Tuist Xcode features they want, or infer the smallest useful set from their request before editing."
      end

    """
    # Integrate Tuist Xcode Project

    Help the user integrate Tuist into an Xcode project for #{project}.

    ## Workflow

    1. Confirm the project handle. If the Tuist organization or project does not exist yet, use `create_organization` and `create_project` with `build_system=xcode`.
    2. Ensure the project has a `Tuist.swift` with `fullHandle` set to the Tuist project.
    3. Determine whether this is a Tuist-generated project, a manually maintained Xcode project, or a workspace, and preserve the user's existing build invocation style.
    4. #{feature_instruction}

    ## Supported integrations

    ### Xcode cache

    Run `tuist setup cache` locally and in CI before any `xcodebuild`, `tuist xcodebuild`, `tuist test`, or `tuist cache warm` invocation. This starts the local cache service that Xcode talks to through a socket.

    For Tuist-generated projects, prefer enabling cache generation in `Tuist.swift`:

    ```swift
    import ProjectDescription

    let tuist = Tuist(
        fullHandle: "your-org/your-project",
        project: .tuist(
            generationOptions: .options(
                enableCaching: true
            )
        )
    )
    ```

    For manually maintained Xcode projects, add these build settings:

    ```text
    COMPILATION_CACHE_ENABLE_CACHING = YES
    COMPILATION_CACHE_REMOTE_SERVICE_PATH = #{socket_path}
    COMPILATION_CACHE_ENABLE_PLUGIN = YES
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
    ```

    Configure upload policy. Prefer CI uploads and local read-only mode when reproducibility matters:

    ```swift
    import ProjectDescription

    let tuist = Tuist(
        fullHandle: "your-org/your-project",
        cache: .cache(
            upload: Environment.isCI
        ),
        project: .tuist(
            generationOptions: .options(
                enableCaching: true
            )
        )
    )
    ```

    Verify by running a clean Xcode build first, then inspect cache behavior through `list_xcode_builds`, `list_xcode_build_cache_tasks`, and `list_xcode_build_cas_outputs`.

    ### Build insights

    Build insights are driven by `tuist inspect build`, usually from a shared scheme post-action. For Xcodebuild-driven CI, use `tuist xcodebuild` when invoking `xcodebuild` actions and include `-resultBundlePath` so Tuist can analyze the build artifacts.

    ```sh
    tuist xcodebuild build \
      -scheme MyScheme \
      -workspace MyWorkspace.xcworkspace \
      -destination 'platform=iOS Simulator,name=iPhone 16' \
      -resultBundlePath .tuist-result-bundles/build.xcresult
    ```

    If the user wants machine metrics, run `tuist setup insights` before building. Verify by running a build, then use `list_xcode_builds`, `get_xcode_build`, `list_xcode_build_targets`, and `list_xcode_build_issues`.

    ### Test insights

    Test insights are driven by `tuist inspect test`, usually from a shared scheme test post-action. Generated projects with auto-generated schemes include the post-action by default unless test insights are disabled.

    Prefer a scheme post-action over running `tuist inspect test` as a standalone command when the project needs accurate scheme attribution. The scheme is part of Tuist's test insight and flakiness context, so running the inspect command from the scheme post-action lets Tuist attribute uploaded results to the scheme that produced them. A standalone `tuist inspect test` command can still upload results when the required result bundle exists, but it may lose that scheme context.

    For manually maintained Xcode schemes, add a test post-action that runs:

    ```sh
    tuist inspect test
    ```

    If the project uses Mise, use Mise's absolute path in the post-action because Xcode does not inherit the shell `PATH`:

    ```sh
    # -C ensures that Mise loads the configuration from the Mise configuration
    # file in the project's root directory.
    $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
    ```

    Ensure the post-action inherits build settings from a target so `$SRCROOT` points at the project root.

    On CI, use `tuist xcodebuild test` or add `-resultBundlePath` to the existing `xcodebuild test` invocation so the result bundle exists for inspection.

    Verify by running a test action first, then inspect uploaded results through `list_test_runs`, `get_test_run`, `list_test_module_runs`, `list_test_suite_runs`, and `list_test_case_runs`.

    ### Test sharding

    Use test sharding when the user wants to distribute Xcode tests across CI runners. Test sharding requires test insights so Tuist can use historical timing data for balancing.

    For manually maintained Xcode projects, create the shard plan with `tuist xcodebuild build-for-testing`:

    ```sh
    tuist xcodebuild build-for-testing \
      -scheme MyScheme \
      -destination 'platform=iOS Simulator,name=iPhone 16' \
      --shard-total 5
    ```

    Then execute each shard with `tuist xcodebuild test` and a shard index:

    ```sh
    TUIST_SHARD_INDEX=0 tuist xcodebuild test \
      -scheme MyScheme \
      -destination 'platform=iOS Simulator,name=iPhone 16'
    ```

    For generated projects, create the shard plan with:

    ```sh
    tuist test --build-only --shard-total 5
    ```

    Then execute each shard with:

    ```sh
    TUIST_SHARD_INDEX=0 tuist test --without-building
    ```

    Tune sharding with `--shard-min`, `--shard-max`, `--shard-total`, `--shard-max-duration`, `--shard-granularity`, `--shard-reference`, and `--shard-archive-path`. Let Tuist derive the shard reference from CI unless the workflow needs `TUIST_SHARD_REFERENCE`.

    ## Verification

    After implementing the selected features, run the smallest relevant Xcode verification:
    - Xcode cache: run a clean build before calling cache-related MCP tools.
    - Build insights: run a build before calling build-related MCP tools.
    - Test insights: run a test action before calling test-related MCP tools.
    - Test sharding: run the shard build phase and one shard execution command.

    Do not remove existing Xcode project settings unless they conflict with the selected Tuist integrations. Keep changes scoped to Tuist configuration, scheme post-actions, cache build settings, and CI bootstrap.
    """
  end
end
