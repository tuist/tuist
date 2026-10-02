defmodule TuistEx.HTTP do
  @moduledoc false

  def request(method, url, body \\ nil, headers \\ []) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    headers =
      [
        {~c"accept", ~c"application/json"}
        | Enum.map(headers, fn {name, value} ->
            {String.to_charlist(name), String.to_charlist(value)}
          end)
      ]

    request =
      if body do
        {String.to_charlist(url), headers, ~c"application/json", Jason.encode!(body)}
      else
        {String.to_charlist(url), headers}
      end

    options = [timeout: 15_000, connect_timeout: 10_000, autoredirect: false]

    options =
      if URI.parse(url).scheme == "https" do
        Keyword.put(options, :ssl,
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        )
      else
        options
      end

    case :httpc.request(method, request, options, body_format: :binary) do
      {:ok, {{_, status, _}, _, response}} ->
        decoded =
          case Jason.decode(response) do
            {:ok, value} -> value
            _ -> %{}
          end

        {:ok, status, decoded}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Uploads `binary` to a pre-signed URL and returns the `ETag` the storage
  answered with.
  """
  def put_binary(url, binary) do
    start()
    request = {String.to_charlist(url), [], ~c"application/octet-stream", binary}

    case :httpc.request(:put, request, options(url, 600_000), body_format: :binary) do
      {:ok, {{_, status, _}, headers, _body}} when status in 200..299 ->
        case List.keyfind(headers, ~c"etag", 0) do
          {_, etag} -> {:ok, List.to_string(etag)}
          nil -> {:error, :missing_etag}
        end

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads a URL straight to `path`, without holding the body in memory.
  """
  def download(url, path) do
    start()
    request = {String.to_charlist(url), []}

    case :httpc.request(:get, request, options(url, 600_000), stream: String.to_charlist(path)) do
      {:ok, :saved_to_file} -> :ok
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
  end

  defp options(url, timeout) do
    options = [timeout: timeout, connect_timeout: 10_000, autoredirect: false]

    if URI.parse(url).scheme == "https" do
      Keyword.put(options, :ssl,
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      )
    else
      options
    end
  end
end
