defmodule Tuist.MCP.Components.Prompts.FixFlakyTest do
  @moduledoc """
  Guides you through fixing a flaky test by analyzing failure patterns, identifying the root cause, and applying a targeted correction.
  """

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Response

  schema do
    field :account_handle, :string,
      description: "The account handle (organization or user). Required if project_handle is provided."

    field :project_handle, :string, description: "The project handle. Required if account_handle is provided."

    field :test_case_id, :string,
      description:
        "The test case UUID or identifier (`Module/Suite/TestCase` or `Module/TestCase`) to fix. " <>
          "When using an identifier, provide account_handle and project_handle."
  end

  @impl true
  def get_messages(arguments, frame) do
    account_handle = Map.get(arguments, :account_handle)
    project_handle = Map.get(arguments, :project_handle)
    test_case_id = Map.get(arguments, :test_case_id)

    response =
      Response.user_message(Response.prompt(), %{
        "type" => "text",
        "text" => prompt_text(account_handle, project_handle, test_case_id)
      })

    {:reply, response, frame}
  end

  defp prompt_text(account_handle, project_handle, test_case_id) do
    discovery_section = discovery_section(account_handle, project_handle, test_case_id)

    """
    # Fix Flaky Test

    Use MCP tools to discover flaky behavior, inspect failure details, and guide a targeted fix.

    ## Available MCP tools

    - **list_projects**: List all accessible projects.
    - **list_test_cases**: List test cases for a project (requires account_handle and project_handle; use flaky=true to focus on flaky tests).
    - **get_test_case**: Get detailed metrics for a test case (requires `test_case_id` or `identifier` with `account_handle` and `project_handle`).
      `test_case_id` is the `id` field returned by `list_test_cases`.
    - **get_test_run**: Get detailed metrics for a test run (requires test_run_id).
    - **get_test_case_run**: Get failure details for a specific test case run (requires test_case_run_id).

    ## Workflow

    #{discovery_section}

    ### 2. Get test case metrics

    Use `get_test_case` with the test case ID (`list_test_cases[].id`), or with identifier + account/project handles. Key fields:

    - **reliability_rate**: percentage of successful runs (higher is better)
    - **flakiness_rate**: percentage of runs marked flaky in the last 30 days
    - **total_runs** / **failed_runs**: volume context
    - **last_status**: current state

    ### 3. Correlate with related flaky tests

    Use `list_test_cases` with focused filters such as `module_name`, `suite_name`, `name`, and `flaky=true` to inspect nearby failures in the same area.
    Compare with `get_test_case` metrics to identify whether the issue is isolated or systematic.

    Look for patterns:

    - Does it fail on specific branches?
    - Does it fail only in CI (`is_ci: true`)?
    - Are failures clustered around specific commits?

    ### 4. Get failure details for a run

    Use `get_test_case_run` with a failing run ID. Key fields:

    - **failures[].message**: the assertion or error message
    - **failures[].path**: source file path
    - **failures[].line_number**: exact line of failure
    - **failures[].issue_type**: type of issue
    - **repetitions**: retry behavior (pass/fail sequence)
    - **test_run_id**: the broader test run this execution belongs to

    ### 5. Read and analyze source code

    Open the file at the reported path and line number. Read the full test function and its setup/teardown.

    Common flaky patterns:

    **Timing and async issues:**
    - Missing waits for async operations. Fix: use await, expectations with timeouts, or polling.
    - Race conditions with shared state. Fix: synchronize access or use serial queues.
    - Hardcoded timeouts that are too short on CI. Fix: use condition-based waits.

    **Shared state:**
    - Test pollution from global/static state. Fix: reset state in setUp/tearDown.
    - Singleton contamination. Fix: inject dependencies or reset singletons.
    - File system leftovers. Fix: use temporary directories and clean up.

    **Environment dependencies:**
    - Network calls to real services. Fix: mock network calls.
    - Date/time sensitivity. Fix: inject a clock or freeze time.
    - Hardcoded file system paths. Fix: use relative paths or temp directories.

    **Order dependence:**
    - Implicit ordering between tests. Fix: make each test self-contained.
    - Parallel execution conflicts. Fix: use unique resources per test.

    ### 6. Reproduce the failure before changing code

    Reproduce at least one failure first in your test environment.
    If you cannot reproduce it, do not claim a fix. Instead:

    - document that reproduction failed
    - compare CI context from MCP data (`is_ci`, branch, commit, scheme)
    - explain what additional signal is needed to proceed

    ### 7. Apply the fix

    - Apply the smallest fix that addresses the root cause.
    - Do not refactor unrelated code.
    - Reuse existing test utilities before creating new ones.

    ### 8. Verify

    Run the specific test repeatedly in your test environment until intermittent failures stop appearing.
    Use 50-100 iterations for fast unit tests, and 2-5 iterations for slower integration tests.

    ### Done checklist

    - Identified the root cause of flakiness.
    - Reproduced the flaky failure before applying the fix.
    - Applied a targeted fix.
    - Verified the test passes consistently across repeated runs.
    - Did not introduce new shared state or hidden dependencies.
    - Committed the fix with a descriptive message.
    """
  end

  defp discovery_section(nil, nil, nil) do
    """
    ### 1. Discover flaky tests

    1. Use `list_projects` to find available projects.
    2. Use `list_test_cases` with account_handle and project_handle and set flaky=true.
    3. Pick a flaky test case and use its `id` as `test_case_id` in `get_test_case`.
    """
  end

  defp discovery_section(account_handle, project_handle, nil)
       when is_binary(account_handle) and is_binary(project_handle) do
    """
    ### 1. Discover flaky tests

    1. Use `list_test_cases` with account_handle="#{account_handle}" and project_handle="#{project_handle}" and set flaky=true.
    2. Pick a flaky test case and use its `id` as `test_case_id` in `get_test_case`.
    """
  end

  defp discovery_section(_account_handle, _project_handle, test_case_id) when is_binary(test_case_id) do
    """
    ### 1. Get test case metrics

    Use `get_test_case` with test_case_id="#{test_case_id}".
    """
  end

  defp discovery_section(_, _, _) do
    discovery_section(nil, nil, nil)
  end
end
