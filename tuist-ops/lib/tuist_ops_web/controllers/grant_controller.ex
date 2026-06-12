defmodule TuistOpsWeb.GrantController do
  @moduledoc """
  The operator-facing surface for accessing a customer project.

  The customer `server/` redirects a non-member operator here to
  justify access; this controller records the reason, mints a signed
  grant, and redirects back to the original customer URL with the
  token in the query string. Pages are rendered with Noora via
  `TuistOpsWeb.GrantHTML`.

  ## Identity

  These routes sit behind Pomerium (Google Workspace OIDC). Identity
  comes from the signature Pomerium puts on each request — the
  `X-Pomerium-Jwt-Assertion` JWT, verified offline by `TuistOps.Pomerium`
  — NOT the forgeable `X-Pomerium-Claim-Email` header. There is no
  session. Locally (no Pomerium) identity falls back to
  `TUIST_OPS_DEV_OPERATOR_EMAIL`.

  ## Tiers

    * `read` — self-serve. Record the reason, mint the grant, redirect
      back immediately.
    * `admin` — create a pending request, post the Slack approval card,
      and show a page that re-checks on each load (a server-driven
      `Refresh`, no client JS) until a second human approves; then it
      302s back with the minted token.
  """

  use TuistOpsWeb, :controller

  alias TuistOps.Environment
  alias TuistOps.ProjectAccess.Approvals
  alias TuistOps.ProjectAccess.Policy
  alias TuistOps.ProjectAccess.Token

  require Logger

  # A verified Pomerium identity is required for every action. Without
  # it `pending/2` would 403 (request exists) vs 404 (doesn't), letting a
  # tailnet-direct caller (no assertion) enumerate request ids.
  plug :require_operator_identity

  @tiers ~w(read admin)
  # A valid account handle is the same charset the server validates names
  # against. Rejecting anything else keeps SQL LIKE wildcards (`%`/`_`)
  # out of the signed grant, so a grant can't bind to one account while
  # the audit/Slack trail shows a different (wildcard) string.
  @account_handle_regex ~r/^[a-zA-Z0-9-]+$/

  def new(conn, params) do
    subject = subject(conn)
    account = params["account"]
    return_to = params["return_to"]
    tier = if params["tier"] in @tiers, do: params["tier"], else: "read"

    cond do
      is_nil(subject) ->
        render_error(conn, 401, "Not authenticated", "No operator identity present.")

      is_nil(account) or is_nil(return_to) ->
        render_error(conn, 400, "Bad request", "Missing account or return_to.")

      not allowed_return_to?(return_to) ->
        render_error(conn, 400, "Bad request", "return_to is not an allowed destination.")

      true ->
        render(conn, :new,
          subject: subject,
          account: account,
          return_to: return_to,
          tier: tier,
          error: nil
        )
    end
  end

  def create(conn, params) do
    subject = subject(conn)
    account = params["account_handle"]
    return_to = params["return_to"]
    tier = params["tier"]
    reason = params |> Map.get("reason", "") |> to_string() |> String.trim()
    ttl_seconds = parse_ttl(params["ttl_minutes"])

    cond do
      is_nil(subject) ->
        render_error(conn, 401, "Not authenticated", "No operator identity present.")

      not Policy.requester_allowed?(subject) ->
        render_error(conn, 403, "Forbidden", "This identity is not permitted to request access.")

      is_nil(account) or is_nil(return_to) or not allowed_return_to?(return_to) ->
        render_error(conn, 400, "Bad request", "Missing or invalid parameters.")

      not valid_account_handle?(account) ->
        render_error(conn, 400, "Bad request", "Invalid account handle.")

      tier not in @tiers ->
        render_error(conn, 400, "Bad request", "Unknown access tier.")

      String.length(reason) < 5 ->
        conn
        |> put_status(422)
        |> render(:new,
          subject: subject,
          account: account,
          return_to: return_to,
          tier: tier,
          error: "Please describe why you need access (at least 5 characters)."
        )

      true ->
        grant_or_request(conn, subject, account, return_to, tier, reason, ttl_seconds)
    end
  end

  def pending(conn, %{"id" => id}) do
    subject = subject(conn)

    case Approvals.get_request(id) do
      nil ->
        render_error(conn, 404, "Not found", "No such request.")

      req ->
        # Case-insensitive: the requester_email was captured from the same
        # Pomerium claim, but don't 403 a legitimate operator on case drift.
        if emails_match?(req.requester_email, subject) do
          render_pending(conn, req)
        else
          render_error(conn, 403, "Forbidden", "This request belongs to another operator.")
        end
    end
  end

  # --- request handling --------------------------------------------------

  defp grant_or_request(conn, subject, account, return_to, "read", reason, ttl_seconds) do
    case Approvals.request_access(%{
           tier: "read",
           requester_email: subject,
           account_handle: account,
           reason: reason,
           return_to: return_to,
           ttl_seconds: ttl_seconds
         }) do
      {:ok, :granted, grant} ->
        redirect(conn, external: append_grant(return_to, Token.mint(grant)))

      {:error, reason} ->
        Logger.warning("project_access: read grant failed: #{inspect(reason)}")
        render_error(conn, 500, "Error", "Could not grant access. Try again.")
    end
  end

  defp grant_or_request(conn, subject, account, return_to, "admin", reason, ttl_seconds) do
    case Approvals.request_access(%{
           tier: "admin",
           requester_email: subject,
           account_handle: account,
           reason: reason,
           return_to: return_to,
           ttl_seconds: ttl_seconds,
           slack_channel_id: Environment.approvals_channel_id()
         }) do
      {:ok, :pending, request} ->
        redirect(conn, to: "/grants/#{request.id}/pending")

      {:error, reason} ->
        Logger.warning("project_access: admin request failed: #{inspect(reason)}")
        render_error(conn, 500, "Error", "Could not submit the request. Try again.")
    end
  end

  # The pending page carries no client JS. While the request is pending it
  # reloads itself via a `Refresh` response header and re-checks here; on
  # approval we mint the grant and 302 back to the customer URL (same as the
  # read tier). Denied/expired render a terminal message with no refresh
  # header, so the page stops reloading.
  defp render_pending(conn, %{status: "approved", return_to: return_to} = req) do
    case Approvals.active_grant_for_request(req.id) do
      %{} = grant -> redirect(conn, external: append_grant(return_to, Token.mint(grant)))
      _ -> render_waiting(conn, req)
    end
  end

  defp render_pending(conn, %{status: "denied"} = req),
    do: render(conn, :pending, account: req.account_handle, state: :denied)

  defp render_pending(conn, %{status: "expired"} = req),
    do: render(conn, :pending, account: req.account_handle, state: :expired)

  defp render_pending(conn, req), do: render_waiting(conn, req)

  defp render_waiting(conn, req) do
    conn
    |> put_resp_header("refresh", "3")
    |> render(:pending, account: req.account_handle, state: :pending)
  end

  defp render_error(conn, status, title, message) do
    conn
    |> put_status(status)
    |> render(:error, title: title, message: message)
  end

  # --- identity + validation --------------------------------------------

  defp require_operator_identity(conn, _opts) do
    if subject(conn) do
      conn
    else
      conn |> render_error(401, "Not authenticated", "No operator identity present.") |> halt()
    end
  end

  defp subject(conn), do: TuistOps.Pomerium.verified_email(conn)

  defp emails_match?(a, b) when is_binary(a) and is_binary(b),
    do: String.downcase(a) == String.downcase(b)

  defp emails_match?(_, _), do: false

  defp valid_account_handle?(handle),
    do: is_binary(handle) and Regex.match?(@account_handle_regex, handle)

  defp parse_ttl(nil), do: nil

  defp parse_ttl(value) when is_binary(value) do
    case Integer.parse(value) do
      {minutes, _} when minutes > 0 -> minutes * 60
      _ -> nil
    end
  end

  defp parse_ttl(_), do: nil

  defp allowed_return_to?(url) when is_binary(url) do
    uri = URI.parse(url)

    Enum.any?(Environment.project_access_return_to_allowlist(), fn allowed ->
      a = URI.parse(allowed)
      uri.scheme == a.scheme and uri.host == a.host and uri.port == a.port
    end)
  end

  defp allowed_return_to?(_), do: false

  defp append_grant(return_to, token) do
    uri = URI.parse(return_to)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("operator_grant", token)
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end
end
