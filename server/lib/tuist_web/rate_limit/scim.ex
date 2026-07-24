defmodule TuistWeb.RateLimit.SCIM do
  @moduledoc """
  Rate limiting for SCIM endpoints.
  """

  alias Tuist.Accounts.AccountToken
  alias TuistWeb.RateLimit

  @bucket_size 600

  def hit(conn) do
    RateLimit.hit(key(conn), limit: @bucket_size, window: to_timeout(minute: 1))
  end

  defp key(%{assigns: %{scim_token: %AccountToken{id: id}}}), do: "scim:token:#{id}"
  defp key(conn), do: "scim:ip:#{TuistWeb.RemoteIp.get(conn)}"
end
