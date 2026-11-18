defmodule TuistWeb.OIDCIssuerController do
  @moduledoc """
  The per-account OpenID Connect issuer Anthropic Workload Identity
  Federation verifies Tuist-signed tokens against
  (`Tuist.Sandboxes.Anthropic.Federation`).
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Sandboxes.Anthropic.Federation

  def openid_configuration(conn, %{"account_id" => account_id}) do
    with_account(conn, account_id, fn conn, id -> json(conn, Federation.openid_configuration(id)) end)
  end

  def jwks(conn, %{"account_id" => account_id}) do
    with_account(conn, account_id, fn conn, _id -> json(conn, Federation.jwks()) end)
  end

  defp with_account(conn, account_id, fun) do
    with {id, ""} <- Integer.parse(account_id),
         {:ok, _account} <- Accounts.get_account_by_id(id) do
      conn |> put_resp_header("cache-control", "public, max-age=300") |> fun.(id)
    else
      _ -> conn |> put_status(:not_found) |> json(%{message: "Issuer not found."})
    end
  end
end
