defmodule Tuist.MCP.Components.Prompts.CompareCacheRuns do
  @moduledoc """
  Guides you through comparing two cache runs to identify cache effectiveness changes and target-level regressions. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL.
  """

  use Tuist.MCP.Prompt,
    name: "compare_cache_runs",
    arguments: [
      %{name: "account_handle", description: "The account handle (organization or user)."},
      %{name: "project_handle", description: "The project handle."},
      %{
        name: "base",
        description:
          "Base cache run: an ID, a Tuist dashboard URL, or a branch name. " <>
            "Defaults to the latest cache run on the project's default branch when omitted."
      },
      %{
        name: "head",
        description:
          "Head cache run: an ID, a Tuist dashboard URL, or a branch name. " <>
            "This is the cache run you want to evaluate. When provided without a base, " <>
            "the base defaults to the latest cache run on the project's default branch."
      }
    ]

  @impl EMCP.Prompt
  def description,
    do:
      "Guides you through comparing two cache runs to identify cache effectiveness changes and target-level regressions. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL."

  @impl EMCP.Prompt
  def template(_conn, args) do
    base = Map.get(args, "base")
    head = Map.get(args, "head")
    {account_handle, project_handle} = PromptSupport.resolve_project_handles(args)
    default_branch = PromptSupport.resolve_default_branch(account_handle, project_handle)

    %{
      messages: [
        %{
          role: "user",
          content: %{type: "text", text: prompt_text(base, head, account_handle, project_handle, default_branch)}
        }
      ]
    }
  end

  defp prompt_text(base, head, account_handle, project_handle, default_branch) do
    resolution = resolution_section(base, head, account_handle, project_handle, default_branch)

    """
    # Compare Cache Runs

    Use MCP tools to fetch two cache runs and compare their effectiveness and target-level cache behavior.

    ## Available MCP tools

    - **list_projects**: List all accessible projects.
    - **list_cache_runs**: List cache runs for a project (supports git_branch filter).
    - **get_cache_run**: Get detailed cache run info (by ID or dashboard URL).
    - **list_xcode_module_cache_targets**: List per-target module cache hit/miss status and subhashes.

    ## Workflow

    #{resolution}

    ### 2. Compare top-level metrics

    Compare these fields between the two cache runs:
    - **duration**: Total cache run time. Flag regressions over 10%.
    - **status**: Did either cache run fail?
    - **cacheable_targets**: Total number of cacheable targets.
    - **local_cache_target_hits** / **remote_cache_target_hits**: Cache hit counts.
    - Compute and compare overall cache hit rates.

    ### 3. Drill into module cache targets

    Use `list_xcode_module_cache_targets` for both cache runs. For each target:
    - Match targets by `name` between base and head.
    - Compare `cache_status` (miss, local, remote).
    - Identify targets that changed from hit to miss (cache invalidation).
    - Identify targets that changed from miss to hit (improvements).
    - Compare `subhashes` to identify which component changed and caused a cache miss.

    ### 4. Analyze cache invalidation and find the root cause

    For targets that went from hit to miss, compare their `subhashes` (`sources`, `resources`, `dependencies`, `target_settings`, `project_settings`, `deployment_target`, `info_plist`, `entitlements`, `headers`, `copy_files`, `core_data_models`, `target_scripts`, `buildable_folders`, `external`).

    **Identify the root cause target.** When many targets are invalidated, it is usually because one target changed and its dependents were invalidated through the `dependencies` subhash cascading down. To find the root cause:
    - Look for the target(s) where a subhash **other than** `dependencies` changed (e.g., `sources`, `target_settings`, `resources`). That is the target where the actual change happened.
    - Targets where **only** the `dependencies` subhash changed were invalidated because they depend (directly or transitively) on the root cause target.
    - Use target names to infer the dependency topology. For example, a target named `FeatureLogin` likely depends on `Core` or `Networking`. Leaf/feature targets depend on shared/core targets. Work from the bottom of the graph upward.
    - If multiple non-dependency subhashes changed across different targets, there may be multiple independent root causes.

    ### Summary format

    Produce a structured summary with:
    1. **Overall**: duration change, cache hit rate delta, verdict (improved/regressed/stable).
    2. **Root cause**: the target(s) and specific subhash(es) that triggered the cascade. Explain what likely changed (e.g., "sources changed in Core, which invalidated 12 dependent targets through the dependencies hash").
    3. **Cache regressions**: targets that went from hit to miss, grouped by root cause.
    4. **Cache improvements**: targets that went from miss to hit.
    5. **Recommendations**: actionable next steps. Since the developer is likely on the head branch, suggest concrete local fixes (e.g., "the source change in Core invalidated 12 targets -- consider whether that change is necessary, or if it can be scoped to avoid touching Core's public interface").
    """
  end

  defp resolution_section(base, head, account_handle, project_handle, default_branch) do
    branch = default_branch || "main"

    project_line =
      if account_handle && project_handle,
        do: "Project: `#{account_handle}/#{project_handle}`.\n",
        else: ""

    base_instruction =
      case base do
        nil ->
          "For the **base**, use `list_cache_runs` with `git_branch=#{branch}` and pick the most recent cache run."

        _ ->
          "For the **base**, use `get_cache_run` with `cache_run_id=#{base}`."
      end

    head_instruction =
      case head do
        nil ->
          "For the **head**, detect the current git branch (e.g., run `git branch --show-current`). " <>
            "If it differs from `#{branch}`, use `list_cache_runs` with that branch and pick the most recent cache run. " <>
            "If it matches the base branch, ask the user which cache run to compare."

        _ ->
          "For the **head**, use `get_cache_run` with `cache_run_id=#{head}`."
      end

    """
    ### 1. Resolve cache runs

    #{project_line}#{base_instruction}
    #{head_instruction}
    """
  end
end
