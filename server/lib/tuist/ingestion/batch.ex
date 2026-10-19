defmodule Tuist.Ingestion.Batch do
  @moduledoc """
  A request-local, bounded batch for facts that must reach the ingestion writer
  before a report is published. Outside a batch, existing schema buffers are used.
  """

  alias Tuist.IngestRepo

  @key {__MODULE__, :batch}
  @max_bytes 8 * 1024 * 1024
  @report_fact_sources ~w(test_case_runs test_module_runs test_suite_runs test_run_errors test_run_destinations test_run_stress_candidates)

  def run(identity, fun) do
    if Process.get(@key), do: raise(ArgumentError, "ingestion batches cannot be nested")
    Process.put(@key, %{identity: identity, tables: %{}})

    try do
      result = fun.()
      Enum.each(Process.get(@key).tables, fn {schema, _} -> flush(schema) end)
      result
    after
      Process.delete(@key)
    end
  end

  def insert(schema, row) do
    if Process.get(@key) do
      insert_all(schema, [row])
      {:ok, row}
    else
      buffer = Module.concat(schema, Buffer)
      buffer.insert(row)
    end
  end

  def insert_all(_schema, []), do: {0, nil}

  def insert_all(schema, rows) do
    if Process.get(@key) do
      Enum.each(rows, &stage(schema, [&1]))
      {length(rows), nil}
    else
      buffer = Module.concat(schema, Buffer)
      buffer.insert_all(rows)
    end
  end

  def uuid(discriminator) do
    case Process.get(@key) do
      nil ->
        UUIDv7.generate()

      %{identity: identity} ->
        payload = :erlang.term_to_binary({identity, discriminator}, [:deterministic])
        <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha256, payload)
        Ecto.UUID.cast!(<<a::48, 8::4, b::12, 2::2, c::62>>)
    end
  end

  defp stage(schema, rows) do
    batch = Process.get(@key)
    table = Map.get_lazy(batch.tables, schema, fn -> %{opts: buffer_opts(schema), chunks: [], bytes: 0} end)
    %{fields: fields, encoding_types: types} = table.opts
    rows = if :shard_report_id in fields, do: Enum.map(rows, &Map.put(&1, :shard_report_id, uuid(:report))), else: rows

    binary =
      rows
      |> Enum.map(fn row -> Enum.map(fields, &Map.fetch!(row, &1)) end)
      |> Ch.RowBinary._encode_rows(types)
      |> IO.iodata_to_binary()

    table = %{table | chunks: [binary | table.chunks], bytes: table.bytes + byte_size(binary)}
    Process.put(@key, put_in(batch, [:tables, schema], table))
    if table.bytes >= @max_bytes, do: flush(schema)
  end

  defp buffer_opts(schema) do
    opts = schema.buffer_opts()

    if schema.__schema__(:source) in @report_fact_sources do
      fields = opts.fields ++ [:shard_report_id]
      types = opts.types ++ ["Nullable(UUID)"]

      %{
        opts
        | fields: fields,
          types: types,
          encoding_types: Ch.RowBinary.encoding_types(types),
          header: IO.iodata_to_binary(Ch.RowBinary.encode_names_and_types(Enum.map(fields, &to_string/1), types)),
          insert_sql:
            "INSERT INTO #{schema.__schema__(:source)} (#{Enum.join(fields, ", ")}) FORMAT RowBinaryWithNamesAndTypes"
      }
    else
      opts
    end
  end

  def flush(schema) do
    case Process.get(@key) do
      nil ->
        buffer = Module.concat(schema, Buffer)
        buffer.flush()

      %{tables: tables} = batch ->
        case tables[schema] do
          %{chunks: [_ | _] = chunks, opts: opts} = table ->
            {:ok, _} = IngestRepo.query(opts.insert_sql, [opts.header | Enum.reverse(chunks)], opts.insert_opts)
            Process.put(@key, put_in(batch, [:tables, schema], %{table | chunks: [], bytes: 0}))
            :ok

          _ ->
            :ok
        end
    end
  end
end
