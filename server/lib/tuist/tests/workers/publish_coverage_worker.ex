defmodule Tuist.Tests.Workers.PublishCoverageWorker do
  @moduledoc """
  Publishes the coverage a client uploaded to object storage for a run it
  processed itself (see `TuistWeb.API.CoverageController`): downloads the
  DEFLATE-compressed file, inflates it to the one-object-per-line form the
  parser writes, and streams it into `Tuist.Tests.Coverage.publish/4` the way
  the xcresult processor does. The object stays in storage as the run's raw
  coverage artifact, under the run's retention.

  An upload that inflates past `Tuist.Environment.coverage_max_inflated_bytes/0`,
  was cut off, or is not DEFLATE-compressed NDJSON is cancelled rather than
  retried, since another attempt reads the same object. A run that has not
  appeared an hour after the job was enqueued is given up on.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:test_run_id, :shard_index], states: :incomplete, period: :infinity]

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Storage
  alias Tuist.Tests
  alias Tuist.Tests.Coverage

  require Logger

  @run_wait_seconds 3600

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, inserted_at: inserted_at}) do
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
        if DateTime.diff(DateTime.utc_now(), inserted_at) > @run_wait_seconds do
          Logger.warning("Coverage for test run #{test_run_id} never found its run; giving up")
          {:cancel, :test_run_not_found}
        else
          Logger.warning("Coverage for test run #{test_run_id} arrived before the run; retrying")
          {:snooze, 30}
        end
    end
  end

  defp publish(test, account, storage_key, partial, shard_index, expected_shards) do
    unique = System.unique_integer([:positive])
    compressed = Path.join(System.tmp_dir!(), "coverage_#{unique}.deflate")
    inflated = Path.join(System.tmp_dir!(), "coverage_#{unique}.ndjson")

    try do
      with {:ok, _} <- Storage.download_to_file(storage_key, compressed, account),
           :ok <- inflate(compressed, inflated, Environment.coverage_max_inflated_bytes()) do
        Coverage.publish(
          test,
          Coverage.rows(test.project_id, %{path: inflated, partial: partial}),
          shard_index,
          expected_shards
        )
      end
    rescue
      error in JSON.DecodeError -> {:cancel, {:invalid_coverage, error}}
    after
      File.rm(compressed)
      File.rm(inflated)
    end
  end

  # Raw DEFLATE (what the CLI's `NSData.compressed(using: .zlib)` and the
  # Compression framework produce), inflated a chunk at a time so the file
  # never sits in memory whole, and never grows past `limit` on disk.
  defp inflate(source, destination, limit) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, -15)

    try do
      inflated =
        File.open!(destination, [:write, :binary], fn output ->
          source
          |> File.stream!(65_536)
          |> Enum.reduce_while(0, fn chunk, size ->
            case write_inflated(z, :zlib.safeInflate(z, chunk), output, size, limit) do
              :too_large -> {:halt, :too_large}
              size -> {:cont, size}
            end
          end)
        end)

      if inflated == :too_large, do: {:cancel, :coverage_too_large}, else: finish_inflate(z)
    rescue
      error in ErlangError -> {:cancel, {:invalid_coverage, error}}
    after
      :zlib.close(z)
    end
  end

  # safeInflate reports `:finished` once it consumed its input, whether or not
  # the stream ended; inflateEnd is what fails on a stream that was cut off.
  defp finish_inflate(z) do
    :zlib.inflateEnd(z)
    :ok
  rescue
    ErlangError -> {:cancel, :truncated_coverage}
  end

  defp write_inflated(z, {status, output_chunk}, output, size, limit) do
    size = size + IO.iodata_length(output_chunk)

    cond do
      size > limit ->
        :too_large

      status == :continue ->
        IO.binwrite(output, output_chunk)
        write_inflated(z, :zlib.safeInflate(z, []), output, size, limit)

      true ->
        IO.binwrite(output, output_chunk)
        size
    end
  end

  defp project_account_id(project_id) do
    case Tuist.Projects.get_project_by_id(project_id) do
      nil -> nil
      project -> project.account_id
    end
  end
end
