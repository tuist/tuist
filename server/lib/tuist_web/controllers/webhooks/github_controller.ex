defmodule TuistWeb.Webhooks.GitHubController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.VCS

  require Logger

  @doc """
  Resolves the HMAC signing secret for an inbound GitHub webhook.

  Two ways an installation gets a webhook secret:

    * **Per-installation** — manifest-flow registrations (GHES) persist
      `webhook_secret` directly on the `GitHubAppInstallation` row,
      Cloak-encrypted. Each customer's GHES App has its own secret.

    * **Global env var** — github.com installations leave
      `webhook_secret` `nil` and rely on
      `TUIST_GITHUB_APP_WEBHOOK_SECRET`, which is the secret of the
      single Tuist App registered on github.com.

  Strategy: prefer the per-installation secret when a row exposes one,
  otherwise fall back to the env var. We try to locate a row two ways:

    1. By `installation.id` from the body — covers the steady state
       for GHES installations (once the post-install setup callback
       has filled `installation_id`). For github.com webhooks this
       step also finds the row, but its `webhook_secret` is `nil`,
       so we fall through.

    2. By App ID alone — covers the bootstrap race for a brand new
       GHES App: the manifest exchange has persisted `app_id` and
       `webhook_secret` but the setup callback hasn't filled
       `installation_id` yet, so step 1 misses. The App ID comes from
       `installation.app_id` in the body or the
       `X-GitHub-Hook-Installation-Target-ID` header.

    3. If neither yields a secret, fall back to the env var.

  github.com webhooks always land on step 3 (their rows carry no
  per-installation secret); GHES webhooks always resolve at step 1 or
  2. HMAC verification then rejects anything whose signature doesn't
  match the resolved secret.
  """
  def resolve_webhook_secret(conn) do
    body = conn.body_params

    cond do
      secret = lookup_secret_by_installation_id(conn, body) -> secret
      secret = lookup_secret_by_app_id(conn, body) -> secret
      true -> Environment.github_app_webhook_secret()
    end
  end

  defp lookup_secret_by_installation_id(conn, body) do
    with id when not is_nil(id) <- body_get(body, ["installation", "id"]),
         {:ok, installation} <- lookup_installation_by_id(conn, body, to_string(id)),
         secret when is_binary(secret) <- installation.webhook_secret do
      secret
    else
      _ -> nil
    end
  end

  defp lookup_secret_by_app_id(conn, body) do
    with id when not is_nil(id) <- app_id_from_request(conn, body),
         {:ok, installation} <- VCS.get_github_app_installation_by_app_id(to_string(id)),
         secret when is_binary(secret) <- installation.webhook_secret do
      secret
    else
      _ -> nil
    end
  end

  # Looks up the installation by `installation_id`, additionally pinning
  # the row by `app_id` (from the body or the
  # `X-GitHub-Hook-Installation-Target-ID` header) when present. The
  # composite unique index on `(client_url, installation_id)` means two
  # GitHub instances can have rows sharing an `installation_id`; pinning
  # by `app_id` keeps the lookup unambiguous.
  defp lookup_installation_by_id(conn, body, installation_id) do
    case app_id_from_request(conn, body) do
      nil -> VCS.get_github_app_installation_by_installation_id(installation_id)
      app_id -> VCS.get_github_app_installation_by_installation_id(installation_id, app_id: to_string(app_id))
    end
  end

  defp app_id_from_request(conn, body) do
    body_get(body, ["installation", "app_id"]) ||
      conn |> get_req_header("x-github-hook-installation-target-id") |> List.first()
  end

  defp body_get(body, [a, b]) do
    get_in(body, [a, b]) || get_in(body, [String.to_existing_atom(a), String.to_existing_atom(b)])
  rescue
    ArgumentError -> nil
  end

  def handle(conn, params) do
    event_type = conn |> get_req_header("x-github-event") |> List.first()

    case event_type do
      "installation" ->
        handle_installation(conn, params)

      "check_run" ->
        handle_check_run(conn, params)

      _ ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})
    end
  end

  defp handle_installation(conn, %{"action" => "deleted", "installation" => %{"id" => installation_id}} = params) do
    {:ok, _} = delete_github_app_installation(conn, params, installation_id)

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_installation(
         conn,
         %{"action" => "created", "installation" => %{"id" => installation_id, "html_url" => html_url}} = params
       ) do
    case update_github_app_installation_html_url_with_retry(conn, params, installation_id, html_url) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})

      {:error, :not_found_after_retries} ->
        # After retries, the installation still doesn't exist. This indicates a broken user flow:
        # 1. The setup callback failed or was never called
        # 2. The user closed the browser before completing setup
        # 3. Network issues prevented the redirect
        # This means the installation exists in GitHub but not in our database,
        # creating an orphaned installation that requires manual reconciliation.
        Logger.error(
          "GitHub installation.created webhook for installation_id=#{installation_id} but installation not found after retries. Setup callback may have failed. Manual intervention may be required."
        )

        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})
    end
  end

  defp handle_installation(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_check_run(
         conn,
         %{
           "action" => "requested_action",
           "check_run" => %{"id" => check_run_id, "name" => "tuist/bundle-size"},
           "requested_action" => %{"identifier" => "accept_bundle_size"},
           "installation" => %{"id" => installation_id},
           "repository" => %{"full_name" => repository_full_name}
         } = params
       ) do
    installation_id = to_string(installation_id)

    with {:ok, installation} <- lookup_installation_by_id(conn, params, installation_id) do
      VCS.update_check_run(%{
        repository_full_handle: repository_full_name,
        check_run_id: check_run_id,
        installation: installation,
        conclusion: "success",
        output: %{
          title: "Bundle size increase accepted",
          summary: "The bundle size increase was manually accepted."
        }
      })
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_check_run(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp delete_github_app_installation(conn, body, installation_id) do
    case lookup_installation_by_id(conn, body, installation_id) do
      {:ok, github_app_installation} ->
        VCS.delete_github_app_installation(github_app_installation)

      {:error, :not_found} ->
        {:ok, :already_deleted}
    end
  end

  defp update_github_app_installation_html_url(conn, body, installation_id, html_url) do
    case lookup_installation_by_id(conn, body, installation_id) do
      {:ok, github_app_installation} ->
        VCS.update_github_app_installation(github_app_installation, %{html_url: html_url})

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp update_github_app_installation_html_url_with_retry(conn, body, installation_id, html_url, attempt \\ 1) do
    max_attempts = 3
    retry_delay_ms = 1000

    case update_github_app_installation_html_url(conn, body, installation_id, html_url) do
      {:ok, result} ->
        {:ok, result}

      {:error, :not_found} when attempt < max_attempts ->
        Logger.info(
          "GitHub installation not found for installation_id=#{installation_id}, attempt #{attempt}/#{max_attempts}. Retrying in #{retry_delay_ms}ms..."
        )

        Process.sleep(retry_delay_ms)
        update_github_app_installation_html_url_with_retry(conn, body, installation_id, html_url, attempt + 1)

      {:error, :not_found} ->
        {:error, :not_found_after_retries}
    end
  end
end
