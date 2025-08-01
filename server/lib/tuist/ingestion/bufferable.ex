defmodule Tuist.Ingestion.Bufferable do
  @moduledoc """
  A module that can be used to make an Ecto schema bufferable for ClickHouse ingestion.

  When used, it provides compile-time preparation of buffer parameters for efficient
  RowBinaryWithNamesAndTypes format ingestion.

  ## Usage

      defmodule MySchema do
        use Tuist.Ingestion.Bufferable
        # ... rest of your schema definition
      end

      # Access the prepared buffer options
      MySchema.buffer_opts()
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile Tuist.Ingestion.Bufferable
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns the compile-time prepared buffer options for this schema.
      """
      def buffer_opts do
        Tuist.Ingestion.Bufferable.compile_time_prepare(__MODULE__)
      end
    end
  end

  @doc """
  Prepares a few buffer parameters for a given schema at compile time.

  The `RowBinaryWithNamesAndTypes` format expects a header row with the column names that we can generate before the runtime, as well as the actual SQL query to insert the data.
  """
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

        type
        |> Ecto.Type.type()
        |> Ecto.Adapters.ClickHouse.Schema.remap_type(schema, field)
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
