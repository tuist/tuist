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

    # Merge http_opts (which may be a map or keyword list)
    merged_opts = merge_opts(http_opts, req_opts)

    # Extract connect_options and convert to Finch pool options if present
    {connect_opts, other_opts} = pop_connect_options(merged_opts)

    # Build final options with Finch
    finch_opts = if connect_opts do
      [
        finch: Tuist.Finch,
        finch_options: [
          conn_opts: connect_opts
        ]
      ]
    else
      [finch: Tuist.Finch]
    end

    [
      method: method,
      url: url,
      body: body,
      headers: headers,
      decode_body: false
    ]
    |> Keyword.merge(finch_opts)
    |> Keyword.merge(other_opts)
    |> Keyword.delete(:follow_redirect)
    |> Req.request()
    |> case do
      {:ok, %{status: status, headers: headers, body: body}} ->
        {:ok, %{status_code: status, headers: headers, body: body}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  # Helper to merge options whether they're maps or keyword lists
  defp merge_opts(opts1, opts2) when is_map(opts1) and is_list(opts2) do
    Map.to_list(opts1) ++ opts2
  end

  defp merge_opts(opts1, opts2) when is_list(opts1) and is_list(opts2) do
    opts1 ++ opts2
  end

  defp merge_opts(opts1, _opts2) when is_map(opts1) do
    Map.to_list(opts1)
  end

  defp merge_opts(opts1, _opts2) do
    opts1
  end

  # Extract connect_options and return {connect_opts, remaining_opts}
  defp pop_connect_options(opts) do
    {connect_opts, remaining} = Keyword.pop(opts, :connect_options)
    {connect_opts, remaining}
  end
end
