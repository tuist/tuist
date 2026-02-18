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

    field :test_case_id, :string, description: "The UUID of a specific flaky test case to fix."
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

    Follow the same workflow as the `fix-flaky-tests` skill. Use MCP tools first, and use CLI fallback commands when MCP data is not enough.

    ## Available MCP tools

    - **list_projects**: List all accessible projects.
    - **list_test_cases**: List test cases for a project (requires account_handle and project_handle; use flaky=true to focus on flaky tests).
    - **get_test_case**: Get detailed metrics for a test case (requires test_case_id).
    - **get_test_run**: Get aggregate metrics and crash summaries for a test run (requires test_run_id).
    - **get_test_case_run**: Get failure details for a specific test case run (requires test_case_run_id).

    ## Workflow

    #{discovery_section}

    ### 2. Get test case metrics

    Use `get_test_case` with the test case ID. Key fields:

    - **reliability_rate**: percentage of successful runs (higher is better)
    - **flakiness_rate**: percentage of runs marked flaky in the last 30 days
    - **total_runs** / **failed_runs**: volume context
    - **last_status**: current state

    ### 3. Inspect flaky and full run history

    If you need to enumerate run history (flaky-only or full history), use CLI fallback:

    ```bash
    tuist test case run list Module/Suite/TestCase --flaky --json
    tuist test case run list Module/Suite/TestCase --json --page-size 20
    ```

    Identifier format is `Module/Suite/TestCase` (or `Module/TestCase` when no suite).

    Look for patterns:

    - Does it fail on specific branches?
    - Does it fail only on CI (`is_ci: true`) or also locally?
    - Are failures clustered around specific commits?

    ### 4. Get failure details for a run

    Use `get_test_case_run` with a failing run ID. Key fields:

    - **failures[].message**: the assertion or error message
    - **failures[].path**: source file path
    - **failures[].line_number**: exact line of failure
    - **failures[].issue_type**: type of issue
    - **repetitions**: retry behavior (pass/fail sequence)
    - **test_run_id**: the broader test run this execution belongs to

    ### 5. Handle crashes explicitly

    If the failing run has empty failures, abrupt termination symptoms, or process-level crashes:

    - Use `get_test_run` with `test_run_id` from the test case run.
    - Inspect **crashed_test_count** and **crashes[]** for the impacted test case runs.
    - Use crash fields (**signal**, **exception_type**, **exception_subtype**) to decide if the fix is in test code, app/runtime code, or environment setup.
    - Prioritize deterministic fixes (remove force-unwrapped assumptions, isolate shared state, stabilize fixtures/bootstrapping).

    ### 6. Read and analyze source code

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

    ### 7. Apply the fix

    - Apply the smallest fix that addresses the root cause.
    - Do not refactor unrelated code.
    - Reuse existing test utilities before creating new ones.

    ### 8. Verify

    Run the specific test repeatedly until failure using:

    ```bash
    xcodebuild test -workspace <workspace> -scheme <scheme> -only-testing <module>/<suite>/<test> -test-iterations <count> -run-tests-until-failure
    ```

    Use 50-100 iterations for fast unit tests, 2-5 for slower integration tests.

    ### Done checklist

    - Identified the root cause of flakiness.
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
    3. Pick a flaky test case and call `get_test_case` with its ID.
    """
  end

  defp discovery_section(account_handle, project_handle, nil)
       when is_binary(account_handle) and is_binary(project_handle) do
    """
    ### 1. Discover flaky tests

    1. Use `list_test_cases` with account_handle="#{account_handle}" and project_handle="#{project_handle}" and set flaky=true.
    2. Pick a flaky test case and call `get_test_case` with its ID.
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
