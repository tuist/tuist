defmodule Condukt.MCP.Server do
  @moduledoc """
  Declarative configuration for a connected MCP server.

  See `Condukt.MCP` for the supported transports, authentication shapes,
  and how the struct fits into agents.

  ## Fields

    * `:name` (required, string) - identifier used to prefix tools
      discovered on this server (`<name>.<tool>` unless overridden by
      `:prefix`). Must match `~r/^[A-Za-z][A-Za-z0-9_-]*$/`.

    * `:transport` (required) - one of:
      - `{:stdio, command: binary, args: [binary], env: %{string => string}}` -
        spawns a subprocess and exchanges newline-delimited JSON-RPC over
        its stdio.
      - `{:http_sse, url: binary, headers: %{string => string}}` - the
        legacy 2024-11 transport with separate POST and SSE endpoints.
      - `{:streamable_http, url: binary, headers: %{string => string}}` -
        the 2025-03-26 single-URL streamable HTTP transport. Default for
        new HTTP-based MCP servers.

    * `:auth` - HTTP authentication. See `Condukt.MCP` for the supported
      shapes. Ignored by the stdio transport.

    * `:env` - extra environment variables to inject into the spawned
      subprocess (stdio only). May be a list of variable names to
      passthrough from the parent process (`["GITHUB_TOKEN"]`) or a map
      of names to secret refs (`%{"GH_TOKEN" => {:env, "GITHUB_TOKEN"}}`).

    * `:prefix` - overrides the default `<name>.` tool name prefix. Pass
      `""` to expose tools without any prefix (use with care, server
      names then become irrelevant for collision avoidance).

    * `:init_timeout` - max milliseconds to wait for the `initialize`
      handshake and `tools/list` exchange (default `10_000`).

    * `:request_timeout` - max milliseconds for a single tool call
      (default `60_000`).
  """

  @enforce_keys [:name, :transport]
  defstruct [
    :name,
    :transport,
    :auth,
    :env,
    :prefix,
    init_timeout: 10_000,
    request_timeout: 60_000
  ]

  @name_pattern ~r/^[A-Za-z][A-Za-z0-9_-]*$/
  @client_credentials_keys %{
    "token_url" => :token_url,
    "token_url_env" => :token_url_env,
    "token_url_static" => :token_url_static,
    "client_id" => :client_id,
    "client_id_env" => :client_id_env,
    "client_id_static" => :client_id_static,
    "client_secret" => :client_secret,
    "client_secret_env" => :client_secret_env,
    "client_secret_static" => :client_secret_static,
    "scope" => :scope
  }

  @doc """
  Returns the tool name prefix used for tools discovered on this server.
  """
  def prefix(%__MODULE__{prefix: nil, name: name}), do: name
  def prefix(%__MODULE__{prefix: prefix}), do: prefix

  @doc """
  Validates a server spec and normalizes shorthand fields.

  Returns `{:ok, server}` or `{:error, reason}`.
  """
  def normalize(%__MODULE__{} = server) do
    with :ok <- validate_name(server.name),
         {:ok, transport} <- normalize_transport(server.transport),
         :ok <- validate_auth(server.auth) do
      {:ok, %{server | transport: transport}}
    end
  end

  def normalize(map) when is_map(map) do
    map
    |> from_map()
    |> case do
      {:ok, server} -> normalize(server)
      {:error, _} = err -> err
    end
  end

  @doc false
  def from_map(%{} = map) do
    with {:ok, name} <- required_string(map, ["name", :name], :missing_name),
         {:ok, transport_spec} <- required_value(map, ["transport", :transport], :missing_transport),
         {:ok, transport} <- transport_from_map(transport_spec, map),
         {:ok, auth} <- auth_from_map(first_value(map, ["auth", :auth])) do
      {:ok, server_from_map(map, name, transport, auth)}
    end
  end

  defp fetch(map, key), do: Map.get(map, key)

  defp first_value(map, keys) do
    Enum.find_value(keys, &fetch(map, &1))
  end

  defp required_value(map, keys, error) do
    case first_value(map, keys) do
      nil -> {:error, error}
      value -> {:ok, value}
    end
  end

  defp required_string(map, keys, error) do
    case Enum.find_value(keys, &fetch_string(map, &1)) do
      nil -> {:error, error}
      value -> {:ok, value}
    end
  end

  defp server_from_map(map, name, transport, auth) do
    %__MODULE__{
      name: name,
      transport: transport,
      auth: auth,
      env: first_value(map, ["env", :env]),
      prefix: first_value(map, ["prefix", :prefix]),
      init_timeout: first_value(map, ["init_timeout", :init_timeout]) || 10_000,
      request_timeout: first_value(map, ["request_timeout", :request_timeout]) || 60_000
    }
  end

  defp fetch_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp transport_from_map({_kind, _opts} = transport, _map), do: {:ok, transport}
  defp transport_from_map("stdio", map), do: {:ok, {:stdio, stdio_opts(map)}}
  defp transport_from_map("http_sse", map), do: {:ok, {:http_sse, http_opts(map)}}
  defp transport_from_map("http", map), do: {:ok, {:streamable_http, http_opts(map)}}
  defp transport_from_map("streamable_http", map), do: {:ok, {:streamable_http, http_opts(map)}}
  defp transport_from_map(other, _map), do: {:error, {:invalid_transport, other}}

  defp stdio_opts(map) do
    [
      command: fetch(map, "command") || fetch(map, :command),
      args: fetch(map, "args") || fetch(map, :args) || []
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp http_opts(map) do
    [
      url: fetch(map, "url") || fetch(map, :url),
      headers: fetch(map, "headers") || fetch(map, :headers) || %{}
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp auth_from_map(nil), do: {:ok, nil}
  defp auth_from_map(%{"type" => "bearer"} = map), do: {:ok, {:bearer, secret_ref_from_map(map)}}
  defp auth_from_map(%{type: "bearer"} = map), do: {:ok, {:bearer, secret_ref_from_map(map)}}

  defp auth_from_map(%{"type" => "client_credentials"} = map) do
    with {:ok, opts} <- client_credentials_opts(map), do: {:ok, {:client_credentials, opts}}
  end

  defp auth_from_map(%{type: "client_credentials"} = map) do
    with {:ok, opts} <- client_credentials_opts(map), do: {:ok, {:client_credentials, opts}}
  end

  defp auth_from_map(other), do: {:ok, other}

  defp secret_ref_from_map(map) do
    cond do
      value = Map.get(map, "env") || Map.get(map, :env) -> {:env, value}
      value = Map.get(map, "static") || Map.get(map, :static) -> {:static, value}
      value = Map.get(map, "op") || Map.get(map, :op) -> {:op, value}
      true -> nil
    end
  end

  defp client_credentials_opts(map) do
    map
    |> Enum.reduce_while({:ok, []}, fn
      {k, _v}, {:ok, acc} when k in ["type", :type] ->
        {:cont, {:ok, acc}}

      {k, v}, {:ok, acc} ->
        case client_credentials_key(k) do
          {:ok, key} -> {:cont, {:ok, [{key, v} | acc]}}
          :error -> {:halt, {:error, {:unknown_client_credentials_key, to_string(k)}}}
        end
    end)
    |> case do
      {:ok, opts} -> {:ok, Enum.reverse(opts)}
      {:error, _} = err -> err
    end
  end

  defp client_credentials_key(key) when is_atom(key) do
    client_credentials_key(Atom.to_string(key))
  end

  defp client_credentials_key(key) when is_binary(key) do
    case Map.fetch(@client_credentials_keys, key) do
      {:ok, key} -> {:ok, key}
      :error -> :error
    end
  end

  defp validate_name(name) when is_binary(name) do
    if Regex.match?(@name_pattern, name), do: :ok, else: {:error, {:invalid_server_name, name}}
  end

  defp validate_name(other), do: {:error, {:invalid_server_name, other}}

  defp normalize_transport({:stdio, opts}) when is_list(opts) do
    case Keyword.get(opts, :command) do
      command when is_binary(command) and command != "" ->
        {:ok, {:stdio, opts}}

      _ ->
        {:error, :stdio_command_required}
    end
  end

  defp normalize_transport({kind, opts}) when kind in [:http_sse, :streamable_http] and is_list(opts) do
    case Keyword.get(opts, :url) do
      url when is_binary(url) and url != "" ->
        {:ok, {kind, opts}}

      _ ->
        {:error, {:url_required, kind}}
    end
  end

  defp normalize_transport(other), do: {:error, {:invalid_transport, other}}

  defp validate_auth(nil), do: :ok
  defp validate_auth({:bearer, _ref}), do: :ok
  defp validate_auth({:client_credentials, opts}) when is_list(opts), do: :ok
  defp validate_auth(other), do: {:error, {:invalid_auth, other}}
end
