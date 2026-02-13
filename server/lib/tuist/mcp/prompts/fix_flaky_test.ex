defmodule Tuist.MCP.Prompts.FixFlakyTest do
  @moduledoc false

  def name, do: "fix_flaky_test"

  def definition do
    %{
      name: name(),
      description:
        "Guides you through fixing a flaky test by analyzing failure patterns, identifying the root cause, and applying a targeted correction.",
      arguments: [
        %{
          name: "account_handle",
          description: "The account handle (organization or user). Required if project_handle is provided.",
          required: false
        },
        %{
          name: "project_handle",
          description: "The project handle. Required if account_handle is provided.",
          required: false
        },
        %{
          name: "test_case_id",
          description: "The UUID of a specific flaky test case to fix.",
          required: false
        }
      ]
    }
  end

  def get(arguments) do
    account_handle = Map.get(arguments, "account_handle")
    project_handle = Map.get(arguments, "project_handle")
    test_case_id = Map.get(arguments, "test_case_id")

    messages = build_messages(account_handle, project_handle, test_case_id)
    {:ok, %{messages: messages}}
  end

  defp build_messages(account_handle, project_handle, test_case_id) do
    [
      %{
        role: "user",
        content: %{
          type: "text",
          text: prompt_text(account_handle, project_handle, test_case_id)
        }
      }
    ]
  end

  defp prompt_text(account_handle, project_handle, test_case_id) do
    discovery_section = discovery_section(account_handle, project_handle, test_case_id)

    """
    # Fix Flaky Test

    You have access to the following MCP tools for investigating flaky tests:

    - **list_projects**: List all accessible projects.
    - **list_flaky_tests**: List flaky test cases for a project (requires account_handle and project_handle).
    - **get_test_case**: Get detailed metrics for a test case (requires test_case_id).
    - **get_test_case_run**: Get failure details for a specific run (requires test_case_run_id).

    ## Steps

    #{discovery_section}

    ### 2. Investigate the test case

    Use `get_test_case` with the test case ID to get:
    - **reliability_rate**: percentage of successful runs (higher is better)
    - **flakiness_rate**: percentage of runs marked flaky in the last 30 days
    - **total_runs** / **failed_runs**: volume context
    - **last_status**: current state

    ### 3. Examine failure details

    Use `get_test_case_run` with a failing run ID to get:
    - **failures[].message**: the assertion or error message
    - **failures[].path**: source file path
    - **failures[].line_number**: exact line of failure
    - **failures[].issue_type**: type of issue
    - **repetitions**: retry behavior (pass/fail sequence)

    ### 4. Read and analyze the source code

    Open the file at the reported path and line number. Read the full test function and its setup/teardown. Look for these common flaky patterns:

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

    ### 5. Apply the fix

    - Apply the smallest fix that addresses the root cause.
    - Do not refactor unrelated code.
    - Check if existing test utilities can be reused before creating new ones.

    ### 6. Verify

    Run the specific test repeatedly to confirm it passes consistently:

    ```bash
    xcodebuild test -workspace <workspace> -scheme <scheme> -only-testing <module>/<suite>/<test> -test-iterations <count> -run-tests-until-failure
    ```

    Use 50-100 iterations for fast unit tests, 2-5 for slower integration tests.
    """
  end

  defp discovery_section(nil, nil, nil) do
    """
    ### 1. Discover flaky tests

    First, use `list_projects` to find available projects. Then use `list_flaky_tests` with the project's account_handle and project_handle to find all flaky test cases. Prioritize by:
    1. Group tests by suite (multiple flaky tests in the same suite often share a root cause).
    2. Look at failure messages to categorize: test logic bugs vs infrastructure issues.
    """
  end

  defp discovery_section(account_handle, project_handle, nil)
       when is_binary(account_handle) and is_binary(project_handle) do
    """
    ### 1. Discover flaky tests

    Use `list_flaky_tests` with account_handle="#{account_handle}" and project_handle="#{project_handle}" to find all flaky test cases. Prioritize by:
    1. Group tests by suite (multiple flaky tests in the same suite often share a root cause).
    2. Look at failure messages to categorize: test logic bugs vs infrastructure issues.
    """
  end

  defp discovery_section(_account_handle, _project_handle, test_case_id) when is_binary(test_case_id) do
    """
    ### 1. Get test case details

    Use `get_test_case` with test_case_id="#{test_case_id}" to get the metrics for this specific flaky test.
    """
  end

  defp discovery_section(_, _, _) do
    discovery_section(nil, nil, nil)
  end
end
