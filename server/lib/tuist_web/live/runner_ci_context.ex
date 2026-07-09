defmodule TuistWeb.RunnerCIContext do
  @moduledoc false

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.JobSteps
  alias TuistWeb.RunnerJobLive
  alias TuistWeb.RunnerWorkflowsLive

  def build(run, selected_account, kind, ci_run_url) when kind in [:build, :test] and not is_nil(ci_run_url) do
    with "github" <- normalize_provider(Map.get(run, :ci_provider)),
         repository when is_binary(repository) and repository != "" <- Map.get(run, :ci_project_handle),
         workflow_run_id when is_integer(workflow_run_id) <- parse_workflow_run_id(Map.get(run, :ci_run_id)),
         jobs when jobs != [] <- Jobs.list_for_workflow_run(selected_account.id, repository, workflow_run_id),
         runner_job when not is_nil(runner_job) <- matching_job(jobs, kind) do
      steps = JobSteps.list_for_job(runner_job.workflow_job_id)
      matched_step = matching_step(steps, kind)

      %{
        matched_step: matched_step,
        matched_step_path: RunnerJobLive.step_path(selected_account.name, runner_job, matched_step),
        runner_job: runner_job,
        runner_job_path: RunnerJobLive.path(selected_account.name, runner_job),
        workflow_path: RunnerWorkflowsLive.workflow_path(selected_account.name, runner_job)
      }
    else
      _ -> nil
    end
  end

  def build(_, _, _, _), do: nil

  defp normalize_provider(provider) when is_binary(provider), do: provider
  defp normalize_provider(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp normalize_provider(_), do: nil

  defp parse_workflow_run_id(value) when is_integer(value) and value > 0, do: value

  defp parse_workflow_run_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {workflow_run_id, ""} when workflow_run_id > 0 -> workflow_run_id
      _ -> nil
    end
  end

  defp parse_workflow_run_id(_), do: nil

  defp matching_job(jobs, :build), do: find_by_name(jobs, ["build"]) || List.first(jobs)
  defp matching_job(jobs, :test), do: find_by_name(jobs, ["test", "tests"]) || List.first(jobs)

  defp find_by_name(jobs, needles) do
    Enum.find(jobs, fn job ->
      name = job |> Map.get(:job_name, "") |> String.downcase()
      Enum.any?(needles, &String.contains?(name, &1))
    end)
  end

  defp matching_step(steps, :build), do: find_step_by_name(steps, ["build"])
  defp matching_step(steps, :test), do: find_step_by_name(steps, ["test", "tests"])

  defp find_step_by_name(steps, needles) do
    Enum.find(steps, fn step ->
      name = step |> Map.get(:name, "") |> String.downcase()
      Enum.any?(needles, &String.contains?(name, &1))
    end)
  end
end
