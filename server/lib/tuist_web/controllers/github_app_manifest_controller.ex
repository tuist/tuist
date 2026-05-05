defmodule TuistWeb.GitHubAppManifestController do
  @moduledoc """
  Implements GitHub's [App manifest registration flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
  so a Tuist organization can stand up a brand new GitHub App on its own
  GitHub Enterprise Server (GHES) instance — Tuist Cloud cannot install
  its own github.com App on a GHES instance, since GitHub Apps are scoped
  to a single GitHub instance.

  Two-step flow:

  1. `start/2` — public HTML page that auto-POSTs a manifest to
     `<ghes>/settings/apps/new`. The manifest carries Tuist's webhook URL
     and required permissions; the customer reviews and clicks Create on
     GHES, which generates the App's credentials. Authorization is
     enforced by the signed Phoenix.Token in the `state` query
     parameter, not by the route pipeline — anyone with a valid token
     for an account is by definition authorized to start the flow.

  2. `callback/2` — public endpoint GHES redirects the customer back to
     with a temporary `code`. We exchange the code for the App's
     permanent credentials (app_id, client_id, client_secret, private_key,
     webhook_secret) and persist them in a pending `GitHubAppInstallation`
     row keyed on `account_id`. The customer is then redirected to the
     App's install URL on the GHES instance.

  After install, GitHub fires the existing `/integrations/github/setup`
  callback, which fills in the pending row's `installation_id`.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation
  alias TuistWeb.CSP
  alias TuistWeb.Errors.BadRequestError

  require Logger

  @app_name "tuist"
  @app_description "Tuist insights, analytics, and PR feedback for your repositories."
  @manifest_secret_keys ~w(pem client_secret webhook_secret)

  def start(conn, %{"state" => state_token}) when is_binary(state_token) do
    case VCS.verify_github_state_token(state_token) do
      {:ok, %{client_url: client_url}} ->
        if client_url == VCS.default_client_url() do
          raise BadRequestError, dgettext("dashboard", "Manifest flow is only available for GitHub Enterprise Server.")
        end

        manifest = manifest_payload()
        nonce = CSP.get_csp_nonce()
        body = render_auto_submit(client_url, manifest, state_token, nonce)

        conn
        |> override_csp_for_manifest_post(client_url, nonce)
        |> put_resp_content_type("text/html")
        |> send_resp(200, body)

      {:error, _reason} ->
        raise BadRequestError, dgettext("dashboard", "Invalid manifest registration request.")
    end
  end

  def start(_conn, _params) do
    raise BadRequestError, dgettext("dashboard", "Missing manifest registration state.")
  end

  def callback(conn, %{"code" => code, "state" => state_token}) when is_binary(code) and is_binary(state_token) do
    with {:ok, %{account_id: account_id, client_url: client_url}} <- VCS.verify_github_state_token(state_token),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, app} <- exchange_manifest_code(client_url, code),
         {:ok, installation} <- upsert_installation(account, client_url, app) do
      install_state = VCS.generate_github_state_token(account.id, client_url)
      install_url = "#{client_url}/apps/#{installation.app_slug}/installations/new?state=#{install_state}"
      redirect(conn, external: install_url)
    else
      {:error, :invalid} ->
        raise BadRequestError, dgettext("dashboard", "Invalid manifest registration request.")

      {:error, :not_found} ->
        raise BadRequestError, dgettext("dashboard", "Account not found.")

      {:error, :existing_installation_in_use} ->
        raise BadRequestError,
              dgettext(
                "dashboard",
                "This account already has a GitHub app installation. Uninstall it before registering a new one."
              )

      {:error, reason} when is_binary(reason) ->
        Logger.error("GitHub App manifest exchange failed: #{reason}")
        raise BadRequestError, dgettext("dashboard", "Could not complete the GitHub App registration.")

      {:error, reason} ->
        Logger.error("GitHub App manifest exchange failed: #{inspect(reason)}")
        raise BadRequestError, dgettext("dashboard", "Could not complete the GitHub App registration.")
    end
  end

  def callback(_conn, _params) do
    raise BadRequestError, dgettext("dashboard", "Invalid manifest registration request.")
  end

  defp manifest_payload do
    callback_url = Environment.app_url(path: ~p"/integrations/github/manifest/callback")
    setup_url = Environment.app_url(path: ~p"/integrations/github/setup")
    webhook_url = Environment.app_url(path: "/webhooks/github")

    %{
      name: @app_name,
      url: Environment.app_url(),
      description: @app_description,
      hook_attributes: %{url: webhook_url, active: true},
      redirect_url: callback_url,
      callback_urls: [callback_url],
      setup_url: setup_url,
      setup_on_update: true,
      public: false,
      default_permissions: %{
        contents: "read",
        issues: "write",
        pull_requests: "write",
        checks: "write",
        metadata: "read"
      },
      default_events: ["check_run", "pull_request", "issue_comment", "installation"]
    }
  end

  # Override the global CSP for this single response so the auto-submit
  # works:
  #
  #   * `script-src` keeps the inline submit script alive — the global
  #     policy already allows `'nonce'`, but we restate it scoped to
  #     this response so a future global tightening doesn't silently
  #     break the flow.
  #   * `form-action` whitelists the customer's GHES origin (the
  #     manifest must be POSTed to `<ghes>/settings/apps/new`); without
  #     this, the browser falls back to `default-src 'self'` and blocks
  #     the cross-origin form submission.
  defp override_csp_for_manifest_post(conn, client_url, nonce) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(client_url)

    ghes_origin =
      case {scheme, host, port} do
        {scheme, host, nil} when is_binary(scheme) and is_binary(host) -> "#{scheme}://#{host}"
        {scheme, host, port} when is_binary(scheme) and is_binary(host) -> "#{scheme}://#{host}:#{port}"
        _ -> ""
      end

    csp =
      "default-src 'self'; " <>
        "script-src 'self' 'nonce-#{nonce}'; " <>
        "form-action 'self' #{ghes_origin}; " <>
        "base-uri 'self'"

    put_resp_header(conn, "content-security-policy", csp)
  end

  defp render_auto_submit(client_url, manifest, state_token, nonce) do
    manifest_json = Jason.encode!(manifest)
    action = "#{client_url}/settings/apps/new?state=#{URI.encode_www_form(state_token)}"

    redirecting_text =
      dgettext("dashboard_integrations", "Redirecting to GitHub Enterprise Server to register the Tuist app…")

    title_text = dgettext("dashboard_integrations", "Redirecting to GitHub Enterprise Server")
    continue_text = dgettext("dashboard_integrations", "Continue")

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>#{Plug.HTML.html_escape(title_text)}</title>
      </head>
      <body>
        <p>#{Plug.HTML.html_escape(redirecting_text)}</p>
        <form id="manifest-form" action="#{Plug.HTML.html_escape(action)}" method="post">
          <input type="hidden" name="manifest" value="#{Plug.HTML.html_escape(manifest_json)}" />
          <noscript>
            <button type="submit">#{Plug.HTML.html_escape(continue_text)}</button>
          </noscript>
        </form>
        <script nonce="#{nonce}">document.getElementById('manifest-form').submit();</script>
      </body>
    </html>
    """
  end

  defp exchange_manifest_code(client_url, code) do
    api_url = VCS.api_url(:github, client_url)
    url = "#{api_url}/app-manifests/#{code}/conversions"

    with {:ok, pinned_url, hostname} <- SSRFGuard.pin(url) do
      case Req.post(
             url: pinned_url,
             headers: [
               {"Accept", "application/vnd.github+json"},
               {"X-GitHub-Api-Version", "2022-11-28"}
             ],
             connect_options: SSRFGuard.connect_options(hostname)
           ) do
        {:ok, %Req.Response{status: status, body: %{"id" => _} = body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, "Manifest conversion failed (HTTP #{status}): #{redact_secrets(body)}"}

        {:error, reason} ->
          {:error, "Manifest conversion request failed: #{inspect(reason)}"}
      end
    end
  end

  defp upsert_installation(account, client_url, app) do
    attrs = %{
      account_id: account.id,
      client_url: client_url,
      app_id: to_string(app["id"]),
      app_slug: app["slug"],
      client_id: app["client_id"],
      client_secret: app["client_secret"],
      private_key: app["pem"],
      webhook_secret: app["webhook_secret"]
    }

    case VCS.get_github_app_installation_for_account(account.id) do
      {:ok, %GitHubAppInstallation{installation_id: installation_id}} when not is_nil(installation_id) ->
        # The account already has a working installation (github.com or a
        # different GHES instance). Refuse rather than silently overwrite
        # and break the existing integration.
        {:error, :existing_installation_in_use}

      {:ok, existing} ->
        # A pending row from a previous, abandoned manifest start —
        # safe to replace its credentials.
        VCS.replace_github_app_installation(existing, attrs)

      {:error, :not_found} ->
        VCS.create_github_app_installation(attrs)
    end
  end

  defp redact_secrets(body) when is_map(body) do
    body
    |> Map.new(fn
      {k, _v} when k in @manifest_secret_keys -> {k, "[REDACTED]"}
      pair -> pair
    end)
    |> inspect()
  end

  defp redact_secrets(body), do: inspect(body)
end
