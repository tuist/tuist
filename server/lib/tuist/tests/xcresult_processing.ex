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
      ran_at: args |> Map.get("ran_at") |> deserialize_ran_at()
    }
  end

  defp deserialize_ran_at(nil), do: NaiveDateTime.utc_now()
  defp deserialize_ran_at(%NaiveDateTime{} = ran_at), do: ran_at
  defp deserialize_ran_at(%DateTime{} = ran_at), do: DateTime.to_naive(ran_at)

  defp deserialize_ran_at(ran_at) when is_binary(ran_at) do
    case NaiveDateTime.from_iso8601(ran_at) do
      {:ok, naive_datetime} ->
        naive_datetime

      {:error, _reason} ->
        ran_at |> DateTime.from_iso8601() |> deserialize_datetime_result(ran_at)
    end
  end

  defp deserialize_datetime_result({:ok, datetime, _offset}, _ran_at), do: DateTime.to_naive(datetime)

  defp deserialize_datetime_result({:error, reason}, ran_at) do
    raise ArgumentError, "invalid Xcode result processing ran_at #{inspect(ran_at)}: #{inspect(reason)}"
  end
end
