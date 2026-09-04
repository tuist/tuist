defmodule Tuist.Bazel.TestReportIngestor do
  @moduledoc false

  alias Tuist.Bazel.JunitReport
  alias Tuist.Projects.Project
  alias Tuist.Tests

  require Logger

  def ingest(%Project{} = project, invocation, test_result, report)
      when is_map(invocation) and is_map(test_result) and is_binary(report) do
    with {:ok, %{test_suites: test_suites, test_cases: test_cases}} <- JunitReport.parse(report),
         true <- test_cases != [] do
      test_module = %{
        name: test_result.target_label,
        status: module_status(test_result.status, test_cases),
        duration: duration(test_result.duration_ms),
        test_suites: test_suites,
        test_cases: test_cases
      }

      case Tests.create_test(test_attributes(project, invocation, [test_module])) do
        {:ok, _test} ->
          :ok

        {:error, changeset} ->
          Logger.warning("bazel: could not persist structured test report: #{inspect(changeset.errors)}")
          {:error, :persistence}
      end
    else
      {:error, reason} ->
        Logger.debug("bazel: could not parse structured test report: #{inspect(reason)}")
        {:error, :invalid_report}

      false ->
        {:error, :empty_report}
    end
  rescue
    exception ->
      Logger.error("bazel: structured test report ingestion failed: #{Exception.message(exception)}")
      {:error, :persistence}
  end

  def ingest(_, _, _, _), do: :ok

  defp module_status("failure", _test_cases), do: "failure"

  defp module_status(_, test_cases),
    do: if(Enum.any?(test_cases, &(&1.status == "failure")), do: "failure", else: "success")

  defp test_attributes(project, invocation, test_modules) do
    %{
      id: UUIDv7.generate(),
      project_id: project.id,
      account_id: project.account_id,
      duration: duration(invocation.duration_ms),
      status: if(invocation.exit_code == 0, do: "success", else: "failure"),
      scheme:
        invocation
        |> Map.get(:target_patterns, [test_modules |> List.first() |> Map.fetch!(:name)])
        |> Enum.join(" ")
        |> String.slice(0, 1_024),
      model_identifier: "",
      macos_version: "",
      xcode_version: "",
      git_branch: Map.get(invocation, :git_branch, ""),
      git_ref: invocation |> Map.get(:git_branch, "") |> git_ref(),
      git_commit_sha: Map.get(invocation, :git_commit_sha, ""),
      ran_at: invocation.finished_at,
      is_ci: false,
      build_system: "bazel",
      bazel_invocation_id: invocation.invocation_id,
      test_modules: test_modules
    }
  end

  defp git_ref(""), do: ""
  defp git_ref(branch), do: "refs/heads/#{branch}"

  defp duration(value) when is_integer(value), do: min(max(value, 0), 2_147_483_647)
  defp duration(_), do: 0
end
