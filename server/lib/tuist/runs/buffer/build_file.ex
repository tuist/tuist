defmodule Tuist.Runs.BuildFile.Buffer do
  @moduledoc false

  alias Tuist.Ingestion.Buffer
  alias Tuist.Runs.BuildFile

  %{
    header: header,
    insert_sql: insert_sql,
    insert_opts: insert_opts,
    fields: fields,
    encoding_types: encoding_types
  } = BuildFile.buffer_opts()

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

  def insert(build_file_or_files) do
    :ok = Buffer.insert(__MODULE__, encode(build_file_or_files))
    {:ok, build_file_or_files}
  end

  def flush do
    Buffer.flush(__MODULE__)
  end

  defp encode(build_files) when is_list(build_files) do
    build_files
    |> Enum.map(fn build_file ->
      Enum.map(unquote(fields), fn field -> Map.fetch!(build_file, field) end)
    end)
    |> Ch.RowBinary._encode_rows(unquote(Macro.escape(encoding_types)))
    |> IO.iodata_to_binary()
  end

  defp encode(build_file) do
    encode([build_file])
  end
end
