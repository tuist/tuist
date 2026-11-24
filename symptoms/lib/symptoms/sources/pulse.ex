defmodule Symptoms.Sources.Pulse do
  @moduledoc """
  HTTP SQL client for Pulse, shaped like the server's (`Tuist.Pulse.request/3`
  and `Tuist.Pulse.SQL.sql/2`): `GET /v1/sql?sql=...` against the `public`
  database (`x-pulse-db-name: public`), basic auth with a read-only token, no
  retries, an 8 MiB response bound and a row bound.

  SQL is authored in the source modules, never taken from input. Values are
  interpolated only through `literal/1` (quotes doubled; Pulse treats
  backslashes literally) or as integers (`timestamp/1`).

  Configuration, from `config :symptoms, #{inspect(__MODULE__)}` (set from the
  environment in `config/runtime.exs`), then the `:pulse` option of a call:

  - `:base_url` (`SYMPTOMS_PULSE_URL`)
  - `:user` (`SYMPTOMS_PULSE_USER`, default `dashboard`) and `:token`
    (`SYMPTOMS_PULSE_TOKEN`): the read-only identity
  - `:write_user` (`SYMPTOMS_PULSE_WRITE_USER`, default `tuist`) and
    `:write_token` (`SYMPTOMS_PULSE_WRITE_TOKEN`): a write-only identity, only
    for the hourly `span-edges.sql` insert (`execute/2`). Pulse checks only
    the write privilege for `INSERT ... SELECT`.
  - `:max_rows` (default 20 000; a call can pass its own `:max_rows`),
    `:receive_timeout` (default 30 s)
  """

  @max_body 8_388_608
  @default_max_rows 20_000

  @type rows :: [%{String.t() => term()}]
  @type error ::
          :not_configured
          | :query_result_limit
          | :invalid_query
          | :rate_limited
          | :upstream_error
          | :timeout
          | :unavailable
          | :malformed_response

  @doc """
  Runs a read query and returns its rows as maps. Appends
  `LIMIT max_rows + 1` and fails with `:query_result_limit` when the bound
  is exceeded, so a truncated result never reads as quiet. With `limit: n`
  it appends `LIMIT n` instead and returns at most `n` rows on purpose.
  """
  @spec query(String.t(), keyword()) :: {:ok, rows()} | {:error, error()}
  def query(sql, opts \\ []) do
    config = config(opts)
    max_rows = Keyword.get(opts, :max_rows) || Keyword.get(config, :max_rows, @default_max_rows)
    limit = Keyword.get(opts, :limit)

    with {:ok, client} <- client(config, :user, :token),
         {:ok, body} <- request(client, "#{sql} LIMIT #{limit || max_rows + 1}"),
         {:ok, rows} <- rows(body) do
      if is_nil(limit) and length(rows) > max_rows, do: {:error, :query_result_limit}, else: {:ok, rows}
    end
  end

  @doc "Runs a write statement with the write token. Returns the affected rows."
  @spec execute(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, error()}
  def execute(sql, opts \\ []) do
    with {:ok, client} <- client(config(opts), :write_user, :write_token),
         {:ok, body} <- request(client, sql) do
      case body do
        %{"output" => [%{"affectedrows" => count}]} when is_integer(count) -> {:ok, count}
        _ -> {:error, :malformed_response}
      end
    end
  end

  @doc "A SQL string literal. Pulse's SQL treats backslashes literally; doubling quotes is the only escape."
  @spec literal(String.t()) :: String.t()
  def literal(value) when is_binary(value), do: "'" <> String.replace(value, "'", "''") <> "'"

  @doc "A timestamp expression for Unix seconds."
  @spec timestamp(integer()) :: String.t()
  def timestamp(seconds) when is_integer(seconds), do: "to_timestamp_seconds(#{seconds})"

  @doc "`column >= start AND column < finish`, both in Unix seconds."
  @spec between(String.t(), integer(), integer()) :: String.t()
  def between(column, start, finish), do: "#{column} >= #{timestamp(start)} AND #{column} < #{timestamp(finish)}"

  @doc """
  The newest `time_window` (Unix seconds) of a Flow sink at or after `since`,
  or `nil` when nothing has arrived since then.
  """
  @spec latest_window(String.t(), integer(), keyword()) :: {:ok, integer() | nil} | {:error, error()}
  def latest_window(table, since, opts) do
    sql = "SELECT to_unixtime(max(time_window)) AS latest FROM #{table} WHERE time_window >= #{timestamp(since)}"

    case query(sql, opts) do
      {:ok, [%{"latest" => latest}]} when is_integer(latest) or is_nil(latest) -> {:ok, latest}
      {:ok, []} -> {:ok, nil}
      {:ok, _} -> {:error, :malformed_response}
      error -> error
    end
  end

  @doc """
  `:ok` when a Flow sink has rows for a window after the one that ends at
  `finish`, so the window is complete; `{:error, :lagging}` otherwise. Pulse
  has no backfill, so a window without later data is unknown, never zero.
  """
  @spec complete?(String.t(), integer(), keyword()) :: :ok | {:error, :lagging | error()}
  def complete?(table, finish, opts) do
    case latest_window(table, finish, opts) do
      {:ok, latest} when is_integer(latest) and latest >= finish -> :ok
      {:ok, _} -> {:error, :lagging}
      error -> error
    end
  end

  defp config(opts) do
    [user: "dashboard", write_user: "tuist"]
    |> Keyword.merge(Application.get_env(:symptoms, __MODULE__, []))
    |> Keyword.merge(Keyword.get(opts, :pulse, []))
  end

  defp client(config, user_key, token_key) do
    url = config[:base_url]
    token = config[token_key]

    if is_binary(url) and url != "" and is_binary(token) and token != "" do
      {:ok,
       %{
         base_url: String.trim_trailing(url, "/"),
         user: config[user_key],
         token: token,
         timeout: Keyword.get(config, :receive_timeout, 30_000)
       }}
    else
      {:error, :not_configured}
    end
  end

  defp request(client, sql) do
    request =
      Req.new(
        method: :get,
        url: client.base_url <> "/v1/sql",
        auth: {:basic, client.user <> ":" <> client.token},
        headers: [{"accept", "application/json"}, {"x-pulse-db-name", "public"}],
        params: [sql: sql],
        compressed: false,
        into: &bounded_body/2,
        redirect: false,
        retry: false,
        receive_timeout: client.timeout,
        connect_options: [timeout: 10_000]
      )

    case Req.request(request) do
      {:ok, %Req.Response{body: :too_large}} -> {:error, :query_result_limit}
      {:ok, %Req.Response{status: 200, body: body}} -> decode_body(body)
      {:ok, %Req.Response{status: status}} when status in [400, 422] -> {:error, :invalid_query}
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{}} -> {:error, :upstream_error}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp bounded_body({:data, data}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(data) <= @max_body,
      do: {:cont, {request, %{response | body: body <> data}}},
      else: {:halt, {request, %{response | body: :too_large}}}
  end

  defp decode_body(body) when is_binary(body) and byte_size(body) <= @max_body do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> {:error, :malformed_response}
    end
  end

  defp decode_body(body) when is_map(body), do: {:ok, body}
  defp decode_body(_body), do: {:error, :malformed_response}

  defp rows(%{"output" => [%{"records" => %{"schema" => %{"column_schemas" => columns}, "rows" => rows}}]})
       when is_list(columns) and is_list(rows) do
    names = Enum.map(columns, &(is_map(&1) && &1["name"]))

    if Enum.all?(names, &is_binary/1) and Enum.all?(rows, &(is_list(&1) and length(&1) == length(names))) do
      {:ok, Enum.map(rows, &Map.new(Enum.zip(names, &1)))}
    else
      {:error, :malformed_response}
    end
  end

  defp rows(_body), do: {:error, :malformed_response}
end
