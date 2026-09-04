defmodule Tuist.Bazel.TestReportIngestor do
  @moduledoc false

  alias Tuist.Bazel.JunitReport
  alias Tuist.Projects.Project
  alias Tuist.Tests

  require Logger

  def ingest(%Project{} = project, invocation, test_results, test_summaries)
      when is_map(invocation) and is_list(test_results) and is_list(test_summaries) do
    results_by_target = Enum.group_by(test_results, & &1.target_label)
    summaries_by_target = Map.new(test_summaries, &{&1.target_label, &1})

    test_modules =
      results_by_target
      |> Map.keys()
      |> Kernel.++(Map.keys(summaries_by_target))
      |> Enum.uniq()
      |> Enum.map(fn target_label ->
        target_results = Map.get(results_by_target, target_label, [])
        test_summary = Map.get(summaries_by_target, target_label)
        reports = Enum.map(target_results, &parse_report/1)
        test_cases = aggregate_test_cases(reports)

        %{
          name: target_label,
          status: module_status(test_summary, target_results),
          duration: module_duration(test_summary, target_results),
          test_suites: suites_from_cases(test_cases),
          test_cases: test_cases
        }
      end)

    attributes = test_attributes(project, invocation, test_results, test_modules)

    case Tests.create_test(attributes) do
      {:ok, test} ->
        {:ok, test}

      {:error, changeset} ->
        Logger.warning("bazel: could not persist structured test report: #{inspect(changeset.errors)}")
        {:error, :persistence}
    end
  end

  def ingest(_, _, _, _), do: {:error, :invalid_input}

  defp parse_report(%{junit_content: report}) when is_binary(report) do
    case JunitReport.parse(report) do
      {:ok, parsed} ->
        parsed

      {:error, reason} ->
        Logger.warning("bazel: could not parse structured test report: #{inspect(reason)}")
        %{test_suites: [], test_cases: []}
    end
  end

  defp parse_report(_result), do: %{test_suites: [], test_cases: []}

  defp aggregate_test_cases(reports) do
    reports
    |> Enum.flat_map(& &1.test_cases)
    |> Enum.group_by(&{&1.name, &1.test_suite_name})
    |> Enum.map(fn {_identity, cases} ->
      latest = List.last(cases)

      Map.put(
        latest,
        :repetitions,
        Enum.map(cases, &Map.take(&1, [:status, :duration, :failures]))
      )
    end)
  end

  defp suites_from_cases(test_cases) do
    test_cases
    |> Enum.group_by(& &1.test_suite_name)
    |> Enum.map(fn {name, cases} ->
      %{
        name: name,
        status: if(Enum.any?(cases, &(&1.status == "failure")), do: "failure", else: "success"),
        duration: Enum.sum(Enum.map(cases, & &1.duration))
      }
    end)
  end

  defp module_status(%{status: "failure"}, _test_results), do: "failure"
  defp module_status(%{status: _status}, _test_results), do: "success"

  defp module_status(nil, test_results) do
    final_attempts =
      test_results
      |> Enum.group_by(&{&1.run, &1.shard})
      |> Enum.map(fn {_run_and_shard, attempts} -> Enum.max_by(attempts, & &1.attempt) end)

    if Enum.any?(final_attempts, &(&1.status == "failure")), do: "failure", else: "success"
  end

  defp module_duration(%{duration_ms: duration_ms}, _test_results), do: bounded_duration(duration_ms)

  defp module_duration(nil, test_results) do
    bounded_duration(Enum.sum(Enum.map(test_results, & &1.duration_ms)))
  end

  defp test_attributes(project, invocation, test_results, test_modules) do
    target_labels = test_modules |> Enum.map(& &1.name) |> Enum.sort()
    target_patterns = if invocation.target_patterns == [], do: target_labels, else: invocation.target_patterns

    %{
      id: invocation.test_run_id,
      project_id: project.id,
      account_id: project.account_id,
      duration: bounded_duration(invocation.duration_ms),
      status: if(invocation.exit_code == 0, do: "success", else: "failure"),
      scheme: target_patterns |> Enum.join(" ") |> String.slice(0, 1_024),
      model_identifier: "",
      macos_version: "",
      xcode_version: "",
      git_branch: invocation.git_branch,
      git_ref: git_ref(invocation.git_branch),
      git_commit_sha: invocation.git_commit_sha,
      ran_at: invocation.finished_at,
      is_ci: invocation.is_ci or Enum.any?(test_results, & &1.is_ci),
      build_system: "bazel",
      bazel_invocation_id: invocation.invocation_id,
      test_modules: test_modules
    }
  end

  defp git_ref(""), do: ""
  defp git_ref(branch), do: "refs/heads/#{branch}"

  defp bounded_duration(value) when is_integer(value), do: min(max(value, 0), 2_147_483_647)
  defp bounded_duration(_), do: 0
end
