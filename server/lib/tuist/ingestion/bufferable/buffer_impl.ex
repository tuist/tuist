defmodule Tuist.Ingestion.Bufferable.BufferImpl do
  @moduledoc false

  defmacro __using__(opts) do
    parent = Keyword.fetch!(opts, :parent)

    quote do
      alias Tuist.Ingestion.Buffer

      @parent unquote(parent)

      defp opts do
        case :persistent_term.get({__MODULE__, :opts}, nil) do
          nil ->
            computed = Tuist.Ingestion.Bufferable.compile_time_prepare(@parent)
            :persistent_term.put({__MODULE__, :opts}, computed)
            computed

          cached ->
            cached
        end
      end

      def child_spec(child_opts) do
        %{header: header, insert_sql: insert_sql, insert_opts: insert_opts} = opts()

        child_opts =
          Keyword.merge(child_opts,
            name: __MODULE__,
            header: header,
            insert_sql: insert_sql,
            insert_opts: insert_opts
          )

        Buffer.child_spec(child_opts)
      end

      def insert(row) do
        %{fields: fields, encoding_types: encoding_types} = opts()

        row_binary =
          [Enum.map(fields, fn field -> Map.fetch!(row, field) end)]
          |> Ch.RowBinary._encode_rows(encoding_types)
          |> IO.iodata_to_binary()

        :ok = Buffer.insert(__MODULE__, row_binary)
        {:ok, row}
      end

      def insert_all([]), do: {0, nil}

      def insert_all(rows) do
        %{fields: fields, encoding_types: encoding_types} = opts()

        row_binary =
          rows
          |> Enum.map(fn row ->
            Enum.map(fields, fn field -> Map.fetch!(row, field) end)
          end)
          |> Ch.RowBinary._encode_rows(encoding_types)
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
