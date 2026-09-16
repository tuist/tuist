defmodule Tuist.Tests.Coverage.Gates do
  @moduledoc """
  Coverage gates: the per-project thresholds a pull request's coverage is
  held to, reported as a GitHub check run and never mandatory on their own.
  Off by default.

  Two gates exist: a minimum patch coverage, and a maximum drop of the total
  against the baseline. A gate that cannot be evaluated, because there is no
  baseline or the patch is unavailable on a partial run, is neutral rather
  than failed, and the check says why.
  """

  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage.Workers.CoverageGateWorker
  alias Tuist.Tests.Test

  @check_name "tuist/coverage"

  def check_name, do: @check_name

  @doc "The project's gate settings."
  def settings(%Project{} = project) do
    %{
      enabled: project.coverage_gates_enabled,
      min_patch_coverage: project.coverage_gate_min_patch_coverage,
      max_total_drop: project.coverage_gate_max_total_drop,
      patch_partial_runs: project.coverage_patch_partial_runs
    }
  end

  @doc """
  Evaluates the project's gates against a comparison
  (`Tuist.Tests.Coverage.Comparison.compare/3`): `%{conclusion, checks}`
  where the conclusion is `:success`, `:failure` or `:neutral`, and each
  check names its gate, threshold, measured value and status (`:passed`,
  `:failed` or `:neutral` with a `reason`). With no gate set, the conclusion
  is neutral and there are no checks.
  """
  def evaluate(%Project{} = project, comparison) do
    settings = settings(project)

    checks =
      Enum.reject(
        [
          settings.min_patch_coverage && patch_check(settings.min_patch_coverage, comparison),
          settings.max_total_drop && drop_check(settings.max_total_drop, comparison)
        ],
        &is_nil/1
      )

    conclusion =
      cond do
        checks == [] -> :neutral
        Enum.any?(checks, &(&1.status == :failed)) -> :failure
        Enum.any?(checks, &(&1.status == :neutral)) -> :neutral
        true -> :success
      end

    %{conclusion: conclusion, checks: checks}
  end

  defp patch_check(threshold, %{patch: %{status: :available} = patch}) do
    %{
      gate: :min_patch_coverage,
      threshold: threshold,
      value: patch.coverage,
      status: if(patch.executable_lines == 0 or patch.coverage >= threshold, do: :passed, else: :failed)
    }
  end

  defp patch_check(threshold, %{patch: %{status: :unavailable} = patch}) do
    %{gate: :min_patch_coverage, threshold: threshold, value: nil, status: :neutral, reason: patch}
  end

  defp drop_check(threshold, %{total_delta: delta}) when is_float(delta) do
    %{
      gate: :max_total_drop,
      threshold: threshold,
      value: delta,
      status: if(-delta <= threshold, do: :passed, else: :failed)
    }
  end

  defp drop_check(threshold, %{run: %{partial: true}}) do
    %{gate: :max_total_drop, threshold: threshold, value: nil, status: :neutral, reason: %{kind: :partial_run}}
  end

  defp drop_check(threshold, %{baseline_reason: reason}) do
    %{gate: :max_total_drop, threshold: threshold, value: nil, status: :neutral, reason: reason}
  end

  @doc """
  Schedules the check run for a run's coverage, once every shard reported
  and the totals are published. Nothing is scheduled for a project without
  gates or for a run that is not a pull request.
  """
  def enqueue(%Project{coverage_gates_enabled: true}, %Test{is_pull_request: true} = run) do
    %{project_id: run.project_id, test_run_id: run.id}
    |> CoverageGateWorker.new()
    |> Oban.insert()
  end

  def enqueue(_project, _run), do: :skipped
end
