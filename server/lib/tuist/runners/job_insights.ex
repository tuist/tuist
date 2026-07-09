defmodule Tuist.Runners.JobInsights do
  @moduledoc """
  Links runner jobs with the build and test insights emitted by the same CI workflow run.
  """

  import Ecto.Query

  alias Tuist.Builds.Build, as: BuildRun
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Tests.Test, as: TestRun

  def for_job(account, job) do
    case project_for_job(account, job) do
      nil ->
        empty()

      project ->
        build_runs = list_build_runs(project, job.workflow_run_id)
        test_runs = list_test_runs(project, job.workflow_run_id)

        build_command_events = build_runs |> command_events_for_runs(:build) |> Enum.reject(&is_nil/1)
        test_command_events = test_runs |> command_events_for_runs(:test) |> Enum.reject(&is_nil/1)

        %{
          project: project,
          build_runs: build_runs,
          test_runs: test_runs,
          build_module_cache_summary: module_cache_summary(build_command_events),
          test_selective_testing_summary: selective_testing_summary(test_command_events)
        }
    end
  end

  defp empty do
    %{
      project: nil,
      build_runs: [],
      test_runs: [],
      build_module_cache_summary: module_cache_summary([]),
      test_selective_testing_summary: selective_testing_summary([])
    }
  end

  def project_for_job(account, %{repository: repository}) when is_binary(repository) do
    case String.split(repository, "/", parts: 2) do
      [_owner, project_handle] ->
        Projects.get_project_by_account_and_project_handles(account.name, project_handle)

      _ ->
        nil
    end
  end

  def project_for_job(_, _), do: nil

  def list_build_runs(project, workflow_run_id) do
    workflow_run_id = Integer.to_string(workflow_run_id)

    BuildRun
    |> where([build], build.project_id == ^project.id)
    |> where([build], build.ci_provider == "github")
    |> where([build], build.ci_run_id == ^workflow_run_id)
    |> order_by([build], desc: build.inserted_at)
    |> ClickHouseRepo.all()
    |> latest_runner_runs_by_id()
  end

  def list_test_runs(project, workflow_run_id) do
    workflow_run_id = Integer.to_string(workflow_run_id)

    TestRun
    |> where([test], test.project_id == ^project.id)
    |> where([test], test.status != "in_progress")
    |> where([test], test.ci_provider == "github")
    |> where([test], test.ci_run_id == ^workflow_run_id)
    |> order_by([test], desc: test.inserted_at, desc: test.ran_at)
    |> ClickHouseRepo.all()
    |> latest_runner_runs_by_id()
    |> Enum.sort_by(&datetime_sort_key(&1.ran_at), :desc)
  end

  defp module_cache_summary(command_events) do
    total_count = Enum.sum(Enum.map(command_events, &(&1.cacheable_targets_count || 0)))
    local_hits_count = Enum.sum(Enum.map(command_events, &(&1.local_cache_hits_count || 0)))
    remote_hits_count = Enum.sum(Enum.map(command_events, &(&1.remote_cache_hits_count || 0)))

    %{
      local_hits_count: local_hits_count,
      remote_hits_count: remote_hits_count,
      hits_count: local_hits_count + remote_hits_count,
      total_count: total_count
    }
  end

  defp selective_testing_summary(command_events) do
    total_count = Enum.sum(Enum.map(command_events, &(&1.test_targets_count || 0)))
    local_hits_count = Enum.sum(Enum.map(command_events, &(&1.local_test_hits_count || 0)))
    remote_hits_count = Enum.sum(Enum.map(command_events, &(&1.remote_test_hits_count || 0)))

    %{
      local_hits_count: local_hits_count,
      remote_hits_count: remote_hits_count,
      hits_count: local_hits_count + remote_hits_count,
      total_count: total_count
    }
  end

  defp latest_runner_runs_by_id(runs) do
    runs
    |> Enum.sort_by(&datetime_sort_key(&1.inserted_at), :desc)
    |> Enum.uniq_by(& &1.id)
  end

  defp datetime_sort_key(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp datetime_sort_key(_), do: ""

  defp command_events_for_runs(runs, kind) do
    Enum.map(runs, fn run ->
      case kind do
        :build ->
          case CommandEvents.get_command_event_by_build_run_id(run.id, project_id: run.project_id) do
            {:ok, event} -> event
            {:error, :not_found} -> nil
          end

        :test ->
          case CommandEvents.get_command_event_by_test_run_id(run.id, project_id: run.project_id) do
            {:ok, event} -> event
            {:error, :not_found} -> nil
          end
      end
    end)
  end
end
