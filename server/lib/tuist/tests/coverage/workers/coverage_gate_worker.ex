defmodule Tuist.Tests.Coverage.Workers.CoverageGateWorker do
  @moduledoc """
  Posts the `tuist/coverage` check run for a pull request's test run: the
  run's coverage against its baseline, its patch coverage and gaps, and the
  verdict of the project's gates (`Tuist.Tests.Coverage.Gates`). The check
  targets the pull request's head commit, which GitHub resolves from the
  run's `refs/pull/N/...` ref, and falls back to the run's commit.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:test_run_id], states: :incomplete, period: :infinity]

  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.VCS

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "test_run_id" => test_run_id}}) do
    with {:ok, run} <- Tests.get_test(test_run_id),
         project when not is_nil(project) <- Projects.get_project_by_id(project_id),
         project = Repo.preload(project, [:account, vcs_connection: :github_app_installation]),
         true <- project.coverage_gates_enabled,
         true <- Projects.has_vcs_connection?(project),
         %{} <- VCS.github_app_credentials(project.vcs_connection.github_app_installation),
         comparison when not is_nil(comparison) <- Comparison.compare(project, run) do
      post_check_run(project, run, comparison, Gates.evaluate(project, comparison))
    else
      {:error, :not_found} -> {:snooze, 30}
      _ -> :ok
    end
  end

  defp post_check_run(project, run, comparison, verdict) do
    account_name = project.account.name
    details_url = Environment.app_url(path: "/#{account_name}/#{project.name}/tests/test-runs/#{run.id}?tab=coverage")

    params = %{
      repository_full_handle: project.vcs_connection.repository_full_handle,
      installation: project.vcs_connection.github_app_installation,
      name: Gates.check_name(),
      head_sha: head_sha(project, run),
      status: "completed",
      conclusion: conclusion(verdict.conclusion),
      output: %{title: title(verdict), summary: summary(comparison, verdict, details_url)},
      details_url: details_url,
      external_id: run.id
    }

    case Client.create_check_run(params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp head_sha(project, run) do
    with "refs/pull/" <> rest <- run.git_ref || "",
         {pr_number, _} <- Integer.parse(rest),
         {:ok, %{"head" => %{"sha" => head_sha}}} <-
           Client.get_pull_request(%{
             repository_full_handle: project.vcs_connection.repository_full_handle,
             installation: project.vcs_connection.github_app_installation,
             pr_number: pr_number
           }) do
      head_sha
    else
      _ -> run.git_commit_sha
    end
  end

  defp conclusion(:success), do: "success"
  defp conclusion(:failure), do: "failure"
  defp conclusion(:neutral), do: "neutral"

  defp title(%{conclusion: :success}), do: "Coverage gates passed"
  defp title(%{conclusion: :failure}), do: "Coverage gates failed"
  defp title(%{checks: []}), do: "Coverage reported"
  defp title(_verdict), do: "Coverage gates could not be evaluated"

  @doc false
  def summary(comparison, verdict, details_url) do
    checks =
      Enum.map_join(verdict.checks, "\n", fn check ->
        "| #{gate_label(check.gate)} | #{threshold_label(check)} | #{value_label(check)} | #{status_label(check)} |"
      end)

    String.trim("""
    | Coverage | Patch | Gaps |
    |:-:|:-:|:-:|
    | #{total_text(comparison)} | #{patch_text(comparison.patch)} | #{gaps_text(comparison.gaps)} |
    #{if checks != "", do: "\n| Gate | Threshold | Measured | Result |\n|:-|:-:|:-:|:-:|\n" <> checks <> "\n"}
    [View the run's coverage](#{details_url})
    """)
  end

  defp total_text(%{run: %{partial: true, coverage: coverage}, total_delta: nil}),
    do: "#{coverage}% (partial run, not compared)"

  defp total_text(%{run: %{coverage: coverage}, total_delta: nil, baseline_reason: reason}),
    do: "#{coverage}% (no baseline: #{Comparison.reason_text(reason)})"

  defp total_text(%{run: %{coverage: coverage}, total_delta: delta, baseline: baseline}),
    do: "#{coverage}% (#{signed(delta)} pp against #{baseline.coverage}% at `#{short(baseline.commit)}`)"

  defp patch_text(%{status: :available, executable_lines: 0}), do: "no changed executable lines"

  defp patch_text(%{status: :available} = patch),
    do: "#{patch.coverage}% (#{patch.covered_lines} of #{patch.executable_lines} changed lines)"

  defp patch_text(%{status: :unavailable} = patch), do: "unavailable: #{Comparison.reason_text(patch)}"

  defp gaps_text([]), do: "none"
  defp gaps_text(gaps), do: Enum.map_join(gaps, ", ", &"`#{&1.path}`")

  defp gate_label(:min_patch_coverage), do: "Minimum patch coverage"
  defp gate_label(:max_total_drop), do: "Maximum total drop"

  defp threshold_label(%{gate: :min_patch_coverage, threshold: threshold}), do: "#{threshold}%"
  defp threshold_label(%{gate: :max_total_drop, threshold: threshold}), do: "#{threshold} pp"

  defp value_label(%{value: nil}), do: "—"
  defp value_label(%{gate: :min_patch_coverage, value: value}), do: "#{value}%"
  defp value_label(%{gate: :max_total_drop, value: value}), do: "#{signed(value)} pp"

  defp status_label(%{status: :passed}), do: "✅"
  defp status_label(%{status: :failed}), do: "❌"
  defp status_label(%{status: :neutral, reason: reason}), do: "⚪ #{Comparison.reason_text(reason)}"

  defp signed(value) when value > 0, do: "+#{value}"
  defp signed(value), do: "#{value}"

  defp short(sha), do: String.slice(sha, 0, 7)
end
