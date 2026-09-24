defmodule Tuist.Tests.Workers.PublishCoverageWorker do
  @moduledoc """
  Publishes the coverage a client uploaded to object storage for a run it
  processed itself (see `TuistWeb.API.CoverageController`): downloads the
  DEFLATE-compressed file, inflates it to the one-object-per-line form the
  parser writes, and streams it into `Tuist.Tests.Coverage.publish/4` the way
  the xcresult processor does. The object stays in storage as the run's raw
  coverage artifact, under the run's retention.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:test_run_id, :shard_index], states: :incomplete, period: :infinity]

  alias Tuist.Accounts
  alias Tuist.Storage
  alias Tuist.Tests
  alias Tuist.Tests.Coverage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"test_run_id" => test_run_id, "project_id" => project_id, "storage_key" => storage_key} = args
    partial = Map.get(args, "partial", false)
    shard_index = Map.get(args, "shard_index")
    expected_shards = Map.get(args, "expected_shards", 1)

    case Tests.get_test(test_run_id) do
      {:ok, test} ->
        case Accounts.get_account_by_id(Map.get(args, "account_id") || project_account_id(project_id)) do
          {:ok, account} -> publish(test, account, storage_key, partial, shard_index, expected_shards)
          {:error, :not_found} -> :ok
        end

      {:error, :not_found} ->
        Logger.warning("Coverage for test run #{test_run_id} arrived before the run; retrying")
        {:snooze, 30}
    end
  end

  defp publish(test, account, storage_key, partial, shard_index, expected_shards) do
    unique = System.unique_integer([:positive])
    compressed = Path.join(System.tmp_dir!(), "coverage_#{unique}.deflate")
    inflated = Path.join(System.tmp_dir!(), "coverage_#{unique}.ndjson")

    try do
      with {:ok, _} <- Storage.download_to_file(storage_key, compressed, account),
           :ok <- inflate(compressed, inflated) do
        Coverage.publish(
          test,
          Coverage.rows(test.project_id, %{path: inflated, partial: partial}),
          shard_index,
          expected_shards
        )
      end
    after
      File.rm(compressed)
      File.rm(inflated)
    end
  end

  # Raw DEFLATE (what the CLI's `NSData.compressed(using: .zlib)` and the
  # Compression framework produce), inflated a chunk at a time so the file
  # never sits in memory whole.
  defp inflate(source, destination) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, -15)

    try do
      File.open!(destination, [:write, :binary], fn output ->
        source
        |> File.stream!(65_536)
        |> Enum.each(fn chunk -> write_inflated(z, :zlib.safeInflate(z, chunk), output) end)
      end)

      :ok
    rescue
      error in ErlangError -> {:error, {:invalid_deflate, error}}
    after
      :zlib.close(z)
    end
  end

  defp write_inflated(z, {:continue, output_chunk}, output) do
    IO.binwrite(output, output_chunk)
    write_inflated(z, :zlib.safeInflate(z, ""), output)
  end

  defp write_inflated(_z, {:finished, output_chunk}, output) do
    IO.binwrite(output, output_chunk)
  end

  defp project_account_id(project_id) do
    case Tuist.Projects.get_project_by_id(project_id) do
      nil -> nil
      project -> project.account_id
    end
  end
end
