defmodule Tuist.OIDC.JWKSClient do
  @moduledoc """
  Fetches a workload identity provider's JSON Web Key Set over a single,
  unpooled HTTPS connection.

  JWKS URLs are configured by tenants, and every request pins the connection
  to a validated IP while presenting the original hostname for SNI and
  certificate checks. Req starts a permanent Finch pool for every distinct set
  of connection options, so routing these requests through it would grow the
  process table with each new hostname. This client opens one Mint connection
  owned by the calling process, sends one GET, and always closes the socket.

  It never follows redirects or retries: any final status other than 200 is
  returned as an error.
  """

  @default_timeout 5_000
  @default_total_timeout 8_000
  @maximum_body_bytes 65_536
  @maximum_header_bytes 16_384

  @doc """
  Performs a GET request against `url`, whose host must be a pinned IP
  address. Hostnames are rejected with `{:error, :unpinned_host}`.

  Options:

    * `:connect_options` - `:hostname` (the original host used for SNI,
      certificate verification and the `Host` header), `:transport_opts`, and
      `:timeout` (connect timeout in milliseconds).
    * `:receive_timeout` - the maximum time to wait for each read.
    * `:total_timeout` - the maximum time to spend receiving the response,
      so a server that trickles bytes can't hold the connection open
      indefinitely. Defaults to 8 seconds.
    * `:headers` - request headers.
    * `:into` - a Req-style `fun({:data, chunk}, {request, response})` that
      returns `{:cont, acc}` or `{:halt, acc}`. Without it the body is
      accumulated internally.

  The body is limited to 64 KiB in every case. Other Req options such as
  `:redirect`, `:retry`, and `:decode_body` are accepted and ignored, since
  this client never redirects, retries, or decodes.

  Returns `{:ok, %{status: 200, headers: headers, body: body}}` or
  `{:error, reason}`.
  """
  def get(url, opts \\ []) do
    with {:ok, uri} <- parse_url(url),
         {:ok, conn} <- connect(uri, opts) do
      try do
        request(conn, uri, opts)
      after
        Mint.HTTP.close(conn)
      end
    end
  end

  # Only IP literals are accepted so a caller can't skip pinning and let DNS
  # resolve the host again at connect time.
  defp parse_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil} = uri} when is_binary(host) and host != "" ->
        if ip_address?(host), do: {:ok, uri}, else: {:error, :unpinned_host}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp parse_url(_url), do: {:error, :invalid_url}

  defp connect(%URI{host: address, port: port}, opts) do
    connect_options = Keyword.get(opts, :connect_options, [])
    hostname = Keyword.get(connect_options, :hostname, address)

    transport_opts =
      connect_options
      |> Keyword.get(:transport_opts, [])
      |> Keyword.put(:timeout, Keyword.get(connect_options, :timeout, @default_timeout))
      |> Keyword.put(:inet6, ipv6?(address))

    Mint.HTTP.connect(:https, address, port,
      hostname: hostname,
      transport_opts: transport_opts,
      protocols: [:http1],
      mode: :passive,
      max_header_list_size: @maximum_header_bytes
    )
  end

  defp ip_address?(host), do: match?({:ok, _}, :inet.parse_strict_address(String.to_charlist(host)))

  defp ipv6?(address) do
    case :inet.parse_strict_address(String.to_charlist(address)) do
      {:ok, {_, _, _, _, _, _, _, _}} -> true
      _ -> false
    end
  end

  defp request(conn, uri, opts) do
    headers = Keyword.get(opts, :headers, [])

    case Mint.HTTP.request(conn, "GET", request_target(uri), headers, nil) do
      {:ok, conn, ref} ->
        state = %{
          ref: ref,
          into: Keyword.get(opts, :into),
          receive_timeout: Keyword.get(opts, :receive_timeout, @default_timeout),
          deadline: System.monotonic_time(:millisecond) + Keyword.get(opts, :total_timeout, @default_total_timeout),
          response: nil
        }

        receive_response(conn, state)

      {:error, _conn, reason} ->
        {:error, reason}
    end
  end

  defp request_target(%URI{path: path, query: query}) do
    path = if path in [nil, ""], do: "/", else: path
    if is_nil(query), do: path, else: path <> "?" <> query
  end

  defp receive_response(conn, state) do
    remaining = state.deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      case Mint.HTTP.recv(conn, 0, min(state.receive_timeout, remaining)) do
        {:ok, conn, responses} ->
          case handle_responses(responses, state) do
            {:cont, state} -> receive_response(conn, state)
            {:done, result} -> result
          end

        {:error, _conn, reason, _responses} ->
          {:error, reason}
      end
    end
  end

  defp handle_responses([], state), do: {:cont, state}

  defp handle_responses([response | responses], state) do
    case handle_response(response, state) do
      {:cont, state} -> handle_responses(responses, state)
      {:done, result} -> {:done, result}
    end
  end

  # Informational (1xx) responses precede the final status and carry no body.
  defp handle_response({:status, ref, status}, %{ref: ref} = state) when status in 100..199, do: {:cont, state}

  defp handle_response({:status, ref, 200}, %{ref: ref, response: nil} = state) do
    {:cont, %{state | response: %{status: 200, headers: [], body: ""}}}
  end

  defp handle_response({:status, ref, status}, %{ref: ref}), do: {:done, {:error, {:unexpected_status, status}}}

  defp handle_response({:headers, ref, _headers}, %{ref: ref, response: nil} = state), do: {:cont, state}

  defp handle_response({:headers, ref, headers}, %{ref: ref, response: response} = state) do
    {:cont, %{state | response: %{response | headers: response.headers ++ headers}}}
  end

  defp handle_response({:data, ref, chunk}, %{ref: ref, response: %{} = response} = state) do
    case append(chunk, response, state.into) do
      {:cont, response} -> {:cont, %{state | response: response}}
      {:halt, response} -> {:done, {:ok, response}}
      {:error, reason} -> {:done, {:error, reason}}
    end
  end

  defp handle_response({:done, ref}, %{ref: ref, response: %{} = response}), do: {:done, {:ok, response}}

  defp handle_response({:error, ref, reason}, %{ref: ref}), do: {:done, {:error, reason}}

  defp handle_response(_response, _state), do: {:done, {:error, :unexpected_response}}

  defp append(chunk, %{body: body} = response, nil) when is_binary(body) do
    if byte_size(body) + byte_size(chunk) <= @maximum_body_bytes,
      do: {:cont, %{response | body: body <> chunk}},
      else: {:error, :response_too_large}
  end

  defp append(chunk, response, into) when is_function(into, 2) do
    case into.({:data, chunk}, {nil, response}) do
      {:cont, {_request, %{body: body} = response}} when is_binary(body) and byte_size(body) <= @maximum_body_bytes ->
        {:cont, response}

      {:cont, {_request, _response}} ->
        {:error, :response_too_large}

      {:halt, {_request, response}} ->
        {:halt, response}
    end
  end
end
