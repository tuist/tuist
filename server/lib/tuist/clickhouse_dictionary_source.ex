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

  Issue the resulting statement with `query_opts/0` to suppress application SQL
  logging. ClickHouse masks the parsed dictionary source password in its query log.
  """

  @doc """
  Query options for a statement rendered with `local_table/2` or `local_query/2`.

  `log: false` keeps the credential out of the application log. Leave server
  query logging settings alone: managed ClickHouse forbids changing
  `log_queries`, so overriding it prevents dictionary creation and blocks deploys.
  Server-side password masking relies on a successfully parsed statement; callers
  must use valid dictionary DDL and the escaped source clauses built here.
  """
  def query_opts, do: [log: false]

  def local_table(repo, table) do
    config = repo.config()

    "CLICKHOUSE(TABLE #{literal(table)}#{credentials(config[:username], config[:password])})"
  end

  @doc """
  Like `local_table/2`, but the dictionary holds the result of `query` rather
  than a whole table. A backfill that only needs a fraction of a large table's
  rows keeps its dictionary, and the memory it pins on the server while the
  backfill runs, proportionally smaller.

  Tables in `query` have to be qualified with their database. The server runs
  the query when it loads the dictionary, outside the repo's default database,
  and a `DB` setting on the source does not apply to `QUERY` sources.
  """
  def local_query(repo, query) do
    config = repo.config()

    "CLICKHOUSE(QUERY #{literal(query)}#{credentials(config[:username], config[:password])})"
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
