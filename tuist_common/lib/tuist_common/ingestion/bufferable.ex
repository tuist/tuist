defmodule TuistCommon.Ingestion.Bufferable do
  @moduledoc """
  Makes an Ecto schema bufferable for ClickHouse ingestion.

  When used, defines `buffer_opts/0` on the schema and generates a
  `Buffer` submodule with `child_spec/1`, `insert/1`, `insert_all/1`,
  and `flush/0` that fan into `TuistCommon.Ingestion.Buffer`.

  ## Usage

      defmodule MySchema do
        use Ecto.Schema
        use TuistCommon.Ingestion.Bufferable,
          otp_app: :my_app,
          repo: MyApp.IngestRepo

        schema "my_table" do
          field :name, :string
          # ...
        end
      end

      # The generated Buffer submodule:
      MySchema.Buffer.insert(row)
      MySchema.Buffer.insert_all(rows)

  `otp_app` and `repo` are required. Defaults for `flush_interval_ms`,
  `max_buffer_size`, and `sync_writes` are read from
  `Application.get_env(otp_app, repo, [])`; a runtime
  `Application.get_env(otp_app, TuistCommon.Ingestion.Bufferable, [])`
  flag `write_through_repo: true` routes writes straight through the
  repo, which the test suite uses to keep assertions inline.
  """

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    repo = Keyword.fetch!(opts, :repo)

    quote do
      @before_compile TuistCommon.Ingestion.Bufferable
      @tuist_common_ingestion_otp_app unquote(otp_app)
      @tuist_common_ingestion_repo unquote(repo)
    end
  end

  defmacro __before_compile__(env) do
    parent = env.module
    otp_app = Module.get_attribute(env.module, :tuist_common_ingestion_otp_app)
    repo = Module.get_attribute(env.module, :tuist_common_ingestion_repo)

    quote do
      def buffer_opts do
        TuistCommon.Ingestion.Bufferable.compile_time_prepare(__MODULE__)
      end

      defmodule Buffer do
        @moduledoc false
        use TuistCommon.Ingestion.Bufferable.BufferImpl,
          parent: unquote(parent),
          otp_app: unquote(otp_app),
          repo: unquote(repo)
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
