defmodule TuistCommon.SentryHTTPClient do
  @moduledoc """
  Sentry HTTP client that uses Finch.
  """

  @behaviour Sentry.HTTPClient

  @impl true
  def post(url, headers, body) do
    finch_name = Application.get_env(:tuist_common, :finch_name)
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, finch_name) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, status, headers, body}

      {:error, error} ->
        {:error, error}
    end
  end
end
