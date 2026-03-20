defmodule Tuist.Ingestion.Bufferable do
  @moduledoc """
  Makes an Ecto schema bufferable for ClickHouse ingestion.

  When used, it defines `buffer_opts/0` on the schema and generates a
  `Buffer` submodule with `child_spec/1`, `insert/1`, `insert_all/1`,
  and `flush/0`.

  ## Usage

      defmodule MySchema do
        use Ecto.Schema
        use Tuist.Ingestion.Bufferable

        schema "my_table" do
          field :name, :string
          # ...
        end
      end

      # The Buffer submodule is generated automatically:
      MySchema.Buffer.insert(row)
      MySchema.Buffer.insert_all(rows)
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile Tuist.Ingestion.Bufferable
    end
  end

  defmacro __before_compile__(env) do
    parent = env.module

    quote do
      def buffer_opts do
        Tuist.Ingestion.Bufferable.compile_time_prepare(__MODULE__)
      end

      defmodule Buffer do
        @moduledoc false

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

  @doc false
  def compile_time_prepare(schema) do
    all_fields = schema.__schema__(:fields)

    struct_defaults = Map.from_struct(schema.__struct__())

    fields =
      Enum.reject(all_fields, fn field ->
        Map.get(struct_defaults, field) == :database
      end)

    types =
      Enum.map(fields, fn field ->
        type = schema.__schema__(:type, field) || raise "missing type for #{field}"
        Ecto.Adapters.ClickHouse.Schema.remap_type(type, schema, field)
      end)

    encoding_types = Ch.RowBinary.encoding_types(types)

    header =
      fields
      |> Enum.map(&to_string/1)
      |> Ch.RowBinary.encode_names_and_types(types)
      |> IO.iodata_to_binary()

    insert_sql =
      "INSERT INTO #{schema.__schema__(:source)} (#{Enum.join(fields, ", ")}) FORMAT RowBinaryWithNamesAndTypes"

    %{
      fields: fields,
      types: types,
      encoding_types: encoding_types,
      header: header,
      insert_sql: insert_sql,
      insert_opts: [
        command: :insert,
        encode: false,
        source: schema.__schema__(:source),
        cast_params: []
      ]
    }
  end
end
