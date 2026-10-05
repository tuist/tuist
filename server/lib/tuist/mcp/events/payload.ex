defmodule Tuist.MCP.Events.Payload do
  @moduledoc false

  def data("test_case.marked_flaky", %{"test_case_id" => id}, {account, project}) do
    project_data(account, project, %{"test_case_id" => id}, "tests/test-cases/#{id}")
  end

  def data("build.failed", %{"build_id" => id, "build_system" => system}, {account, project}) do
    path = if system == "bazel", do: "builds/invocations/#{id}", else: "builds/build-runs/#{id}"
    project_data(account, project, %{"build_id" => id, "build_system" => system}, path)
  end

  def data("test_run.failed", %{"test_run_id" => id}, {account, project}) do
    project_data(account, project, %{"test_run_id" => id}, "tests/test-runs/#{id}")
  end

  def data("ci_job.failed", %{"workflow_job_id" => id, "workflow_run_id" => run_id}, account) do
    %{
      "account_handle" => account,
      "workflow_job_id" => id,
      "workflow_run_id" => run_id,
      "url" => "#{Tuist.Environment.app_url()}/#{account}/runners/runs/#{run_id}/jobs/#{id}"
    }
  end

  defp project_data(account, project, fields, path) do
    Map.merge(fields, %{
      "account_handle" => account,
      "project_handle" => project,
      "url" => "#{Tuist.Environment.app_url()}/#{account}/#{project}/#{path}"
    })
  end
end
