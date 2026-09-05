defmodule Tuist.Bazel.Workers.ProcessTestInvocationWorker do
  @moduledoc """
  Processes Bazel test results outside the web tier after an invocation ends.

  The webhook only performs bounded validation and PostgreSQL writes. This
  worker runs on the Linux build-processor fleet, parses the untrusted JUnit
  reports, and writes one test run for the complete Bazel invocation.
  """

  use Oban.Worker,
    queue: :process_bazel_tests,
    max_attempts: 40,
    unique: [keys: [:project_id, :invocation_id], states: :incomplete, period: :infinity]

  alias Tuist.Bazel
  alias Tuist.Projects
  alias Tuist.Tests.Sanitizer

  require Logger

  @invocation_retry_seconds 15
  @invocation_wait_minutes 15
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "invocation_id" => invocation_id}}) do
    case Bazel.get_test_invocation(project_id, invocation_id) do
      %{state: "pending"} = test_invocation ->
        process_pending_invocation(test_invocation)

      %{state: "processed"} ->
        :ok

      %{state: "collecting"} = test_invocation ->
        wait_or_discard(test_invocation)

      nil ->
        {:discard, :test_invocation_not_found}
    end
  end

  defp process_pending_invocation(test_invocation) do
    project_id = test_invocation.project_id
    invocation_id = test_invocation.invocation_id

    with project when not is_nil(project) <- Projects.get_project_by_id(project_id),
         {:ok, invocation} <- Bazel.get_invocation(project_id, invocation_id) do
      test_results = Bazel.list_test_results(project_id, invocation_id)
      test_summaries = Bazel.list_test_summaries(project_id, invocation_id)

      process_results(
        project,
        Map.put(invocation, :test_run_id, test_invocation.test_run_id),
        test_invocation,
        test_results,
        test_summaries
      )
    else
      {:error, :not_found} -> wait_or_discard(test_invocation)
      nil -> {:discard, :project_not_found}
    end
  end

  defp process_results(_project, _invocation, test_invocation, [], []) do
    case Bazel.mark_test_invocation_processed(test_invocation) do
      {:ok, _test_invocation} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp process_results(project, invocation, test_invocation, test_results, test_summaries) do
    with {:ok, _test} <- Bazel.ingest_test_report(project, invocation, test_results, test_summaries),
         {_count, nil} <- Bazel.create_invocation_logs(test_logs(project.id, test_results)),
         {:ok, _test_invocation} <- Bazel.mark_test_invocation_processed(test_invocation) do
      Bazel.delete_test_results(project.id, invocation.invocation_id)
      Bazel.delete_test_summaries(project.id, invocation.invocation_id)
      :ok
    else
      error ->
        Logger.error("bazel: test invocation processing failed for #{invocation.invocation_id}: #{inspect(error)}")

        {:error, :persistence}
    end
  end

  defp test_logs(project_id, test_results) do
    test_results
    |> Enum.sort_by(& &1.sequence_number)
    |> Enum.filter(&is_binary(&1.log_content))
    |> Enum.map(fn result ->
      %{
        id: result.id,
        invocation_id: result.invocation_id,
        sequence_number: result.sequence_number,
        stream: "stdout",
        message:
          "[Bazel test log for #{result.target_label}]\n" <>
            Sanitizer.sanitize(result.log_content),
        project_id: project_id,
        observed_at: DateTime.to_naive(result.started_at)
      }
    end)
  end

  defp wait_or_discard(test_invocation) do
    cutoff = DateTime.add(DateTime.utc_now(), -@invocation_wait_minutes, :minute)

    if DateTime.before?(test_invocation.inserted_at, cutoff) do
      case Bazel.discard_test_invocation(test_invocation) do
        {:ok, _test_invocation} -> {:discard, :invocation_never_arrived}
        {:error, reason} -> {:error, reason}
      end
    else
      {:snooze, @invocation_retry_seconds}
    end
  end
end
