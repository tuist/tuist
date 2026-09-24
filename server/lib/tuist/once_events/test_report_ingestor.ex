defmodule Tuist.OnceEvents.TestReportIngestor do
  @moduledoc """
  Publishes a finished Once test run into the shared test store.

  Bazel receives one complete report at the end of a run and writes it
  straight through (`Tuist.Bazel.TestReportIngestor`). Once instead streams
  `TestSuiteStarted` / `TestCaseCompleted` as the run progresses, and
  `RunCompleted` carries only per-result counts, so the case detail exists
  nowhere but the `once_test_*` rows the projector has been accumulating.

  Those rows are therefore ingestion state, not a second product store: this
  module reads them once the run finalizes, assembles the same nested report
  Bazel builds, and hands it to `Tuist.Tests.create_test/1` with
  `build_system: "once"`. Everything downstream of the shared store (flaky
  detection, quarantine, history, the API) then works for Once without a
  parallel implementation.
  """
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Run
  alias Tuist.Projects
  alias Tuist.Tests

  require Logger

  @doc """
  Publish `run`'s test results. A no-op for runs that carried no test cases,
  which is every `once build`.
  """
  def publish(%Run{} = run) do
    case OnceEvents.list_test_case_runs(run) do
      [] -> {:ok, :no_test_cases}
      case_runs -> publish_cases(run, case_runs)
    end
  end

  defp publish_cases(%Run{} = run, case_runs) do
    case Projects.get_project_by_id(run.project_id) do
      nil ->
        {:error, :project_not_found}

      project ->
        attributes = test_attributes(project, run, case_runs)

        case Tests.create_test(attributes) do
          {:ok, test} ->
            {:ok, test}

          {:error, changeset} ->
            Logger.warning("once: could not publish test report: #{inspect(changeset.errors)}")

            {:error, :persistence}
        end
    end
  end

  defp test_attributes(project, %Run{} = run, case_runs) do
    test_modules = test_modules(case_runs)

    %{
      # Derived from the run rather than generated, so republishing the same
      # run targets the same shared row instead of creating a second one.
      id: test_run_id(run),
      project_id: project.id,
      account_id: project.account_id,
      duration: bounded_duration(run.wall_ms),
      status: test_status(run.exit_status, test_modules),
      scheme: String.slice(run.command_display || "", 0, 1_024),
      model_identifier: "",
      macos_version: "",
      xcode_version: "",
      git_branch: run.git_branch || "",
      git_ref: git_ref(run.git_branch),
      git_commit_sha: run.git_rev || "",
      ran_at: run.finalized_at || run.started_at,
      is_ci: run.is_ci || false,
      build_system: "once",
      once_run_id: run.run_id,
      test_modules: test_modules
    }
  end

  defp test_modules(case_runs) do
    case_runs
    |> Enum.group_by(& &1.target_execution_id)
    |> Enum.map(fn {target, target_cases} ->
      test_cases = Enum.map(target_cases, &test_case/1)

      %{
        name: target,
        status: aggregate_status(test_cases),
        duration: Enum.sum(Enum.map(test_cases, & &1.duration)),
        test_suites: suites_from_cases(test_cases),
        test_cases: test_cases
      }
    end)
  end

  defp test_case(case_run) do
    %{
      name: case_run.name || case_run.case_id,
      test_suite_name: case_run.suite_id || case_run.target_execution_id,
      status: shared_status(case_run.result),
      duration: case_run.duration_ms || 0
    }
  end

  defp suites_from_cases(test_cases) do
    test_cases
    |> Enum.group_by(& &1.test_suite_name)
    |> Enum.map(fn {name, cases} ->
      %{
        name: name,
        status: aggregate_status(cases),
        duration: Enum.sum(Enum.map(cases, & &1.duration))
      }
    end)
  end

  # The shared column is `Enum8('success', 'failure', 'skipped')`, so an
  # unmapped Once result is a write error rather than a silent coercion.
  # Once reports eight.
  #
  # `errored` and `timed_out` are verdicts against the test, so they fail.
  # `cancelled`, `unknown` and anything unspecified never reached a verdict:
  # counting those as failures would manufacture failure and flakiness signals
  # out of an interrupted run, so they are skipped instead. The original Once
  # result stays on the `once_test_case_runs` row either way.
  defp shared_status("passed"), do: "success"
  defp shared_status("failed"), do: "failure"
  defp shared_status("errored"), do: "failure"
  defp shared_status("timed_out"), do: "failure"
  defp shared_status(_no_verdict), do: "skipped"

  defp aggregate_status(items) do
    cond do
      Enum.any?(items, &(&1.status == "failure")) -> "failure"
      items != [] and Enum.all?(items, &(&1.status == "skipped")) -> "skipped"
      true -> "success"
    end
  end

  # A failed case makes the run a failure even when the client reported a
  # zero exit status. The shared store feeds flaky detection, so a report
  # claiming success while carrying a failed case would poison it.
  defp test_status(exit_status, test_modules) do
    cond do
      exit_status not in [0, nil] -> "failure"
      Enum.any?(test_modules, &(&1.status == "failure")) -> "failure"
      test_modules != [] and Enum.all?(test_modules, &(&1.status == "skipped")) -> "skipped"
      true -> "success"
    end
  end

  defp git_ref(branch) when is_binary(branch) and branch != "", do: "refs/heads/#{branch}"
  defp git_ref(_blank), do: ""

  defp bounded_duration(nil), do: 0
  defp bounded_duration(duration) when duration < 0, do: 0
  defp bounded_duration(duration), do: duration

  # A Once run id is client-minted and only unique within its project, so the
  # shared row's UUID is derived from both.
  defp test_run_id(%Run{} = run) do
    OnceEvents.uuid_from_seed("once-test-run\0#{run.project_id}\0#{run.run_id}")
  end
end
