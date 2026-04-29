defmodule TuistWeb.GitHubAppManifestController do
  @moduledoc """
  Implements GitHub's [App manifest registration flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
  so a Tuist organization can stand up a brand new GitHub App on its own
  GitHub Enterprise Server (GHES) instance — Tuist Cloud cannot install
  its own github.com App on a GHES instance, since GitHub Apps are scoped
  to a single GitHub instance.

  Two-step flow:

  1. `start/2` — auth-required HTML page that auto-POSTs a manifest to
     `<ghes>/settings/apps/new`. The manifest carries Tuist's webhook URL
     and required permissions; the customer reviews and clicks Create on
     GHES, which generates the App's credentials.

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
  alias TuistWeb.Errors.BadRequestError

  require Logger

  @app_name "tuist"
  @app_description "Tuist insights, analytics, and PR feedback for your repositories."

  def start(conn, %{"state" => state_token}) when is_binary(state_token) do
    case VCS.verify_github_state_token(state_token) do
      {:ok, %{client_url: client_url}} ->
        if client_url == VCS.default_client_url() do
          raise BadRequestError, dgettext("dashboard", "Manifest flow is only available for GitHub Enterprise Server.")
        end

        manifest = manifest_payload(client_url)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, render_auto_submit(client_url, manifest, state_token))

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

  defp manifest_payload(_client_url) do
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

  defp render_auto_submit(client_url, manifest, state_token) do
    manifest_json = Jason.encode!(manifest)
    action = "#{client_url}/settings/apps/new?state=#{URI.encode_www_form(state_token)}"

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Redirecting to GitHub Enterprise Server…</title>
      </head>
      <body>
        <p>Redirecting to GitHub Enterprise Server to register the Tuist app…</p>
        <form id="manifest-form" action="#{Plug.HTML.html_escape(action)}" method="post">
          <input type="hidden" name="manifest" value="#{Plug.HTML.html_escape(manifest_json)}" />
          <noscript>
            <button type="submit">Continue</button>
          </noscript>
        </form>
        <script>document.getElementById('manifest-form').submit();</script>
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
          {:error, "Manifest conversion failed (HTTP #{status}): #{inspect(body)}"}

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
      {:ok, existing} -> VCS.replace_github_app_installation(existing, attrs)
      {:error, :not_found} -> VCS.create_github_app_installation(attrs)
    end
  end
end
