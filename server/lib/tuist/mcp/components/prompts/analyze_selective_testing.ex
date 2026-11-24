defmodule Tuist.MCP.Components.Prompts.AnalyzeSelectiveTesting do
  @moduledoc """
  Guides you through analyzing selective testing effectiveness for a test run, identifying which targets were skipped or ran, and diagnosing regressions. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Prompt,
    name: "analyze_selective_testing",
    arguments: [
      %{name: "account_handle", description: "The account handle (organization or user)."},
      %{name: "project_handle", description: "The project handle."},
      %{
        name: "test_run_id",
        description:
          "A test run ID or Tuist dashboard URL. " <>
            "When omitted, the latest CI test run on the project's default branch is used."
      },
      %{
        name: "base_test_run_id",
        description:
          "Optional base test run ID for comparison. " <>
            "When provided, the analysis compares selective testing behavior between base and head."
      }
    ]

  @impl EMCP.Prompt
  def description,
    do:
      "Guides you through analyzing selective testing effectiveness for a test run, identifying which targets were skipped or ran, and diagnosing regressions. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  @impl EMCP.Prompt
  def template(_conn, args) do
    test_run_id = Map.get(args, "test_run_id")
    base_test_run_id = Map.get(args, "base_test_run_id")
    {account_handle, project_handle} = PromptSupport.resolve_project_handles(args)
    default_branch = PromptSupport.resolve_default_branch(account_handle, project_handle)

    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: prompt_text(test_run_id, base_test_run_id, account_handle, project_handle, default_branch)
          }
        }
      ]
    }
  end

  defp prompt_text(test_run_id, base_test_run_id, account_handle, project_handle, default_branch) do
    resolution = resolution_section(test_run_id, base_test_run_id, account_handle, project_handle, default_branch)

    """
    # Analyze Selective Testing

    Use MCP tools to analyze selective testing effectiveness for Xcode test runs, identify which test targets were skipped or ran, and diagnose regressions in test selection.

    ## Available MCP tools

    - **list_projects**: List all accessible projects.
    - **list_test_runs**: List test runs for a project, each with its `selective_testing_strategy` (supports git_branch, status, scheme and `selective_testing` (`coverage` or `module_hash`) filters, and richer query expressions such as `-git_branch~"gh-readonly-queue"`).
    - **get_test_run**: Get detailed test run info including its `selective_testing` summary: the `strategy` (`coverage` or `module_hash`), the `baseline_sha` coverage compared against, and the `requested`, `selected` and `skipped` test counts.
    - **list_xcode_test_targets**: List per-target selective testing hit/miss status and hash for a test run. Supports `hit_status` filter (miss, local, remote).
    - **list_selective_testing_tests**: For a run whose strategy is `coverage`, list every test its selection decided, with `decision` (selected or skipped), `reason`, the changed file that selected it (`matched_path`) and its outcome in the run. Supports `decision`, `reason` and `search` filters.
    - **list_selective_testing_changed_files**: For a run whose strategy is `coverage`, list the files that changed since its baseline, with how many tests each selected and whether it's a tracked file.

    ## Workflow

    #{resolution}

    ### 2. Assess overall selective testing effectiveness

    Read `selective_testing.strategy` from `get_test_run`. When it's `coverage`, the run used coverage-based test selection: follow "Coverage-based selection" below instead of steps 3 and 4.

    Otherwise, from `selective_testing` the share of tests skipped is `skipped / requested * 100`. From `list_xcode_test_targets`, compute:
    - **Effectiveness**: `(local_hits + remote_hits) / targets * 100`
    - **Targets tested**: targets that had status `miss` (i.e. actually ran)
    - **Targets skipped**: targets with `local` or `remote` hits (skipped because unchanged)

    Effectiveness varies by project and workflow. Some teams enable selective testing on all branches, while others only use it on feature branches. A 0% effectiveness means all tests ran — this is expected for the very first run or after a full cache invalidation.

    ### 3. Drill into per-target details

    Use `list_xcode_test_targets` to see each target's status:
    - Filter by `hit_status=miss` to see targets that ran (were selected for testing)
    - Filter by `hit_status=local` or `hit_status=remote` to see targets that were skipped

    For each target, the response includes:
    - **name**: The test target name
    - **hit_status**: `miss` (ran), `local` (skipped, hash matched locally), or `remote` (skipped, hash matched on server)
    - **hash**: The selective testing hash for this target

    ### 4. Compare with a baseline (if base provided)

    If a base test run is available, use `list_xcode_test_targets` for both runs:
    - Match targets by `name` between base and head
    - Identify targets that changed from `local`/`remote` (skipped) to `miss` (ran) — these were invalidated
    - Identify targets that changed from `miss` to `local`/`remote` — these are now cached
    - Compare `hash` values: if a target's hash changed between runs, its dependencies or sources changed

    ### 5. Diagnose selective testing regressions

    If effectiveness dropped significantly (e.g., from 60% to <20%):

    **Common causes:**
    - **Hash invalidation cascade**: A widely-depended-on target changed, invalidating all dependents
    - **CI environment change**: Different Xcode version, macOS version, or build settings can change hashes. Use `get_test_run` to compare `xcode_version` and `macos_version` between a known-good run and the regressed run — if they differ, that is the likely cause.
    - **Project graph or dependency change**: Adding/removing targets, changing dependency versions, or modifying build configurations and project manifests
    - **Cold cache**: First run on a new branch or after cache expiration

    Note: Tuist CLI version upgrades rarely cause hash invalidation — the hash version is not updated on every release.

    **Diagnosis steps:**
    1. Check how many targets have `miss` status — if nearly all targets are misses, the cache is fully cold
    2. Compare `xcode_version` and `macos_version` between the regressed run and a known-good run using `get_test_run` — environment differences are a common cause of full invalidation
    3. Compare hashes between runs — if all hashes differ, suspect a global change (environment, project settings)
    4. If only some targets changed, trace the dependency chain to find the root cause target
    5. Check git history around the regression date for dependency or configuration changes

    ### Coverage-based selection

    For a run whose strategy is `coverage`, `selective_testing` gives the effectiveness: `skipped / requested * 100`.

    1. Use `list_selective_testing_tests` with `decision=selected` and group the tests by `reason`. Rules such as `impacted` (a changed file is in the test's coverage) or `test_file_changed` kept a test on evidence; `no_evidence` means the baseline had no coverage for it. Any other reason, such as `tracked_file_changed` or `no_baseline`, is a fallback: coverage couldn't decide, so the test ran anyway.
    2. Use `list_selective_testing_changed_files` to see which changes drove the selection: the files that selected the most tests come first, and a `tracked` file explains a fallback.
    3. If a base run is provided, compare the reasons and the changed files between the two runs: a jump in selected tests usually traces to a widely covered file or a tracked file that changed.

    ### Summary format

    Produce a structured summary with:
    1. **Overall**: effectiveness percentage, total targets, hits (local + remote), misses, verdict (healthy/moderate/low/cold)
    2. **Target breakdown**: group targets by hit status, sorted by name
    3. **Regression analysis** (if comparing): which targets changed status and likely cause
    4. **Recommendations**: actionable next steps to restore effectiveness
    """
  end

  defp resolution_section(test_run_id, base_test_run_id, account_handle, project_handle, default_branch) do
    branch = default_branch || "main"

    project_line =
      if account_handle && project_handle,
        do: "Project: `#{account_handle}/#{project_handle}`.\n",
        else: ""

    head_instruction =
      case test_run_id do
        nil ->
          "For the **head** test run, use `list_test_runs` with the current git branch and pick the most recent CI test run. " <>
            "If no branch is specified, detect it with `git branch --show-current`."

        _ ->
          "For the **head** test run, use `get_test_run` with `test_run_id=#{test_run_id}`."
      end

    base_instruction =
      case base_test_run_id do
        nil ->
          "For the **base** (optional), use `list_test_runs` with `git_branch=#{branch}` to find a recent test run with good selective testing effectiveness for comparison."

        _ ->
          "For the **base**, use `get_test_run` with `test_run_id=#{base_test_run_id}`."
      end

    """
    ### 1. Resolve test runs

    #{project_line}#{head_instruction}
    #{base_instruction}
    """
  end
end
