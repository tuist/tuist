defmodule TuistWeb.API.Internal.AuthController do
  @moduledoc """
  Internal token verification used by Kura mesh nodes via their Lua
  extension hook.

  This is **not** part of the public API — the surface is gated by a
  shared secret in the `Authorization` header that Kura sends from
  `KURA_EXTENSION_HTTP_CLIENT_TUIST_HEADERS_AUTHORIZATION`. The shared
  secret lives in the encrypted secrets bundle as
  `kura.verify_token` and is provisioned by the rollout worker into
  the Kura StatefulSet's env at deploy time.

  The endpoint accepts a CLI bearer token, runs it through the same
  `Tuist.Authentication.authenticated_subject/1` resolver the rest of
  the API uses, and returns a principal description Kura's `authorize`
  hook can use locally:

      {
        "principal": {
          "id": "<integer-as-string>",
          "kind": "user" | "project" | "account",
          "account_handles": ["tuist", "another-org"]
        }
      }

  No information beyond what the caller already had access to is
  returned. The shared-secret check stops random clients from using
  this as an oracle to probe token validity.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authentication
  alias Tuist.Projects.Project

  plug :require_kura_caller

  def verify(conn, %{"token" => token}) when is_binary(token) and token != "" do
    case Authentication.authenticated_subject(token) do
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_token"})

      subject ->
        json(conn, %{principal: principal(subject)})
    end
  end

  def verify(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing_token"})
  end

  defp principal(%User{} = user) do
    handles =
      [user.account.name | Enum.map(Accounts.get_user_organization_accounts(user), & &1.account.name)]
      |> Enum.uniq()

    %{
      id: to_string(user.id),
      kind: "user",
      account_handles: handles
    }
  end

  defp principal(%Project{} = project) do
    %{
      id: to_string(project.id),
      kind: "project",
      account_handles: [project.account.name]
    }
  end

  defp principal(%AuthenticatedAccount{account: account}) do
    %{
      id: to_string(account.id),
      kind: "account",
      account_handles: [account.name]
    }
  end

  defp require_kura_caller(conn, _opts) do
    expected = Tuist.Environment.kura_verify_token()
    presented = bearer(conn)

    cond do
      is_nil(expected) or expected == "" ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "verify_disabled"})
        |> halt()

      is_nil(presented) or not Plug.Crypto.secure_compare(presented, expected) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_caller"})
        |> halt()

      true ->
        conn
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end
