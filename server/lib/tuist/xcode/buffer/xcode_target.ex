defmodule Tuist.Xcode.XcodeTarget.Buffer do
  @moduledoc false

  alias Tuist.Ingestion.Buffer

  %{
    header: header,
    insert_sql: insert_sql,
    insert_opts: insert_opts,
    fields: fields,
    encoding_types: encoding_types
  } = Tuist.Xcode.XcodeTarget.buffer_opts()

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

  def insert(xcode_target_or_targets) do
    :ok = Buffer.insert(__MODULE__, encode(xcode_target_or_targets))
    {:ok, xcode_target_or_targets}
  end

  def flush do
    Buffer.flush(__MODULE__)
  end

  defp encode(xcode_targets) when is_list(xcode_targets) do
    xcode_targets
    |> Enum.map(fn xcode_target ->
      Enum.map(unquote(fields), fn field -> Map.fetch!(xcode_target, field) end)
    end)
    |> Ch.RowBinary._encode_rows(unquote(Macro.escape(encoding_types)))
    |> IO.iodata_to_binary()
  end

  defp encode(xcode_target) do
    encode([xcode_target])
  end
end
