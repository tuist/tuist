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
    - **list_gradle_build_steps**: Compare timed tasks, configuration and transforms with search and overlap filters.
    - **get_gradle_build_step**: Inspect recorded metadata by opaque step ID; per-step logs are unavailable.
    """
  end

  defp tools_section(:bazel) do
    """
    ## Available MCP tools

    - **list_bazel_invocations** and **get_bazel_invocation**: Resolve completed invocations and compare their metrics.
    - **list_bazel_build_steps** and **get_bazel_build_step**: Inspect retained action intervals with search and overlap filters.
    - **list_bazel_invocation_logs** and **get_bazel_invocation_log**: Inspect available invocation-level output.
    All Bazel tools require account_handle and project_handle. Detail tools use invocation_id.
    """
  end

  defp tools_section(:cargo) do
    """
    ## Available MCP tools

    - **list_cargo_builds**: List Cargo builds newest first, with git_branch, command and is_ci filters and pagination.
    - **get_cargo_build**: Get a Cargo build, aggregate cache counters and up to 500 recorded compiler jobs with diagnostics using build_id.
    Both tools require account_handle and project_handle: Cargo build IDs are project-scoped.
    Cargo timeline tools are not available yet.
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
    - **list_xcode_build_steps**: List recorded operations with timings and outcomes; filter by target or search and paginate, slowest first by default.
    - **get_xcode_build_step**: Inspect a step's recorded log using its build ID and decimal string step ID.
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
    Sort by absolute time difference. Use `list_gradle_build_steps` to inspect overlapping work and configuration or transform costs.
    Honor `time_origin`: older reports start at the first recording. Match operations by identity, never by their build-scoped step IDs.

    ### 4. Check cache changes

    Compare task-level cache behavior:
    - Tasks that changed from hit to executed (potential cache invalidation).
    - Tasks that changed from executed to hit (improvements).
    - New tasks that appeared in the head build.
    """
  end

  defp workflow_section(:bazel) do
    """
    ### 2. Compare invocation metrics

    Compare duration_ms, status, actions_executed, critical_path and cache totals.

    ### 3. Inspect recorded steps

    Use `list_bazel_build_steps` to find slow, failed, or overlapping intervals. Honor the response's `coverage`:
    `trace_profile` includes all recorded profile intervals; `retained_action_spans` is limited to up to 32 actions plus setup.
    Absent intervals in the retained summary do not imply absent work.
    Compare descriptions, targets, and categories, never step IDs across invocations.

    ### 4. Check available output

    Use `get_bazel_build_step` to inspect a step's outcome and recorded action log when available.
    Use invocation log tools for broader failure output. Missing diagnostics or unknown outcomes do not imply success.
    """
  end

  defp workflow_section(:cargo) do
    """
    ### 2. Compare like-for-like builds

    Compare **command**, **rust_version** and environment (**is_ci**, **ci_provider** and recorded **custom_metadata**).
    Call out differences before attributing changes to code or caching; missing environment values are unknown.
    Compare **duration_ms** as measured elapsed build duration and **status** for success or failure.
    Flag duration regressions over 10% only when the base duration is positive.

    ### 3. Compare aggregate cache reuse and transfer

    Use `get_cargo_build` for both builds and compare the **cache** object:
    - **hits**, **task_misses**, **hit_rate**: aggregate task reuse. task_misses includes misses, unconsulted tasks and verifications.
    - **misses**, **unconsulted**, **verifications**, **divergences**: explain changes in reuse and verification work.
    - **prefetched_actions**, **downloaded_bytes**, **uploaded_bytes**, **remote_failures**, **background_upload_failures**: transfer and reliability changes.
    - **prefetch_duration_ns**, **materialization_duration_ns**, **remote_action_lookup_duration_ns**, **remote_blob_transfer_duration_ns**, **upload_drain_duration_ns**: aggregate cache phase costs, not a sequential timeline.

    **estimated_compiler_duration_avoided_ns** is estimated avoided compiler work, not elapsed savings.
    Do not subtract it from duration_ms or sum cache phase counters to infer elapsed savings.
    A null cache object or hit_rate and any missing values are unavailable, not zero; preserve explicitly measured zero values.
    For recorded task/CAS evidence, request **include_cache_inspection: true** only when needed (up to 4 MB).
    A null **cache_inspection** is unavailable; respect its **truncated** flag and never infer task-hit origin from transfers.

    ### 4. Report evidence and limits

    Compare returned **compilations** by name, source and kind, not their build-scoped IDs. Each is one rustc job,
    not per-file timing; multiple jobs can belong to one crate and overlap. Read their recorded diagnostics.
    Respect **compilations_truncated**: missing jobs may be omitted, already fresh or restored, not necessarily removed.
    Without a Cargo timeline, do not infer a critical path or sum job durations into elapsed time.
    Do not invent task-level cache transitions. In the summary, mark unsupported breakdowns unavailable
    and report hit-rate deltas only when both rates are available. Recommend a controlled rerun with matching
    command, Rust version and environment when the builds are not comparable.
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

    For individual compiler, linker, or script operations, use `list_xcode_build_steps` filtered by the affected target.
    Inspect relevant output with `get_xcode_build_step`. Step IDs are scoped to each build; compare titles and targets,
    not IDs. Respect `availability` and `log_truncated`: missing or expired records are not evidence that work did not run.

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

  defp resolution_section(base, head, account_handle, project_handle, default_branch, :bazel) do
    """
    ### 1. Resolve invocations

    Project: `#{account_handle}/#{project_handle}`. Base: #{base || "latest invocation on #{default_branch || "main"}"}.
    Head: #{head || "latest invocation on the current branch"}.
    Resolve IDs or dashboard URLs using `get_bazel_invocation` with invocation_id.
    For branches, paginate `list_bazel_invocations` and match git_branch locally; it has no branch filter.
    If the intended invocation cannot be identified, ask which invocation to compare.
    """
  end

  defp resolution_section(base, head, account_handle, project_handle, default_branch, :cargo) do
    """
    ### 1. Resolve builds

    Project: `#{account_handle}/#{project_handle}`. Base: #{base || "latest build on #{default_branch || "main"}"}.
    Head: #{head || "latest build on the current branch"}.
    Pass account_handle and project_handle to every Cargo tool call.
    For IDs, use `get_cargo_build` with build_id, not build_run_id. For dashboard URLs, extract the build ID first.
    For branches, use `list_cargo_builds` with git_branch and pick the most recent matching build.
    If head is omitted, detect the current git branch (e.g., run `git branch --show-current`).
    If it matches the base branch or the intended build cannot be identified, ask which build to compare.
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
