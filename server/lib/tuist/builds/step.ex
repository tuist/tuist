defmodule Tuist.Builds.Step do
  @moduledoc """
  Recorded leaf operations from a build activity log, shared by build analytics views.
  """
  use Ecto.Schema

  alias Tuist.Ingestion.Bufferable
  alias Tuist.IngestRepo

  @batch_bytes 8 * 1024 * 1024
  @batch_rows 1000

  @primary_key false
  schema "build_steps" do
    field :build_run_id, Ecto.UUID
    field :event_id, Ch, type: "UInt64"
    field :title, :string
    field :target, :string
    field :project, :string
    field :category, :string
    field :start_ms, Ch, type: "Float64"
    field :duration_ms, Ch, type: "Float64"
    field :status, :string
    field :log, :string, default: ""
    field :log_truncated, :boolean, default: false
    field :inserted_at, :utc_datetime
  end

  # Each worker streams bounded writes through the repo pool, without serializing
  # log-heavy builds through a node-wide GenServer. Failed writes fail the job;
  # stable step IDs make Oban retries idempotent.
  def insert_all(entries) do
    opts = Bufferable.compile_time_prepare(__MODULE__)

    entries
    |> Stream.map(fn entry ->
      values = Enum.map(opts.fields, &Map.fetch!(entry, &1))
      [values] |> Ch.RowBinary._encode_rows(opts.encoding_types) |> IO.iodata_to_binary()
    end)
    |> Stream.chunk_while(
      {[], 0, 0},
      fn row, {rows, bytes, count} ->
        if count > 0 and (bytes + byte_size(row) > @batch_bytes or count == @batch_rows) do
          {:cont, Enum.reverse(rows), {[row], byte_size(row), 1}}
        else
          {:cont, {[row | rows], bytes + byte_size(row), count + 1}}
        end
      end,
      fn
        {[], _, _} -> {:cont, []}
        {rows, _, _} -> {:cont, Enum.reverse(rows), []}
      end
    )
    |> Enum.each(fn rows -> IngestRepo.query!(opts.insert_sql, [opts.header | rows], opts.insert_opts) end)
  end
end
