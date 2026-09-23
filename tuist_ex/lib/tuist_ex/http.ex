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
end
