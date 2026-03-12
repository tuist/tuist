defmodule Tuist.MCP.Components.Prompts.CompareTestCase do
  @moduledoc """
  Guides you through comparing a test case's behavior across two branches or time periods. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}. They are not needed if test_case_id is a dashboard URL.
  """

  use Tuist.MCP.Prompt,
    name: "compare_test_case",
    arguments: [
      %{name: "account_handle", description: "The account handle (organization or user)."},
      %{name: "project_handle", description: "The project handle."},
      %{name: "test_case_id", description: "The test case ID or a Tuist dashboard URL."},
      %{
        name: "base_branch",
        description: "The base branch to compare against (defaults to the project's default branch)."
      },
      %{name: "head_branch", description: "The head branch to evaluate."}
    ]

  @impl EMCP.Prompt
  def description,
    do:
      "Guides you through comparing a test case's behavior across two branches or time periods. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}. They are not needed if test_case_id is a dashboard URL."

  @impl EMCP.Prompt
  def template(_conn, args) do
    test_case_id = Map.get(args, "test_case_id")
    {account_handle, project_handle} = PromptSupport.resolve_project_handles(args)
    default_branch = PromptSupport.resolve_default_branch(account_handle, project_handle)
    base_branch = Map.get(args, "base_branch") || default_branch || "main"
    head_branch = Map.get(args, "head_branch")

    %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: prompt_text(test_case_id, base_branch, head_branch, account_handle, project_handle)
          }
        }
      ]
    }
  end

  defp prompt_text(test_case_id, base_branch, head_branch, account_handle, project_handle) do
    resolution = resolution_section(test_case_id, account_handle, project_handle)

    """
    # Compare Test Case

    Use MCP tools to analyze a test case's behavior across branches and identify regressions or improvements.

    ## Available MCP tools

    - **get_test_case**: Get test case metrics (reliability, flakiness, avg duration).
    - **list_test_case_runs**: List runs for a test case (supports filtering by test_run_id).
    - **get_test_case_run**: Get failure details, repetitions for a specific run.
    - **list_test_case_run_attachments**: List attachments (screenshots, logs, crash reports) for a test case run. Each attachment includes a temporary download URL.
    - **list_test_runs**: List test runs (supports git_branch filter).

    ## Workflow

    #{resolution}

    ### 2. Get test case metrics

    Use `get_test_case` to understand the overall health:
    - **reliability_rate**: success rate percentage.
    - **flakiness_rate**: flaky run percentage in last 30 days.
    - **total_runs** / **failed_runs**: volume context.

    ### 3. Compare across branches

    Base branch: `#{base_branch}`
    #{if head_branch, do: "Head branch: `#{head_branch}`", else: "Head branch: detect the current git branch (e.g., run `git branch --show-current`). If it matches the base branch, ask the user which branch to compare."}

    For each branch:
    1. Use `list_test_runs` with the branch name to find recent test runs.
    2. Use `list_test_case_runs` filtered by `test_run_id` to find runs of this test case.
    3. Compare:
       - **Pass/fail status**: Is it failing on head but passing on base?
       - **Duration**: Is it slower on head?
       - **Flakiness**: Is it flaky on head but stable on base?

    ### 4. Inspect failures

    If the test case fails on the head branch:
    1. Use `get_test_case_run` with a failing run ID.
    2. Examine `failures[].message`, `failures[].path`, `failures[].line_number`.
    3. Check `repetitions` to see if it's intermittent.

    ### 5. Inspect attachments

    For failing runs, use `list_test_case_run_attachments` to find diagnostic artifacts. Each attachment includes a download URL.

    - **Text attachments** (logs, crash reports, JSON, XML, CSV): download and include relevant excerpts inline.
    - **Image attachments** (screenshots, PNGs, JPGs): present the download URL so the developer can view them.

    ### 6. Identify root cause

    Based on the comparison:
    - If newly failing: look at commits between the two branches.
    - If newly flaky: look for timing, async, or shared-state issues.
    - If duration regressed: look for added test setup or slow assertions.

    ### Summary format

    Produce a structured summary with:
    1. **Test case**: name, module, suite.
    2. **Base branch behavior**: pass rate, avg duration, flakiness.
    3. **Head branch behavior**: pass rate, avg duration, flakiness.
    4. **Verdict**: regressed / improved / stable.
    5. **Root cause hypothesis**: what likely changed.
    6. **Recommendations**: fix steps or further investigation needed. Since the developer is likely on the head branch, suggest concrete local fixes with file paths and line numbers when available.
    """
  end

  defp resolution_section(nil, _account_handle, _project_handle) do
    """
    ### 1. Resolve the test case

    Ask the user for the test case to compare, or use `list_test_cases` with `flaky=true` to find candidates.
    """
  end

  defp resolution_section(test_case_id, _account_handle, _project_handle) when is_binary(test_case_id) do
    """
    ### 1. Resolve the test case

    Use `get_test_case` with `test_case_id=#{test_case_id}` to fetch the test case details.
    """
  end

  defp resolution_section(_, _, _) do
    resolution_section(nil, nil, nil)
  end
end
