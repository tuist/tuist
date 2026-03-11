defmodule Tuist.MCP.Components.Prompts.CompareBuilds do
  @moduledoc """
  Guides you through comparing two build runs to identify performance regressions, cache changes, and build issues. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL.
  """

  use Tuist.MCP.Prompt,
    name: "compare_builds",
    arguments: [
      %{name: "account_handle", description: "The account handle (organization or user)."},
      %{name: "project_handle", description: "The project handle."},
      %{
        name: "base",
        description:
          "Base build: an ID, a Tuist dashboard URL, or a branch name. " <>
            "Defaults to the latest build on the project's default branch when omitted."
      },
      %{
        name: "head",
        description:
          "Head build: an ID, a Tuist dashboard URL, or a branch name. " <>
            "This is the build you want to evaluate. When provided without a base, " <>
            "the base defaults to the latest build on the project's default branch."
      }
    ]

  @impl EMCP.Prompt
  def description,
    do:
      "Guides you through comparing two build runs to identify performance regressions, cache changes, and build issues. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL."

  @impl EMCP.Prompt
  def template(_conn, args) do
    base = Map.get(args, "base")
    head = Map.get(args, "head")
    {account_handle, project_handle} = PromptSupport.resolve_project_handles(args)
    meta = PromptSupport.resolve_project_metadata(account_handle, project_handle)

    %{
      messages: [
        %{role: "user", content: %{type: "text", text: prompt_text(base, head, account_handle, project_handle, meta)}}
      ]
    }
  end

  defp prompt_text(base, head, account_handle, project_handle, meta) do
    default_branch = meta.default_branch
    build_system = meta.build_system
    resolution = resolution_section(base, head, account_handle, project_handle, default_branch, build_system)
    tools_section = tools_section(build_system)
    workflow_section = workflow_section(build_system)

    """
    # Compare Builds

    Use MCP tools to fetch two build runs and compare them to identify regressions and improvements.

    #{tools_section}

    ## Workflow

    #{resolution}

    #{workflow_section}

    ### Summary format

    Produce a structured summary with:
    1. **Overall**: duration change, status change, pass/regress verdict.
    2. **Top regressions**: up to 5 items sorted by absolute time increase.
    3. **Cache changes**: hit-rate delta, notable changes.
    4. **New issues**: new errors and warnings (Xcode only).
    5. **Recommendations**: actionable next steps. Since the developer is likely on the head branch, suggest concrete local fixes.
    """
  end

  defp tools_section(:gradle) do
    """
    ## Available MCP tools

    - **list_projects**: List all accessible projects (includes build_system field).
    - **list_gradle_builds**: List Gradle build runs for a project (supports git_branch filter).
    - **get_gradle_build**: Get detailed metrics for a Gradle build run.
    - **list_gradle_build_tasks**: List Gradle tasks with outcomes and cache status.
    """
  end

  defp tools_section(_xcode_or_unknown) do
    """
    ## Available MCP tools

    - **list_projects**: List all accessible projects (includes build_system field).
    - **list_xcode_builds**: List Xcode build runs for a project (supports git_branch, status, scheme filters).
    - **get_xcode_build**: Get detailed metrics for an Xcode build run (by ID or dashboard URL).
    - **list_xcode_build_targets**: List per-target build and compilation durations.
    - **list_xcode_build_files**: List per-file compilation durations (sorted slowest-first by default).
    - **list_xcode_build_issues**: List warnings and errors.
    - **list_xcode_build_cache_tasks**: List cache hit/miss status per task.
    - **list_xcode_build_cas_outputs**: List CAS upload/download operations.
    """
  end

  defp workflow_section(:gradle) do
    """
    ### 2. Compare top-level metrics

    Compare these fields between the two Gradle builds:
    - **duration**: Total build time. Flag regressions over 10%.
    - **status**: Did either build fail?
    - **tasks_local_hit_count**, **tasks_remote_hit_count**, **tasks_executed_count**: Cache effectiveness changes.

    ### 3. Drill into tasks (if duration regressed)

    Use `list_gradle_build_tasks` for both builds. Compare `duration_ms` and `outcome` per task.
    Identify tasks that changed from `local_hit`/`remote_hit` to `executed` (cache misses).
    Sort by absolute time difference.

    ### 4. Check cache changes

    Compare task-level cache behavior:
    - Tasks that changed from hit to executed (potential cache invalidation).
    - Tasks that changed from executed to hit (improvements).
    - New tasks that appeared in the head build.
    """
  end

  defp workflow_section(_xcode_or_unknown) do
    """
    ### 2. Compare top-level metrics

    Compare these fields between the two Xcode builds:
    - **duration**: Total build time. Flag regressions over 10%.
    - **status**: Did either build fail?
    - **cacheable_tasks_count**, **cacheable_task_local_hits_count**, **cacheable_task_remote_hits_count**: Cache effectiveness changes.
    - **category**: clean vs. incremental (only compare like-for-like).

    ### 3. Drill into targets (if duration regressed)

    Use `list_xcode_build_targets` for both builds. Compare `build_duration` and `compilation_duration` per target.
    Identify which targets regressed the most and sort by absolute time difference.

    ### 4. Drill into files (if a target regressed)

    Use `list_xcode_build_files` filtered by the regressed target. Compare `compilation_duration` per file.
    Identify the slowest files and any new files that appeared in the head build.

    ### 5. Check issues

    Use `list_xcode_build_issues` for both builds. Report:
    - New errors in head that were not in base.
    - New warnings introduced.
    - Issues that were resolved.

    ### 6. Check cache changes

    Use `list_xcode_build_cache_tasks` for both builds. Report:
    - Tasks that changed from hit to miss (potential cache invalidation).
    - Tasks that changed from miss to hit (improvements).
    """
  end

  defp resolution_section(base, head, account_handle, project_handle, default_branch, build_system) do
    branch = default_branch || "main"
    {list_tool, get_tool} = build_tool_names(build_system)

    project_line =
      if account_handle && project_handle,
        do: "Project: `#{account_handle}/#{project_handle}`.\n",
        else: ""

    base_instruction =
      case base do
        nil ->
          "For the **base**, use `#{list_tool}` with `git_branch=#{branch}` and pick the most recent build."

        _ ->
          "For the **base**, use `#{get_tool}` with `build_run_id=#{base}`."
      end

    head_instruction =
      case head do
        nil ->
          "For the **head**, detect the current git branch (e.g., run `git branch --show-current`). " <>
            "If it differs from `#{branch}`, use `#{list_tool}` with that branch and pick the most recent build. " <>
            "If it matches the base branch, ask the user which build to compare."

        _ ->
          "For the **head**, use `#{get_tool}` with `build_run_id=#{head}`."
      end

    """
    ### 1. Resolve builds

    #{project_line}#{base_instruction}
    #{head_instruction}
    """
  end

  defp build_tool_names(:gradle), do: {"list_gradle_builds", "get_gradle_build"}
  defp build_tool_names(_), do: {"list_xcode_builds", "get_xcode_build"}
end
