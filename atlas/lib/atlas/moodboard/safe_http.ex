defmodule Atlas.Moodboard.SafeHTTP do
  @moduledoc "Bounded, credential-free HTTPS reads with DNS validation and a pinned destination on every redirect."

  alias Atlas.Moodboard.Resolver
  alias Atlas.URL
  alias Mint.HTTP

  @max_bytes 2_000_000
  @timeout 12_000

  def fetch(url), do: fetch(url, 3, System.monotonic_time(:millisecond) + @timeout)

  def public_url?(url) when is_binary(url) and byte_size(url) <= 2048 do
    with {:ok, uri} <- URI.new(url),
         {:ok, %{scheme: "https"}} <- URL.validate_public(url) do
      uri.userinfo == nil and uri.port == 443
    else
      _ -> false
    end
  end

  def public_url?(_url), do: false

  def public_address?({a, b, c, d} = address) do
    match?({:ok, _}, URL.validate_public("https://#{:inet.ntoa(address)}")) and
      a < 224 and {a, b, c, d} not in [{255, 255, 255, 255}] and
      not (a == 192 and b == 88 and c == 99) and
      not (a == 198 and b in [18, 19])
  end

  # Only global-unicast IPv6; reject transition mechanisms that can encode private IPv4 destinations.
  def public_address?({a, b, _, _, _, _, _, _} = address) do
    a in 0x2000..0x3FFD and a != 0x2002 and not (a == 0x2001 and (b <= 0x1FF or b == 0xDB8)) and
      match?({:ok, _}, URL.validate_public("https://[#{:inet.ntoa(address)}]"))
  end

  def public_address?(_address), do: false

  defp fetch(url, redirects_left, deadline) do
    with true <- public_url?(url),
         true <- System.monotonic_time(:millisecond) < deadline,
         uri = URI.parse(url),
         {:ok, [_ | _] = addresses} <- Resolver.resolve(uri.host),
         true <- System.monotonic_time(:millisecond) < deadline,
         true <- Enum.all?(addresses, &public_address?/1),
         {:ok, response} <- request(uri, hd(addresses), deadline) do
      if response.status in [301, 302, 303, 307, 308] do
        with true <- redirects_left > 0,
             {_, location} <- List.keyfind(response.headers, "location", 0) do
          next_url = uri |> URI.merge(location) |> URI.to_string()
          fetch(next_url, redirects_left - 1, deadline)
        else
          _ -> {:error, :redirect_rejected}
        end
      else
        {:ok, Map.put(response, :url, url)}
      end
    else
      {:error, :dns_unavailable} -> {:error, :dns_unavailable}
      {:error, _reason} -> {:error, :fetch_failed}
      {:error, _conn, _reason} -> {:error, :fetch_failed}
      _ -> {:error, :unsafe_url}
    end
  rescue
    _ -> {:error, :fetch_failed}
  end

  defp request(uri, address, deadline) do
    opts = [
      hostname: uri.host,
      protocols: [:http1],
      mode: :passive,
      max_header_list_size: 32_768,
      transport_opts: [timeout: remaining(deadline), verify: :verify_peer]
    ]

    with {:ok, conn} <- HTTP.connect(:https, address, 443, opts) do
      try do
        path = URI.to_string(%URI{path: uri.path || "/", query: uri.query})

        headers = [
          {"accept", "text/html, application/json, text/plain;q=0.8"},
          {"accept-encoding", "identity"},
          {"user-agent", "Atlas-Moodboard/1.0"}
        ]

        with {:ok, conn, _ref} <- HTTP.request(conn, "GET", path, headers, nil) do
          receive_response(conn, %{status: nil, headers: [], body: "", done: false}, deadline)
        end
      after
        HTTP.close(conn)
      end
    end
  end

  defp receive_response(conn, response, deadline) do
    with {:ok, conn, events} <- HTTP.recv(conn, 0, remaining(deadline)),
         {:ok, response} <- consume(events, response) do
      cond do
        response.done -> {:ok, Map.delete(response, :done)}
        System.monotonic_time(:millisecond) >= deadline -> {:error, :timeout}
        true -> receive_response(conn, response, deadline)
      end
    else
      _ -> {:error, :fetch_failed}
    end
  end

  defp consume(events, response), do: Enum.reduce_while(events, {:ok, response}, &consume_event/2)

  defp consume_event({:status, _ref, status}, {:ok, acc}), do: {:cont, {:ok, %{acc | status: status}}}

  defp consume_event({:headers, _ref, headers}, {:ok, acc}) do
    encoding = List.keyfind(headers, "content-encoding", 0)

    type =
      case List.keyfind(headers, "content-type", 0) do
        {_, value} -> String.downcase(String.trim(value))
        _ -> ""
      end

    cond do
      encoding not in [nil, {"content-encoding", "identity"}] -> {:halt, {:error, :compressed_response}}
      String.starts_with?(type, ["image/", "video/"]) -> {:halt, {:ok, %{acc | headers: headers, done: true}}}
      true -> {:cont, {:ok, %{acc | headers: acc.headers ++ headers}}}
    end
  end

  defp consume_event({:data, _ref, data}, {:ok, acc}) do
    if byte_size(acc.body) + byte_size(data) <= @max_bytes do
      {:cont, {:ok, %{acc | body: acc.body <> data}}}
    else
      {:halt, {:error, :response_too_large}}
    end
  end

  defp consume_event({:done, _ref}, {:ok, acc}), do: {:halt, {:ok, %{acc | done: true}}}
  defp consume_event(_event, _acc), do: {:halt, {:error, :fetch_failed}}

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 1)
end
