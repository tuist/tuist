defmodule Tuist.Xcode.XcodeProject.Buffer do
  @moduledoc false

  alias Tuist.Ingestion.Buffer

  %{
    header: header,
    insert_sql: insert_sql,
    insert_opts: insert_opts,
    fields: fields,
    encoding_types: encoding_types
  } = Tuist.Xcode.XcodeProject.buffer_opts()

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

  def insert(xcode_project_or_projects) do
    :ok = Buffer.insert(__MODULE__, encode(xcode_project_or_projects))
    {:ok, xcode_project_or_projects}
  end

  def flush do
    Buffer.flush(__MODULE__)
  end

  defp encode(xcode_projects) when is_list(xcode_projects) do
    xcode_projects
    |> Enum.map(fn xcode_project ->
      Enum.map(unquote(fields), fn field -> Map.fetch!(xcode_project, field) end)
    end)
    |> Ch.RowBinary._encode_rows(unquote(encoding_types))
    |> IO.iodata_to_binary()
  end

  defp encode(xcode_project) do
    encode([xcode_project])
  end
end
