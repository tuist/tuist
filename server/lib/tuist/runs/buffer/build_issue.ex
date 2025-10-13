defmodule Tuist.Runs.BuildIssue.Buffer do
  @moduledoc false

  alias Tuist.Ingestion.Buffer
  alias Tuist.Runs.BuildIssue

  %{
    header: header,
    insert_sql: insert_sql,
    insert_opts: insert_opts,
    fields: fields,
    encoding_types: encoding_types
  } = BuildIssue.buffer_opts()

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

  def insert(build_issue_or_issues) do
    :ok = Buffer.insert(__MODULE__, encode(build_issue_or_issues))
    {:ok, build_issue_or_issues}
  end

  def flush do
    Buffer.flush(__MODULE__)
  end

  defp encode(build_issues) when is_list(build_issues) do
    build_issues
    |> Enum.map(fn build_issue ->
      Enum.map(unquote(fields), fn field -> Map.fetch!(build_issue, field) end)
    end)
    |> Ch.RowBinary._encode_rows(unquote(Macro.escape(encoding_types)))
    |> IO.iodata_to_binary()
  end

  defp encode(build_issue) do
    encode([build_issue])
  end
end
