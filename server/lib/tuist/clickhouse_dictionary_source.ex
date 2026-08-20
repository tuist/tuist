defmodule Tuist.ClickHouseDictionarySource do
  @moduledoc """
  Builds the `SOURCE` clause for dictionaries that read a table living in the
  same ClickHouse instance the repo is connected to.

  A `CLICKHOUSE` dictionary source is resolved by the ClickHouse server, not by
  the client that issued the `CREATE DICTIONARY`, so the server authenticates it
  separately. With no user named in the source it falls back to `default` with
  an empty password, which only succeeds on a server that has no password set.
  Installs following the published self-hosted Compose file do set one, so every
  backfill dictionary died there with `AUTHENTICATION_FAILED`. Name the
  credentials the repo already connects with instead.

  Host and port stay out of the clause on purpose. Omitted, they default to the
  server's own address and native port, which is what a same-instance lookup
  wants; the repo's port is the HTTP one the source would not dial anyway.
  """

  def local_table(repo, table) do
    config = repo.config()

    "CLICKHOUSE(TABLE #{literal(table)}#{credentials(config[:username], config[:password])})"
  end

  defp credentials(nil, _password), do: ""

  defp credentials(username, password) do
    " USER #{literal(username)} PASSWORD #{literal(password || "")}"
  end

  defp literal(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("'", "\\'")

    "'" <> escaped <> "'"
  end
end
