defmodule TuistCommon.AWS.Client do
  @moduledoc """
  Custom HTTP client for ExAws using Req.

  This shouldn't be necessary, but there's a bug in the client
  provided by ExAws that causes the request to blow up.

  Options can be set for `m:Req` with the following config:

      config :ex_aws, :req_opts,
        receive_timeout: 30_000

  The default config handles setting the above.

  ## Redirects

  Req follows redirects by default, but AWS requests are signed with SigV4 for a
  specific host. If Req transparently follows a redirect (for example S3
  answering a region mismatch with a 301/307 to a different endpoint), it resends
  the request to the new host while reusing the `Authorization` header signed for
  the original host, which the new host rejects as an improperly signed request.

  We disable Req's automatic redirect handling so that redirects surface to ExAws
  (which knows how to re-sign and retry against the right region) instead of being
  followed with a stale signature. We also drop the legacy `:follow_redirect`
  option so it never leaks into `Req.request/1`.
  """

  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body \\ "", headers \\ [], http_opts \\ []) do
    req_opts = Application.get_env(:ex_aws, :req_opts, [])

    http_opts_list = if is_map(http_opts), do: Map.to_list(http_opts), else: http_opts

    finch_name = Application.get_env(:tuist_common, :finch_name)

    opts =
      [
        method: method,
        url: url,
        body: body,
        headers: headers,
        decode_body: false,
        finch: finch_name
      ]
      |> Keyword.merge(req_opts)
      |> Keyword.merge(http_opts_list)
      |> Keyword.delete(:follow_redirect)
      |> Keyword.put(:redirect, false)

    opts =
      if Keyword.get(opts, :finch) do
        opts
        |> Keyword.delete(:connect_options)
        |> Keyword.delete(:inet6)
      else
        opts
      end

    opts
    |> Req.request()
    |> case do
      {:ok, %{status: status, headers: headers, body: body}} ->
        {:ok, %{status_code: status, headers: headers, body: body}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
