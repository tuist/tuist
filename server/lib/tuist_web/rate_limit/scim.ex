defmodule TuistWeb.RateLimit.SCIM do
  @moduledoc """
  Rate limiting for SCIM endpoints.
  """

  alias Tuist.Accounts.AccountToken
  alias TuistWeb.RateLimit.InMemory

  @bucket_size 600

  def hit(conn) do
    conn
    |> key()
    |> InMemory.hit(to_timeout(minute: 1), @bucket_size)
  end

  defp key(%{assigns: %{scim_token: %AccountToken{id: id}}}), do: "scim:token:#{id}"
  defp key(conn), do: "scim:ip:#{TuistWeb.RemoteIp.get(conn)}"
end
