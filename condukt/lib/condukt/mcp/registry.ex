defmodule Condukt.MCP.Registry do
  @moduledoc """
  Lifecycle helper for connecting to a list of MCP servers as part of
  starting a session.

  `start_all/2` opens one `Condukt.MCP.Client` per server and discovers
  the tools each one exposes. The returned registry value carries the
  client pids and prebuilt `Condukt.Tool.Inline` specs ready to merge
  into an agent tool list.

  `stop_all/1` closes every connection in the registry. Tool inline
  specs returned by `tools/1` capture the client pid in their `:call`
  closure, so once stopped they will fail with a transport error.
  """

  alias Condukt.MCP.{Client, Server, Tool}

  defstruct entries: []

  @doc """
  Returns an empty registry.
  """
  def new, do: %__MODULE__{}

  @doc """
  Starts a `Condukt.MCP.Client` for each server in `servers`.

  Servers may be `%Condukt.MCP.Server{}` structs or plain maps that
  `Condukt.MCP.Server.normalize/1` can normalize. On the first failure
  every already-started client is stopped before returning the error.

  Options are forwarded to `Condukt.MCP.Client.start_link/2` (and
  ultimately to the transports). Use `:fetch_env`, `:token_request`,
  `:sse_request`, and `:http_request` to inject test doubles.
  """
  def start_all(servers, opts \\ [])

  def start_all([], _opts), do: {:ok, new()}

  def start_all(servers, opts) when is_list(servers) do
    Enum.reduce_while(servers, {:ok, []}, fn server_spec, {:ok, acc} ->
      case start_one(server_spec, opts) do
        {:ok, entry} ->
          {:cont, {:ok, [entry | acc]}}

        {:error, reason} ->
          rollback(acc)
          {:halt, {:error, {:mcp_start_failed, name_of(server_spec), reason}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, %__MODULE__{entries: Enum.reverse(entries)}}
      {:error, _} = err -> err
    end
  end

  defp start_one(spec, opts) do
    with {:ok, server} <- normalize(spec),
         {:ok, client} <- Client.start_link(server, opts) do
      tools = Tool.inline_tools(client, server)
      {:ok, %{server: server, client: client, tools: tools}}
    end
  end

  defp normalize(%Server{} = server), do: Server.normalize(server)
  defp normalize(map) when is_map(map), do: Server.normalize(map)
  defp normalize(other), do: {:error, {:invalid_server_spec, other}}

  defp rollback(entries) do
    Enum.each(entries, fn entry -> Client.stop(entry.client) end)
  end

  defp name_of(%Server{name: name}), do: name
  defp name_of(%{"name" => name}), do: name
  defp name_of(%{name: name}), do: name
  defp name_of(_), do: nil

  @doc """
  Stops every connection in the registry. Safe to call when the
  registry is already empty or when individual clients have already
  exited.
  """
  def stop_all(%__MODULE__{entries: entries}) do
    Enum.each(entries, fn entry -> Client.stop(entry.client) end)
    :ok
  end

  def stop_all(other) when is_list(other) do
    Enum.each(other, fn
      %{client: client} -> Client.stop(client)
      _ -> :ok
    end)

    :ok
  end

  @doc """
  Returns every inline tool spec exposed by the registry, flattened
  into a single list ready to be appended to an agent's `tools` list.
  """
  def tools(%__MODULE__{entries: entries}) do
    Enum.flat_map(entries, & &1.tools)
  end

  @doc """
  Returns the entries in the registry. Useful for telemetry or
  introspection.
  """
  def entries(%__MODULE__{entries: entries}), do: entries
end
