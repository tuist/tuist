defmodule Tuist.Cache.CASEvent.Buffer do
  @moduledoc false

  alias Tuist.Cache.CASEvent
  alias Tuist.Ingestion.Buffer

  %{
    header: header,
    insert_sql: insert_sql,
    insert_opts: insert_opts,
    fields: fields,
    encoding_types: encoding_types
  } = CASEvent.buffer_opts()

  @encoding_types encoding_types

  def child_spec(opts) do
    opts =
      Keyword.merge(opts,
        name: __MODULE__,
        header: unquote(header),
        insert_sql: unquote(insert_sql),
        insert_opts: unquote(insert_opts)
      )

    Buffer.child_spec(opts)
  end

  def insert(row) do
    row_binary =
      [Enum.map(unquote(fields), fn field -> Map.fetch!(row, field) end)]
      |> Ch.RowBinary._encode_rows(@encoding_types)
      |> IO.iodata_to_binary()

    :ok = Buffer.insert(__MODULE__, row_binary)
    {:ok, row}
  end

  def insert_all([]), do: {0, nil}

  def insert_all(rows) do
    row_binary =
      Enum.map(rows, fn row ->
        Enum.map(unquote(fields), fn field -> Map.fetch!(row, field) end)
      end)
      |> Ch.RowBinary._encode_rows(@encoding_types)
      |> IO.iodata_to_binary()

    :ok = Buffer.insert(__MODULE__, row_binary)
    {length(rows), nil}
  end

  def flush do
    Buffer.flush(__MODULE__)
  end
end
