defmodule AtlasWeb.POCPublicController do
  @moduledoc """
  HTTP surface for the customer-facing POC brief:

  - `verify`: the target of the "Confirm my email" link in the verification
    email. Marks the request as email-verified and redirects the visitor
    back to the brief LiveView, which then waits on Slack approval via
    PubSub.

  - `session`: called by the LiveView (via `push_navigate`) once both
    email verification and ops approval land. Sets a signed session
    cookie scoped to the POC and redirects to the brief.
  """

  use AtlasWeb, :controller

  alias Atlas.Accounts.POCs
  alias Atlas.Accounts.POCs.AccessRequest

  def verify(conn, %{"public_token" => public_token, "request_id" => request_id, "token" => token}) do
    with %{} = poc <- POCs.get_poc_by_public_token(public_token),
         %AccessRequest{poc_id: poc_id} = _request when poc_id == poc.id <- POCs.get_access_request(request_id),
         {:ok, _request} <- POCs.verify_access_email(request_id, token) do
      conn
      |> put_flash(:info, "Email confirmed. Waiting for the Tuist team to grant access.")
      |> redirect(to: ~p"/p/pocs/#{public_token}")
    else
      _ ->
        conn
        |> put_flash(:error, "That verification link is invalid or expired.")
        |> redirect(to: ~p"/p/pocs/#{public_token}")
    end
  end

  def verify(conn, %{"public_token" => public_token}) do
    conn
    |> put_flash(:error, "That verification link is missing its token.")
    |> redirect(to: ~p"/p/pocs/#{public_token}")
  end

  def session(conn, %{"public_token" => public_token, "request_id" => request_id}) do
    with %{} = poc <- POCs.get_poc_by_public_token(public_token),
         %AccessRequest{} = request <- POCs.get_access_request(request_id),
         true <- request.poc_id == poc.id,
         true <- AccessRequest.active?(request) do
      # Persisted in the Plug session (a signed cookie itself) so the LiveView
      # sees the value in its `mount/3` session map. The signed value carries
      # the (poc_id, request_id) pair, and every render re-validates the
      # request row so a later revocation takes effect instantly.
      value = POCs.sign_session_cookie(poc, request)

      conn
      |> put_session(session_cookie_name(poc), value)
      |> redirect(to: ~p"/p/pocs/#{public_token}")
    else
      _ ->
        conn
        |> put_flash(:error, "Access is not yet granted.")
        |> redirect(to: ~p"/p/pocs/#{public_token}")
    end
  end

  def session_cookie_name(poc), do: "poc_session_" <> poc.id
end
