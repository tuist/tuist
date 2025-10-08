defmodule Tuist.Runs.BuildTargetBuffer do
  @moduledoc false

  alias Tuist.Ingestion.Buffer
  alias Tuist.Runs.BuildTarget

  %{
    header: header,
    insert_sql: insert_sql,
    insert_opts: insert_opts,
    fields: fields,
    encoding_types: encoding_types
  } = BuildTarget.buffer_opts()

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

  def insert(build_target_or_targets) do
    :ok = Buffer.insert(__MODULE__, encode(build_target_or_targets))
    {:ok, build_target_or_targets}
  end

  def flush do
    Buffer.flush(__MODULE__)
  end

  defp encode(build_targets) when is_list(build_targets) do
    build_targets
    |> Enum.map(fn build_target ->
      Enum.map(unquote(fields), fn field -> Map.fetch!(build_target, field) end)
    end)
    |> Ch.RowBinary._encode_rows(unquote(Macro.escape(encoding_types)))
    |> IO.iodata_to_binary()
  end

  defp encode(build_target) do
    encode([build_target])
  end
end
