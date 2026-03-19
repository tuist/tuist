defmodule Tuist.Ingestion.SchemaBuffer do
  @moduledoc """
  Generates a buffer module for a ClickHouse schema.

  The schema must `use Tuist.Ingestion.Bufferable`.

  ## Example

      defmodule Tuist.Tests.TestCaseRun.Buffer do
        use Tuist.Ingestion.SchemaBuffer, schema: Tuist.Tests.TestCaseRun
      end

  This generates `child_spec/1`, `insert/1`, `insert_all/1`, and `flush/0`.
  """

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      alias Tuist.Ingestion.Buffer

      %{
        header: header,
        insert_sql: insert_sql,
        insert_opts: insert_opts,
        fields: fields,
        encoding_types: encoding_types
      } = unquote(schema).buffer_opts()

      @__header header
      @__insert_sql insert_sql
      @__insert_opts insert_opts
      @__fields fields
      @__encoding_types encoding_types

      def child_spec(opts) do
        opts =
          Keyword.merge(opts,
            name: __MODULE__,
            header: @__header,
            insert_sql: @__insert_sql,
            insert_opts: @__insert_opts
          )

        Buffer.child_spec(opts)
      end

      def insert(row) do
        row_binary =
          [Enum.map(@__fields, fn field -> Map.fetch!(row, field) end)]
          |> Ch.RowBinary._encode_rows(@__encoding_types)
          |> IO.iodata_to_binary()

        :ok = Buffer.insert(__MODULE__, row_binary)
        {:ok, row}
      end

      def insert_all([]), do: {0, nil}

      def insert_all(rows) do
        row_binary =
          rows
          |> Enum.map(fn row ->
            Enum.map(@__fields, fn field -> Map.fetch!(row, field) end)
          end)
          |> Ch.RowBinary._encode_rows(@__encoding_types)
          |> IO.iodata_to_binary()

        :ok = Buffer.insert(__MODULE__, row_binary)
        {length(rows), nil}
      end

      def flush do
        Buffer.flush(__MODULE__)
      end
    end
  end
end
