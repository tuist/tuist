defmodule Tuist.OIDC.JWKSClient do
  @moduledoc """
  Fetches a workload identity provider's JSON Web Key Set over a single,
  unpooled HTTPS connection through `Tuist.OAuth2.PinnedHTTP`.

  JWKS URLs are configured by tenants, so every request pins the connection
  to a validated IP while presenting the original hostname for SNI and
  certificate checks, and never starts a Req/Finch pool. It never follows
  redirects or retries: any final status other than 200 is returned as an
  error, and the body is limited to 64 KiB.
  """

  alias Tuist.OAuth2.PinnedHTTP

  @doc """
  Performs a GET request against `url`, whose host must be a pinned IP
  address. Accepts the options of `Tuist.OAuth2.PinnedHTTP.request/3`.

  Returns `{:ok, %{status: 200, headers: headers, body: body}}` or
  `{:error, reason}`.
  """
  def get(url, opts \\ []) do
    PinnedHTTP.request("GET", url, Keyword.merge(opts, accept_status: 200, max_body_bytes: 65_536, body: nil))
  end
end
