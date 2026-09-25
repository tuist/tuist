defmodule Tuist.Tests.Coverage.Gates do
  @moduledoc """
  Coverage gates: the per-project thresholds a pull request commit's
  coverage is held to, reported as one GitHub check run per commit and never
  mandatory on their own. Off by default.

  Two gates exist: a minimum patch coverage, and a maximum drop of the total
  against the baseline. The check stays **pending until the commit's
  coverage pipeline signals completion** (`Tuist.Tests.Coverage.Commits.signal_complete/2`),
  since whether every run has reported cannot be read off the data; a project
  whose pipeline never signals cannot use gates. Once posted, the verdict is
  the commit's: a run landing after the signal joins the commit's coverage
  but leaves the check as it was. A gate that cannot be evaluated, because
  there is no comparable baseline or the patch is unavailable on a partial
  measurement, is neutral rather than failed, and the check says why.
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
      max_total_drop: project.coverage_gate_max_total_drop
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

  defp drop_check(threshold, %{commit: %{partial: true}, baseline: baseline}) when not is_nil(baseline) do
    %{gate: :max_total_drop, threshold: threshold, value: nil, status: :neutral, reason: %{kind: :partial_run}}
  end

  defp drop_check(threshold, %{baseline_reason: reason}) do
    %{gate: :max_total_drop, threshold: threshold, value: nil, status: :neutral, reason: reason}
  end

  @doc """
  Schedules the check run for a pull request run's commit once the run's
  coverage is published: a pending check until the commit signals
  completion. Nothing is scheduled for a project without gates, a run that
  is not a pull request's, or a run without a commit or from a dirty
  checkout.
  """
  def enqueue(%Project{coverage_gates_enabled: true, id: project_id}, %Test{is_pull_request: true} = run) do
    if is_binary(run.git_commit_sha) and run.git_commit_sha != "" and run.git_dirty != true do
      %{project_id: project_id, git_commit_sha: run.git_commit_sha, git_ref: run.git_ref, trigger: "run"}
      |> CoverageGateWorker.new()
      |> Oban.insert()
    else
      :skipped
    end
  end

  def enqueue(_project, _run), do: :skipped

  @doc "Schedules the check run's verdict, once the commit's coverage pipeline signalled completion."
  def enqueue_signal(%Project{coverage_gates_enabled: true, id: project_id}, sha) do
    %{project_id: project_id, git_commit_sha: sha, trigger: "signal"}
    |> CoverageGateWorker.new()
    |> Oban.insert()
  end

  def enqueue_signal(_project, _sha), do: :skipped
end
