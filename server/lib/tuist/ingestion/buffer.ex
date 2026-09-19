defmodule Tuist.Ingestion.Buffer do
  @moduledoc """
  Server-side alias for `TuistCommon.Ingestion.Buffer`.

  The runtime buffer used to live here and now lives in `tuist_common`
  so any Elixir service that ingests into ClickHouse can share it.
  This module stays as a thin delegator so a handful of direct callers
  keep working without a rename, and injects the `:tuist` +
  `Tuist.IngestRepo` defaults so tests that build a buffer inline do
  not have to spell them out.
  """

  alias TuistCommon.Ingestion.Buffer

  def start_link(opts) do
    opts
    |> with_defaults()
    |> Buffer.start_link()
  end

  def child_spec(opts) do
    opts
    |> with_defaults()
    |> Buffer.child_spec()
  end

  defdelegate insert!(server, row_binary), to: Buffer
  defdelegate flush(server), to: Buffer

  defp with_defaults(opts) do
    opts
    |> Keyword.put_new(:otp_app, :tuist)
    |> Keyword.put_new(:repo, Tuist.IngestRepo)
  end
end
