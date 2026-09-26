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
      [] ->
        {:ok, :no_test_cases}

      case_runs ->
        # The transport replays a batch whenever an ack is lost, so
        # `RunCompleted` can arrive more than once, possibly on two pods at
        # once. Claiming before publishing keeps `create_test/1` from
        # appending a second copy of every module, suite and case, which it
        # would, because it generates fresh ids for those children.
        case OnceEvents.claim_test_report_publication(run) do
          :already_published -> {:ok, :already_published}
          :ok -> publish_cases(run, case_runs)
        end
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
            # Give the claim back, otherwise a transient failure would leave
            # the run marked published and its results permanently absent.
            OnceEvents.release_test_report_publication(run)
            Logger.warning("once: could not publish test report: #{inspect(changeset.errors)}")

            {:error, :persistence}
        end
    end
  end

  defp test_attributes(project, %Run{} = run, case_runs) do
    test_modules = case_runs |> test_modules() |> mark_quarantined_cases(project, run)

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
      test_cases = aggregate_test_cases(target_cases)

      %{
        name: target,
        status: aggregate_status(test_cases),
        duration: Enum.sum(Enum.map(test_cases, & &1.duration)),
        test_suites: suites_from_cases(test_cases),
        test_cases: test_cases
      }
    end)
  end

  # One entry per case, carrying every attempt as a repetition. Once retries a
  # failing case in place and reports each attempt as its own event, so
  # collapsing them to the last one would throw away the only evidence of
  # flakiness: `Tuist.Tests` decides a case is flaky when its repetitions hold
  # both a success and a failure.
  defp aggregate_test_cases(case_runs) do
    case_runs
    |> Enum.group_by(&{&1.suite_id || &1.target_execution_id, &1.case_id || &1.name})
    |> Enum.map(fn {_identity, attempts} ->
      attempts = Enum.sort_by(attempts, &(&1.attempt || 1))
      last = List.last(attempts)

      %{
        name: last.name || last.case_id,
        test_suite_name: last.suite_id || last.target_execution_id,
        # The verdict is the final attempt's: a case that passed on retry
        # passed, and is recorded as flaky through its repetitions instead.
        status: shared_status(last.result),
        duration: Enum.sum(Enum.map(attempts, &(&1.duration_ms || 0))),
        repetitions: repetitions(attempts)
      }
    end)
  end

  defp repetitions(attempts) do
    attempts
    |> Enum.with_index(1)
    |> Enum.map(fn {attempt, number} ->
      %{
        name: "Attempt #{number}",
        repetition_number: number,
        status: shared_status(attempt.result),
        duration: attempt.duration_ms || 0
      }
    end)
  end

  # Without this a quarantined case keeps failing runs for Once, because the
  # shared store only knows a case is quarantined if the report says so. The
  # state is read as of the run's start so a case quarantined afterwards does
  # not retroactively change a finished run.
  defp mark_quarantined_cases(test_modules, project, %Run{} = run) do
    identities =
      for module <- test_modules, test_case <- module.test_cases do
        Tests.generate_test_case_id(project.id, test_case.name, module.name, test_case.test_suite_name)
      end

    states = Tests.get_test_case_states_at(project.id, identities, run.started_at || run.finalized_at)

    Enum.map(test_modules, fn module ->
      Map.update!(module, :test_cases, fn cases ->
        Enum.map(cases, fn test_case ->
          id = Tests.generate_test_case_id(project.id, test_case.name, module.name, test_case.test_suite_name)
          Map.put(test_case, :is_quarantined, states[id].state in Tests.active_quarantine_states())
        end)
      end)
    end)
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
