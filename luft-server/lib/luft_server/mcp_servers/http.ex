defmodule LuftServer.MCPServers.HTTP do
  @moduledoc """
  Sends one request to an MCP server or its authorization server. Every URL
  comes from a person or from metadata a third party controls, so the host is
  resolved once, refused unless every address is public, and the connection
  is pinned to that address (`LuftServer.HTTP.SSRFGuard`) over a single
  unpooled connection (`LuftServer.HTTP.PinnedHTTP`). Nothing is redirected
  or retried.

  Tests set `LuftServer.Config.mcp_req_options/0`, which sends the same
  request through Req instead, with the same options and response shape.

  Returns `{:ok, %{status: status, headers: [{name, value}], body: body}}`.
  Name resolution failures, private addresses and transport errors are all
  `{:error, :unreachable}`, so errors do not reveal which internal names exist.
  """

  alias LuftServer.Config
  alias LuftServer.HTTP.PinnedHTTP
  alias LuftServer.HTTP.SSRFGuard

  def request(method, url, options) do
    case Config.mcp_req_options() do
      [] -> pinned(method, url, options)
      req_options -> stubbed(method, url, options, req_options)
    end
  end

  defp pinned(method, url, options) do
    with {:ok, pinned, host} <- SSRFGuard.pin(url),
         connect_options = SSRFGuard.connect_options(host) ++ [timeout: 5_000],
         {:ok, response} <-
           PinnedHTTP.request(
             method,
             pinned,
             Keyword.put(options, :connect_options, connect_options)
           ) do
      {:ok, response}
    else
      {:error, {:unexpected_status, _status}} = error -> error
      {:error, _reason} -> {:error, :unreachable}
    end
  end

  defp stubbed(method, url, options, req_options) do
    into =
      case options[:into] do
        nil ->
          nil

        into ->
          fn data, {request, response} ->
            {action, {_request, collected}} = into.(data, {nil, plain(response)})
            {action, {request, %{response | body: collected.body}}}
          end
      end

    request =
      [
        method: method,
        url: url,
        headers: options[:headers] || [],
        body: options[:body],
        retry: false,
        redirect: false,
        decode_body: false
      ] ++ if(into, do: [into: into], else: []) ++ req_options

    case Req.request(request) do
      {:ok, response} ->
        response = plain(response)
        accepted = options[:accept_status]

        cond do
          accepted && response.status not in List.wrap(accepted) ->
            {:error, {:unexpected_status, response.status}}

          options[:headers_only] ->
            {:ok, %{response | body: ""}}

          is_nil(into) and
              byte_size(response.body) > Keyword.get(options, :max_body_bytes, 65_536) ->
            {:error, :unreachable}

          true ->
            {:ok, response}
        end

      {:error, _reason} ->
        {:error, :unreachable}
    end
  end

  defp plain(%Req.Response{} = response) do
    headers = for {name, values} <- response.headers, value <- values, do: {name, value}
    %{status: response.status, headers: headers, body: response.body || ""}
  end

  defp plain(response), do: response
end
