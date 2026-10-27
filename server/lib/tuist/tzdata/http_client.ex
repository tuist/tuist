defmodule Tuist.Tzdata.HTTPClient do
  @moduledoc false

  @behaviour Tzdata.HTTPClient

  @impl true
  def get(url, headers, options) do
    case request(:get, url, headers, options) do
      {:ok, %{status: status, headers: response_headers, body: body}} ->
        {:ok, {status, response_headers, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def head(url, headers, options) do
    case request(:head, url, headers, options) do
      {:ok, %{status: status, headers: response_headers}} ->
        {:ok, {status, response_headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(method, url, headers, options) do
    case Req.request(
           method: method,
           url: url,
           headers: headers,
           redirect: Keyword.get(options, :follow_redirect, false),
           decode_body: false
         ) do
      {:ok, %Req.Response{} = response} -> {:ok, Req.Response.to_map(response)}
      {:error, reason} -> {:error, reason}
    end
  end
end
