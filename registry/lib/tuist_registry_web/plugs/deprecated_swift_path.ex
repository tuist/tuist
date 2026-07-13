defmodule TuistRegistryWeb.Plugs.DeprecatedSwiftPath do
  @moduledoc """
  Marks Swift Package Registry responses served under the legacy
  `/api/registry/swift/*` prefix as deprecated.

  The canonical path is `/swift/*` on `registry.tuist.dev`. The legacy
  prefix is kept so clients that still resolve registry URLs under
  `/api/registry/swift/*` (the path cache served before the registry
  was extracted) keep working through the cutover and beyond.

  Sets the standard `Deprecation` and `Sunset` response headers
  (RFC 8594) so well-behaved clients and observability tooling can
  surface the warning. The `Sunset` date is intentionally generous to
  give CLI users time to upgrade.
  """

  import Plug.Conn

  @sunset_http_date "Thu, 31 Dec 2026 23:59:59 GMT"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("deprecation", "true")
    |> put_resp_header("sunset", @sunset_http_date)
  end
end
