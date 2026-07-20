defmodule Tuist.Tests.XcresultProcessing do
  @moduledoc """
  Enqueues Xcode result processing and builds the shared test-run attributes
  used for successful and failed processing results.
  """

  alias Tuist.Tests
  alias Tuist.Tests.Workers.ProcessXcresultWorker

  def enqueue(args) do
    args
    |> ProcessXcresultWorker.new()
    |> Oban.insert()
  end

  def mark_test_run_failed(args) do
    attrs =
      args
      |> base_test_attrs()
      |> Map.merge(%{
        status: "failed_processing",
        duration: 0,
        test_modules: []
      })

    case Tests.create_test(attrs) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def base_test_attrs(args) do
    %{
      id: args["test_run_id"],
      project_id: args["project_id"],
      account_id: args["account_id"],
      is_ci: Map.get(args, "is_ci", false),
      git_branch: Map.get(args, "git_branch"),
      git_commit_sha: Map.get(args, "git_commit_sha"),
      git_ref: Map.get(args, "git_ref"),
      macos_version: Map.get(args, "macos_version"),
      xcode_version: Map.get(args, "xcode_version"),
      model_identifier: Map.get(args, "model_identifier"),
      scheme: Map.get(args, "scheme"),
      ci_run_id: Map.get(args, "ci_run_id"),
      ci_project_handle: Map.get(args, "ci_project_handle"),
      ci_host: Map.get(args, "ci_host"),
      ci_provider: Map.get(args, "ci_provider"),
      build_run_id: Map.get(args, "build_run_id"),
      shard_plan_id: Map.get(args, "shard_plan_id"),
      shard_index: Map.get(args, "shard_index"),
      ran_at: Map.get(args, "ran_at", NaiveDateTime.utc_now())
    }
  end
end
