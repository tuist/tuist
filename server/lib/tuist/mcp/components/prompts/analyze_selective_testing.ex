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
    - **list_test_runs**: List test runs for a project (supports git_branch, status, scheme filters).
    - **get_test_run**: Get detailed test run info including `xcode_selective_testing_targets`, `xcode_selective_testing_local_hits`, and `xcode_selective_testing_remote_hits`.
    - **list_xcode_selective_testing_targets**: List per-target selective testing hit/miss status and hash for a test run. Supports `hit_status` filter (miss, local, remote).

    ## Workflow

    #{resolution}

    ### 2. Assess overall selective testing effectiveness

    From `get_test_run`, compute:
    - **Effectiveness**: `(local_hits + remote_hits) / targets * 100`
    - **Targets tested**: targets that had status `miss` (i.e. actually ran)
    - **Targets skipped**: targets with `local` or `remote` hits (skipped because unchanged)

    A healthy project typically has 40-80% effectiveness on feature branches. The `develop`/`main` branch baseline run will have 0% (all tests run to establish hashes).

    ### 3. Drill into per-target details

    Use `list_xcode_selective_testing_targets` to see each target's status:
    - Filter by `hit_status=miss` to see targets that ran (were selected for testing)
    - Filter by `hit_status=local` or `hit_status=remote` to see targets that were skipped

    For each target, the response includes:
    - **name**: The test target name
    - **hit_status**: `miss` (ran), `local` (skipped, hash matched locally), or `remote` (skipped, hash matched on server)
    - **hash**: The selective testing hash for this target

    ### 4. Compare with a baseline (if base provided)

    If a base test run is available, use `list_xcode_selective_testing_targets` for both runs:
    - Match targets by `name` between base and head
    - Identify targets that changed from `local`/`remote` (skipped) to `miss` (ran) — these were invalidated
    - Identify targets that changed from `miss` to `local`/`remote` — these are now cached
    - Compare `hash` values: if a target's hash changed between runs, its dependencies or sources changed

    ### 5. Diagnose selective testing regressions

    If effectiveness dropped significantly (e.g., from 60% to <20%):

    **Common causes:**
    - **Hash invalidation cascade**: A widely-depended-on target changed, invalidating all dependents
    - **Tuist version upgrade**: A new CLI version may compute hashes differently, invalidating the entire cache
    - **CI environment change**: Different Xcode version, macOS version, or build settings can change hashes
    - **Project structure change**: Adding/removing targets, changing dependencies, or modifying build configurations
    - **Cold cache**: First run on a new branch or after cache expiration

    **Diagnosis steps:**
    1. Check how many targets have `miss` status — if nearly all targets are misses, the cache is fully cold
    2. Compare hashes between a known-good run and the regression run — if all hashes differ, suspect a global change (CLI version, Xcode version, environment)
    3. If only some targets changed, trace the dependency chain to find the root cause target
    4. Check git history around the regression date for dependency or configuration changes

    ### Summary format

    Produce a structured summary with:
    1. **Overall**: effectiveness percentage, total targets, hits (local + remote), misses, verdict (healthy/degraded/broken)
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
