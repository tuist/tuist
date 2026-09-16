defmodule Atlas.TuistServer do
  @moduledoc """
  Client for the Tuist server's internal Atlas API.

  Atlas runs in its own Kubernetes cluster and authenticates to the Tuist server
  with a projected ServiceAccount token (audience `tuist-server`), which the
  Tuist server verifies offline via pinned JWKS (`InternalAtlasAuthPlug`). This
  module wraps the read-only database endpoints under `/api/internal/atlas/db`
  — the Tuist side runs every query through its `/ops/db` read-only engine
  (SELECT/WITH/EXPLAIN/SHOW grammar gate + `BEGIN READ ONLY` + statement
  timeout), so this client never touches the database directly.

  Each call reads the token fresh from disk because the kubelet rotates the
  projected token file in place.
  """

  require Logger

  @default_receive_timeout 30_000

  @doc """
  Whether the internal Tuist server API is reachable from this environment
  (base URL configured and a token available). False in dev/test, where the
  projected token file is absent.
  """
  def configured?(opts \\ []) do
    client = client(opts)
    present?(client.base_url) and token_available?(client)
  end

  @doc """
  Run a read-only SQL query. `:limit` caps returned rows (Tuist clamps it).
  Returns `{:ok, %{"columns" => ..., "rows" => ..., "num_rows" => ..., "truncated" => ...}}`
  where `rows` are objects keyed by column name.
  """
  def query(sql, opts \\ []) when is_binary(sql) do
    body =
      case Keyword.get(opts, :limit) do
        limit when is_integer(limit) and limit > 0 -> %{"query" => sql, "limit" => limit}
        _ -> %{"query" => sql}
      end

    request(:post, "/api/internal/atlas/db/query", [json: body], opts)
  end

  @doc "List app-owned tables with size + estimated-row stats."
  def list_tables(opts \\ []) do
    request(:get, "/api/internal/atlas/db/tables", [], opts)
  end

  @doc "Describe a single table's columns. `schema` defaults to `\"public\"`."
  def describe_table(table, schema \\ "public", opts \\ []) when is_binary(table) do
    path = "/api/internal/atlas/db/tables/#{encode_segment(schema)}/#{encode_segment(table)}"
    request(:get, path, [], opts)
  end

  @doc """
  Run a bounded read-only ClickHouse query. Only `SELECT`/`WITH` statements are
  allowed; the Tuist side clamps `:limit` and enforces scan/memory/time limits.

  `:params` is a map of named ClickHouse parameters (e.g.
  `%{"project_ids" => [1, 2]}` for a `{project_ids:Array(Int64)}` placeholder).

  Returns `{:ok, %{"columns" => ..., "rows" => ..., "num_rows" => ..., "truncated" => ...}}`
  where `rows` are objects keyed by column name.
  """
  def clickhouse_query(sql, opts \\ []) when is_binary(sql) do
    body =
      %{"query" => sql}
      |> maybe_put("limit", clickhouse_limit(opts))
      |> maybe_put("params", clickhouse_params(opts))

    request(:post, "/api/internal/atlas/clickhouse/query", [json: body], opts)
  end

  @doc "List tables in the Tuist ClickHouse application database with size + row stats."
  def clickhouse_list_tables(opts \\ []) do
    request(:get, "/api/internal/atlas/clickhouse/tables", [], opts)
  end

  @doc "Describe a single ClickHouse table's columns within `database`."
  def clickhouse_describe_table(table, database, opts \\ []) when is_binary(table) and is_binary(database) do
    path = "/api/internal/atlas/clickhouse/tables/#{encode_segment(database)}/#{encode_segment(table)}"
    request(:get, path, [], opts)
  end

  defp clickhouse_limit(opts) do
    case Keyword.get(opts, :limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      _ -> nil
    end
  end

  defp clickhouse_params(opts) do
    case Keyword.get(opts, :params) do
      params when is_map(params) and map_size(params) > 0 -> params
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Percent-encode a single path segment. Plain `URI.encode/1` leaves `/` and `.`
  # intact, so a schema/table value like `public/../admin` could redirect the
  # request to a different internal endpoint while still carrying the SA token.
  # Encoding everything outside the RFC 3986 unreserved set keeps the value a
  # single, inert path segment.
  defp encode_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp request(method, path, req_opts, client_opts) do
    client = client(client_opts)

    with {:ok, token} <- fetch_token(client) do
      req =
        Req.new(
          [
            method: method,
            url: client.base_url <> path,
            auth: {:bearer, token},
            receive_timeout: client.receive_timeout,
            headers: [{"accept", "application/json"}]
          ] ++ req_opts
        )

      case client.request.(req) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %Req.Response{status: status, body: %{"error" => error}}} ->
          Logger.warning("Tuist internal API #{method} #{path} failed: status=#{status}")
          {:error, to_string(error)}

        {:ok, %Req.Response{status: status}} ->
          Logger.warning("Tuist internal API #{method} #{path} failed: status=#{status}")
          {:error, "Tuist server returned status #{status}."}

        {:error, reason} ->
          Logger.warning("Tuist internal API #{method} #{path} transport error: #{inspect(reason)}")
          {:error, "Could not reach the Tuist server."}
      end
    end
  end

  defp fetch_token(client) do
    cond do
      present?(client.token) ->
        {:ok, client.token}

      present?(client.token_path) ->
        read_token_file(client.token_path)

      true ->
        {:error, "The Tuist server internal API is not configured for this environment."}
    end
  end

  defp read_token_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> {:error, "Tuist server token file is empty."}
          token -> {:ok, token}
        end

      {:error, reason} ->
        {:error, "Could not read Tuist server token: #{:file.format_error(reason)}"}
    end
  end

  defp token_available?(client) do
    present?(client.token) or (present?(client.token_path) and File.exists?(client.token_path))
  end

  defp client(opts) do
    config = config()

    %{
      base_url: base_url(configured_option(opts, config, :base_url)),
      token: configured_option(opts, config, :token),
      token_path: configured_option(opts, config, :token_path),
      receive_timeout: receive_timeout(configured_option(opts, config, :receive_timeout)),
      request: Keyword.get(opts, :request, &Req.request/1)
    }
  end

  defp configured_option(opts, config, key) do
    if Keyword.has_key?(opts, key), do: Keyword.get(opts, key), else: Keyword.get(config, key)
  end

  defp base_url(value) when is_binary(value) and value != "", do: String.trim_trailing(value, "/")
  defp base_url(_value), do: nil

  defp receive_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp receive_timeout(_timeout), do: @default_receive_timeout

  defp present?(value), do: is_binary(value) and value != ""

  defp config, do: Application.get_env(:atlas, :tuist_server, [])
end
