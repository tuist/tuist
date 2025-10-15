defmodule Tuist.CommandEvents.Buffer do
  @moduledoc false

  alias Tuist.Ingestion.Buffer

  %{
    header: header,
    insert_sql: insert_sql,
    insert_opts: insert_opts,
    fields: fields,
    encoding_types: encoding_types
  } = Tuist.CommandEvents.Event.buffer_opts()

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

  def insert(event) do
    row_binary =
      [Enum.map(unquote(fields), fn field -> Map.fetch!(event, field) end)]
      |> Ch.RowBinary._encode_rows(unquote(encoding_types))
      |> IO.iodata_to_binary()

    :ok = Buffer.insert(__MODULE__, row_binary)
    {:ok, event}
  end

  def flush do
    Buffer.flush(__MODULE__)
  end
end
