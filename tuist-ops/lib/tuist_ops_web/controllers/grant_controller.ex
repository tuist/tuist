defmodule TuistOpsWeb.GrantController do
  @moduledoc """
  The operator-facing surface for accessing a customer project.

  The customer `server/` redirects a non-member operator here to
  justify access; this controller records the reason, mints a signed
  grant, and redirects back to the original customer URL with the
  token in the query string.

  ## Identity

  These routes sit behind Pomerium (Google Workspace OIDC), which
  sets `X-Pomerium-Claim-Email`. That header IS the operator identity
  — there is no session. Locally (no Pomerium) the identity falls
  back to `TUIST_OPS_DEV_OPERATOR_EMAIL`.

  ## Tiers

    * `read` — self-serve. Record the reason, mint the grant, redirect
      back immediately.
    * `admin` — create a pending request, post the Slack approval
      card, and show a small page that polls `/grants/:id/status`
      until a second human approves; then it redirects back with the
      minted token. No LiveView — a plain poll keeps this service free
      of an asset pipeline.

  Rendered as plain HTML via `Phoenix.Controller.html/2` (this app has
  no view layer); all interpolated user input is escaped.
  """

  use TuistOpsWeb, :controller

  alias TuistOps.Environment
  alias TuistOps.ProjectAccess.Approvals
  alias TuistOps.ProjectAccess.Token

  require Logger

  @tiers ~w(read admin)

  def new(conn, params) do
    subject = subject(conn)
    account = params["account"]
    return_to = params["return_to"]
    tier = if params["tier"] in @tiers, do: params["tier"], else: "read"

    cond do
      is_nil(subject) ->
        conn
        |> put_status(401)
        |> html(error_page("Not authenticated", "No operator identity present."))

      is_nil(account) or is_nil(return_to) ->
        conn
        |> put_status(400)
        |> html(error_page("Bad request", "Missing account or return_to."))

      not allowed_return_to?(return_to) ->
        conn
        |> put_status(400)
        |> html(error_page("Bad request", "return_to is not an allowed destination."))

      true ->
        html(conn, form_page(subject, account, return_to, tier, nil))
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
        conn
        |> put_status(401)
        |> html(error_page("Not authenticated", "No operator identity present."))

      is_nil(account) or is_nil(return_to) or not allowed_return_to?(return_to) ->
        conn
        |> put_status(400)
        |> html(error_page("Bad request", "Missing or invalid parameters."))

      tier not in @tiers ->
        conn |> put_status(400) |> html(error_page("Bad request", "Unknown access tier."))

      String.length(reason) < 5 ->
        conn
        |> put_status(422)
        |> html(
          form_page(
            subject,
            account,
            return_to,
            tier,
            "Please describe why you need access (at least 5 characters)."
          )
        )

      true ->
        grant_or_request(conn, subject, account, return_to, tier, reason, ttl_seconds)
    end
  end

  def pending(conn, %{"id" => id}) do
    subject = subject(conn)

    case Approvals.get_request(id) do
      %{requester_email: ^subject} = req when not is_nil(subject) ->
        html(conn, pending_page(req))

      nil ->
        conn |> put_status(404) |> html(error_page("Not found", "No such request."))

      _ ->
        conn
        |> put_status(403)
        |> html(error_page("Forbidden", "This request belongs to another operator."))
    end
  end

  def status(conn, %{"id" => id}) do
    subject = subject(conn)

    case Approvals.get_request(id) do
      %{requester_email: ^subject} = req when not is_nil(subject) ->
        json(conn, status_payload(req))

      nil ->
        conn |> put_status(404) |> json(%{status: "not_found"})

      _ ->
        conn |> put_status(403) |> json(%{status: "forbidden"})
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
        conn |> put_status(500) |> html(error_page("Error", "Could not grant access. Try again."))
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

        conn
        |> put_status(500)
        |> html(error_page("Error", "Could not submit the request. Try again."))
    end
  end

  defp status_payload(%{status: "approved", return_to: return_to} = req) do
    case Approvals.active_grant_for_request(req.id) do
      nil -> %{status: "pending"}
      grant -> %{status: "approved", redirect: append_grant(return_to, Token.mint(grant))}
    end
  end

  defp status_payload(%{status: status}), do: %{status: status}

  # --- identity + validation --------------------------------------------

  defp subject(conn) do
    case get_req_header(conn, "x-pomerium-claim-email") do
      [email | _] when is_binary(email) and byte_size(email) > 0 -> email
      _ -> Environment.dev_operator_email()
    end
  end

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

  # --- HTML (no view layer; escape every interpolation) -----------------

  defp form_page(subject, account, return_to, tier, error) do
    error_html =
      if error, do: ~s(<p class="error">#{esc(error)}</p>), else: ""

    read_checked = if tier == "admin", do: "", else: "checked"
    admin_checked = if tier == "admin", do: "checked", else: ""

    page("Access #{esc(account)}", """
    <h1>Access <code>#{esc(account)}</code></h1>
    <p>Signed in as <strong>#{esc(subject)}</strong>. Tell us why you need to access this customer's project. The reason is recorded and auditable.</p>
    #{error_html}
    <form method="post" action="/grants">
      <input type="hidden" name="account_handle" value="#{esc(account)}" />
      <input type="hidden" name="return_to" value="#{esc(return_to)}" />

      <fieldset>
        <legend>Access level</legend>
        <label><input type="radio" name="tier" value="read" #{read_checked} /> Read — view the dashboard (granted immediately)</label>
        <label><input type="radio" name="tier" value="admin" #{admin_checked} /> Admin — act as an admin (needs Slack approval)</label>
      </fieldset>

      <label>Duration (minutes)
        <input type="number" name="ttl_minutes" min="1" value="30" />
      </label>

      <label>Reason
        <textarea name="reason" rows="3" placeholder="e.g. investigating a failing build reported in ticket #123" required></textarea>
      </label>

      <button type="submit">Continue</button>
    </form>
    """)
  end

  defp pending_page(req) do
    page("Waiting for approval", """
    <h1>Waiting for approval</h1>
    <p>Your request for <strong>admin</strong> access to <code>#{esc(req.account_handle)}</code> is pending. A second person needs to approve it in Slack.</p>
    <p id="state" class="muted">Waiting…</p>
    <script>
      const id = "#{req.id}";
      async function poll() {
        try {
          const r = await fetch("/grants/" + id + "/status", {headers: {"Accept": "application/json"}});
          const j = await r.json();
          if (j.status === "approved" && j.redirect) { window.location = j.redirect; return; }
          if (j.status === "denied") { document.getElementById("state").textContent = "Request denied."; return; }
          if (j.status === "expired") { document.getElementById("state").textContent = "Request expired. Start again."; return; }
        } catch (e) {}
        setTimeout(poll, 2500);
      }
      poll();
    </script>
    """)
  end

  defp error_page(title, message) do
    page(title, "<h1>#{esc(title)}</h1><p>#{esc(message)}</p>")
  end

  defp page(title, body) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>#{esc(title)} · Tuist Ops</title>
      <style>
        body { font-family: -apple-system, system-ui, sans-serif; max-width: 36rem; margin: 4rem auto; padding: 0 1rem; color: #1a1a1a; }
        h1 { font-size: 1.4rem; }
        code { background: #f2f2f2; padding: 0.1rem 0.3rem; border-radius: 4px; }
        form { display: grid; gap: 1rem; margin-top: 1.5rem; }
        fieldset { border: 1px solid #ddd; border-radius: 8px; }
        label { display: block; }
        textarea, input[type=number] { width: 100%; box-sizing: border-box; margin-top: 0.25rem; }
        button { padding: 0.6rem 1rem; border: 0; border-radius: 8px; background: #6f4cff; color: #fff; font-size: 1rem; cursor: pointer; }
        .error { color: #b00020; }
        .muted { color: #777; }
      </style>
    </head>
    <body>#{body}</body>
    </html>
    """
  end

  defp esc(value), do: value |> to_string() |> Plug.HTML.html_escape()
end
