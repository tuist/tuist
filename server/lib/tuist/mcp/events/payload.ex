defmodule Tuist.MCP.Events.Payload do
  @moduledoc false

  def data("test_case.marked_flaky", %{"test_case_id" => id}, {account, project}) do
    project_data(account, project, %{"test_case_id" => id}, "tests/test-cases/#{id}")
  end

  def data("build.failed", %{"build_id" => id, "build_system" => system} = args, {account, project}) do
    path = if system == "bazel", do: "builds/invocations/#{id}", else: "builds/build-runs/#{id}"
    project_data(account, project, failure_context(args, %{"build_id" => id, "build_system" => system}), path)
  end

  def data("test_run.failed", %{"test_run_id" => id} = args, {account, project}) do
    project_data(account, project, failure_context(args, %{"test_run_id" => id}), "tests/test-runs/#{id}")
  end

  def data("ci_job.failed", %{"workflow_job_id" => id, "workflow_run_id" => run_id}, account) do
    %{
      "account_handle" => account,
      "workflow_job_id" => id,
      "workflow_run_id" => run_id,
      "url" => "#{Tuist.Environment.app_url()}/#{account}/runners/runs/#{run_id}/jobs/#{id}"
    }
  end

  # The entity comes from the symptoms evaluator: untrusted, so it is bounded
  # and typed `untrusted_json` for clients that hand it to a model.
  def data("pulse_symptom.opened", %{"symptom_id" => id, "tier" => tier} = args, account) do
    entity = Map.new(~w(service kind key), &{&1, args |> Map.get(&1) |> to_string() |> String.slice(0, 200)})

    %{
      "account_handle" => account,
      "symptom_id" => id,
      "tier" => tier,
      "untrusted" => %{"type" => "untrusted_json", "value" => entity},
      "url" => "#{Tuist.Environment.app_url()}/#{account}/pulse/symptoms/#{id}"
    }
  end

  defp project_data(account, project, fields, path) do
    Map.merge(fields, %{
      "account_handle" => account,
      "project_handle" => project,
      "url" => "#{Tuist.Environment.app_url()}/#{account}/#{project}/#{path}"
    })
  end

  defp failure_context(args, fields) do
    Map.merge(fields, %{
      "is_ci" => args["is_ci"] == true,
      "git_branch" => Map.get(args, "git_branch") || ""
    })
  end
end
