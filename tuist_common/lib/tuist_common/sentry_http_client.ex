defmodule TuistCommon.SentryHTTPClient do
  @moduledoc """
  Sentry HTTP client that uses Finch.
  """

  @behaviour Sentry.HTTPClient

  @finch_name TuistCommon.SentryFinch

  @impl true
  def child_spec do
    Supervisor.child_spec({Finch, name: @finch_name}, id: @finch_name)
  end

  @impl true
  def post(url, headers, body) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, @finch_name) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, status, headers, body}

      {:error, error} ->
        {:error, error}
    end
  end
end
