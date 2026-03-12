defmodule Tuist.MCP.Components.Prompts.CompareTestRuns do
  @moduledoc """
  Guides you through comparing two test runs to identify regressions, new failures, and flaky tests. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL.
  """

  use Tuist.MCP.Prompt,
    name: "compare_test_runs",
    arguments: [
      %{name: "account_handle", description: "The account handle (organization or user)."},
      %{name: "project_handle", description: "The project handle."},
      %{
        name: "base",
        description:
          "Base test run: an ID, a Tuist dashboard URL, or a branch name. " <>
            "Defaults to the latest test run on the project's default branch when omitted."
      },
      %{
        name: "head",
        description:
          "Head test run: an ID, a Tuist dashboard URL, or a branch name. " <>
            "This is the test run you want to evaluate. When provided without a base, " <>
            "the base defaults to the latest test run on the project's default branch."
      }
    ]

  @impl EMCP.Prompt
  def description,
    do:
      "Guides you through comparing two test runs to identify regressions, new failures, and flaky tests. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL."

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
    # Compare Test Runs

    Use MCP tools to fetch two test runs and compare them to identify new failures, flaky tests, and performance changes.

    ## Available MCP tools

    - **list_projects**: List all accessible projects.
    - **list_test_runs**: List test runs for a project (supports git_branch, status, scheme filters).
    - **get_test_run**: Get detailed metrics for a test run (total/failed/flaky counts, duration).
    - **list_test_module_runs**: List per-module results within a test run.
    - **list_test_suite_runs**: List per-suite results (optionally filtered by module).
    - **list_test_case_runs**: List individual test case runs (supports test_run_id filter).
    - **get_test_case_run**: Get failure details and repetitions for a specific test case run.
    - **list_test_case_run_attachments**: List attachments (screenshots, logs, crash reports) for a test case run. Each attachment includes a temporary download URL.

    ## Workflow

    #{resolution}

    ### 2. Compare top-level metrics

    Compare these fields between the two test runs:
    - **duration**: Total test duration. Flag regressions over 10%.
    - **total_test_count**: Did the test count change?
    - **failed_test_count**: New failures?
    - **flaky_test_count**: New flaky tests?
    - **status**: Did either run fail entirely?

    ### 3. Drill into modules (if failures increased)

    Use `list_test_module_runs` for both runs. Compare `status`, `duration`, and `test_case_count` per module.
    Identify modules that went from passing to failing, or that significantly increased in duration.

    ### 4. Drill into suites (for regressed modules)

    Use `list_test_suite_runs` filtered by the regressed module. Compare individual suite results.

    ### 5. Inspect failing test cases

    Use `list_test_case_runs` with `test_run_id` for the head run to find failures.
    Use `get_test_case_run` to get failure messages, file paths, and line numbers.

    Compare with the base run to identify:
    - **New failures**: tests that passed in base but failed in head.
    - **Fixed tests**: tests that failed in base but passed in head.
    - **Persistent failures**: tests that failed in both runs.

    ### 6. Check for flaky tests

    Look at tests with `is_flaky: true` in the head run. Use `get_test_case_run` to inspect repetitions.
    Report any newly flaky tests that were stable in the base run.

    ### 7. Inspect attachments

    For failing or flaky test case runs, use `list_test_case_run_attachments` to find diagnostic artifacts. Each attachment includes a download URL.

    - **Text attachments** (logs, crash reports, JSON, XML, CSV): download and include relevant excerpts inline.
    - **Image attachments** (screenshots, PNGs, JPGs): present the download URL so the developer can view them. Describe what the image likely shows based on its file name and context.

    ### Summary format

    Produce a structured summary with:
    1. **Overall**: duration change, test count change, pass/fail verdict.
    2. **New failures**: list of tests that newly failed, with failure messages.
    3. **New flaky tests**: tests that became flaky.
    4. **Fixed tests**: tests that were previously failing and now pass.
    5. **Duration regressions**: modules or suites with notable slowdowns.
    6. **Recommendations**: actionable next steps. Since the developer is likely on the head branch, suggest concrete local fixes (e.g., "investigate ModuleX failures at path:line", "fix flaky test Y by addressing shared state").
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
          "For the **base**, use `list_test_runs` with `git_branch=#{branch}` and pick the most recent run."

        _ ->
          "For the **base**, use `get_test_run` with `test_run_id=#{base}`."
      end

    head_instruction =
      case head do
        nil ->
          "For the **head**, detect the current git branch (e.g., run `git branch --show-current`). " <>
            "If it differs from `#{branch}`, use `list_test_runs` with that branch and pick the most recent run. " <>
            "If it matches the base branch, ask the user which test run to compare."

        _ ->
          "For the **head**, use `get_test_run` with `test_run_id=#{head}`."
      end

    """
    ### 1. Resolve test runs

    #{project_line}#{base_instruction}
    #{head_instruction}
    """
  end
end
