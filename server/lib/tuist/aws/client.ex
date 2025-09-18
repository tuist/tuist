defmodule Tuist.AWS.Client do
  # This shouldn't be necessary, but there's a bug in the client
  # provided by ExAWS that causes the request to blow up.
  @moduledoc """
  Configuration for `m:Req`.

  Options can be set for `m:Req` with the following config:

      config :ex_aws, :req_opts,
        receive_timeout: 30_000

  The default config handles setting the above.
  """

  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body \\ "", headers \\ [], http_opts \\ []) do
    # Get req_opts from config
    req_opts = Application.get_env(:ex_aws, :req_opts, [])

    # Convert http_opts to keyword list if it's a map
    http_opts_list = if is_map(http_opts), do: Map.to_list(http_opts), else: http_opts

    [
      method: method,
      url: url,
      body: body,
      headers: headers,
      decode_body: false,
      finch: Tuist.Finch
    ]
    |> Keyword.merge(req_opts)
    |> Keyword.merge(http_opts_list)
    |> Keyword.delete(:follow_redirect)
    |> Req.request()
    |> case do
      {:ok, %{status: status, headers: headers, body: body}} ->
        {:ok, %{status_code: status, headers: headers, body: body}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
