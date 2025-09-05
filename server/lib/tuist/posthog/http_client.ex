defmodule Tuist.PostHog.HTTPClient do
  @moduledoc """
  HTTP client for PostHog API requests using Req with Finch connection pooling.
  """

  @behaviour Posthog.HTTPClient

  def post(url, body, headers, _opts) do
    case Req.post(url,
           body: body,
           headers: headers,
           finch: Tuist.Finch,
           decode_body: false
         ) do
      {:ok, %{status: status, headers: response_headers, body: response_body}} ->
        {:ok, %{status: status, headers: response_headers, body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
