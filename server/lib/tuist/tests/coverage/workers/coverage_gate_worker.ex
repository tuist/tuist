defmodule Tuist.Tests.Coverage.Workers.CoverageGateWorker do
  @moduledoc """
  Posts the `tuist/coverage` check run for a pull request commit. Triggered
  by a run (`trigger: "run"`), it posts a pending check while the commit's
  coverage pipeline is still running, and does nothing once the commit is
  complete: the verdict is final. Triggered by the completion signal
  (`trigger: "signal"`), it compares the commit with its baseline, evaluates
  the project's gates (`Tuist.Tests.Coverage.Gates`) and posts the verdict.
  The check targets the pull request's head commit, which GitHub resolves
  from a `refs/pull/N/...` ref or the pull request number, and falls back to
  the commit itself.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id, :git_commit_sha, :trigger], states: :incomplete, period: :infinity]

  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.VCS

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "git_commit_sha" => sha} = args}) do
    with project when not is_nil(project) <- Projects.get_project_by_id(project_id),
         project = Repo.preload(project, [:account, vcs_connection: :github_app_installation]),
         true <- project.coverage_gates_enabled,
         true <- Projects.has_vcs_connection?(project),
         %{} <- VCS.github_app_credentials(project.vcs_connection.github_app_installation),
         summary when not is_nil(summary) <- Commits.summary(project.id, sha) do
      head = project |> Comparison.from_commit(sha) |> Map.put_new(:git_ref, args["git_ref"])

      case {args["trigger"], summary.complete} do
        {"signal", _} -> post_verdict(project, head, Comparison.compare(project, head))
        {_, false} -> post_pending(project, head, summary)
        {_, true} -> :ok
      end
    else
      _ -> :ok
    end
  end

  defp post_pending(project, head, summary) do
    post_check_run(project, head, %{
      status: "in_progress",
      conclusion: nil,
      output: %{
        title: "Waiting for the coverage pipeline to finish",
        summary:
          "Coverage so far: #{summary.coverage}% over #{schemes_text(summary.schemes)}. " <>
            "The gates are evaluated once the pipeline signals completion (`tuist coverage complete`).\n\n" <>
            "[View the commit's coverage](#{details_url(project, head.sha)})"
      }
    })
  end

  defp post_verdict(project, head, nil), do: post_pending(project, head, %{coverage: 0.0, schemes: []})

  defp post_verdict(project, head, comparison) do
    verdict = Gates.evaluate(project, comparison)

    post_check_run(project, head, %{
      status: "completed",
      conclusion: conclusion(verdict.conclusion),
      output: %{title: title(verdict), summary: summary(comparison, verdict, details_url(project, head.sha))}
    })
  end

  defp post_check_run(project, head, params) do
    params =
      Map.merge(params, %{
        repository_full_handle: project.vcs_connection.repository_full_handle,
        installation: project.vcs_connection.github_app_installation,
        name: Gates.check_name(),
        head_sha: head_sha(project, head),
        details_url: details_url(project, head.sha),
        external_id: head.sha
      })

    case Client.create_check_run(params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp details_url(project, sha),
    do: Environment.app_url(path: "/#{project.account.name}/#{project.name}/tests/coverage/commits/#{sha}")

  defp head_sha(project, head) do
    with number when is_integer(number) and number > 0 <- pull_request_number(head),
         {:ok, %{"head" => %{"sha" => head_sha}}} <-
           Client.get_pull_request(%{
             repository_full_handle: project.vcs_connection.repository_full_handle,
             installation: project.vcs_connection.github_app_installation,
             pr_number: number
           }) do
      head_sha
    else
      _ -> head.sha
    end
  end

  defp pull_request_number(%{pull_request_number: number}) when is_integer(number) and number > 0, do: number

  defp pull_request_number(%{git_ref: "refs/pull/" <> rest}) do
    case Integer.parse(rest) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp pull_request_number(_head), do: nil

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

    schemes =
      if length(comparison.schemes) > 1 do
        "\n| Scheme | Coverage | Change |\n|:-|:-:|:-:|\n" <>
          Enum.map_join(comparison.schemes, "\n", fn row ->
            "| `#{row.scheme}` | #{scheme_total(row)} | #{scheme_delta(row)} |"
          end) <> "\n"
      else
        ""
      end

    String.trim("""
    | Coverage | Patch | Gaps |
    |:-:|:-:|:-:|
    | #{total_text(comparison)} | #{patch_text(comparison.patch)} | #{gaps_text(comparison.gaps)} |
    #{schemes}#{if checks != "", do: "\n| Gate | Threshold | Measured | Result |\n|:-|:-:|:-:|:-:|\n" <> checks <> "\n"}
    [View the commit's coverage](#{details_url})
    """)
  end

  # A commit compared through its reported coverage is judged on that figure,
  # so that is the one the check leads with. Its measured figure is whatever
  # the runs that did execute happened to cover, and for a commit whose every
  # scheme was skipped it is 0%, which reads as a catastrophe beside a gate
  # that has just passed.
  defp total_text(%{commit: %{partial: true, coverage: coverage, reported: %{kind: "reported"} = reported}} = comparison) do
    carried =
      "#{reported.coverage}% (#{coverage}% measured, #{reported.carried_tests_count} " <>
        "#{if reported.carried_tests_count == 1, do: "test", else: "tests"} carried forward)"

    case comparison do
      %{total_delta: delta, baseline: baseline} when is_float(delta) ->
        "#{carried}, #{signed(delta)}% against #{reported_baseline(baseline)}% at `#{short(baseline.commit)}`"

      %{baseline_reason: reason} when not is_nil(reason) ->
        "#{carried}, no baseline: #{Comparison.reason_text(reason)}"

      _ ->
        carried
    end
  end

  defp total_text(%{commit: %{partial: true, coverage: coverage}, total_delta: nil, baseline: baseline})
       when not is_nil(baseline), do: "#{coverage}% (some tests were skipped, not compared)"

  defp total_text(%{commit: %{coverage: coverage}, total_delta: nil, baseline_reason: reason}),
    do: "#{coverage}% (no baseline: #{Comparison.reason_text(reason)})"

  defp total_text(%{commit: %{coverage: coverage}, total_delta: delta, baseline: baseline}),
    do: "#{coverage}% (#{signed(delta)}% against #{baseline.coverage}% at `#{short(baseline.commit)}`)"

  defp reported_baseline(%{
         reported_kind: "reported",
         reported_covered_lines: covered,
         reported_executable_lines: executable
       }), do: Coverage.percentage(covered, executable)

  defp reported_baseline(baseline), do: baseline.coverage

  defp scheme_total(%{coverage: nil}), do: "—"
  defp scheme_total(%{partial: true, coverage: coverage}), do: "#{coverage}% (partial)"
  defp scheme_total(%{coverage: coverage}), do: "#{coverage}%"

  defp scheme_delta(%{delta: delta, baseline_coverage: baseline}) when is_float(delta),
    do: "#{signed(delta)}% (#{baseline}%)"

  defp scheme_delta(_row), do: "—"

  defp patch_text(%{status: :available, executable_lines: 0}), do: "no changed executable lines"

  defp patch_text(%{status: :available} = patch),
    do: "#{patch.coverage}% (#{patch.covered_lines} of #{patch.executable_lines} changed lines)"

  defp patch_text(%{status: :unavailable} = patch), do: "unavailable: #{Comparison.reason_text(patch)}"

  defp gaps_text([]), do: "none"
  defp gaps_text(gaps), do: Enum.map_join(gaps, ", ", &"`#{&1.path}`")

  defp schemes_text([]), do: "no scheme"
  defp schemes_text(schemes), do: Enum.map_join(schemes, ", ", &"`#{&1}`")

  defp gate_label(:min_patch_coverage), do: "Minimum patch coverage"
  defp gate_label(:max_total_drop), do: "Maximum total drop"

  defp threshold_label(%{gate: :min_patch_coverage, threshold: threshold}), do: "#{threshold}%"
  defp threshold_label(%{gate: :max_total_drop, threshold: threshold}), do: "#{threshold}%"

  defp value_label(%{value: nil}), do: "—"
  defp value_label(%{gate: :min_patch_coverage, value: value}), do: "#{value}%"
  defp value_label(%{gate: :max_total_drop, value: value}), do: "#{signed(value)}%"

  defp status_label(%{status: :passed}), do: "✅"
  defp status_label(%{status: :failed}), do: "❌"
  defp status_label(%{status: :neutral, reason: reason}), do: "⚪ #{Comparison.reason_text(reason)}"

  defp signed(value) when value > 0, do: "+#{value}"
  defp signed(value), do: "#{value}"

  defp short(sha), do: String.slice(sha, 0, 7)
end
