defmodule TuistWeb.Webhooks.GitHubController do
  use TuistWeb, :controller

  alias Tuist.Automations
  alias Tuist.Environment
  alias Tuist.Runners.Workers.DispatchWorker
  alias Tuist.Tests
  alias Tuist.VCS

  require Logger

  @doc """
  Resolves the HMAC signing secret for an inbound GitHub webhook and,
  when a per-installation row owns the request, stashes it on
  `conn.assigns[:github_installation]` so post-HMAC handlers don't
  redo a potentially-ambiguous lookup.

  Two ways an installation gets a webhook secret:

    * **Per-installation** — manifest-flow registrations (GHES) persist
      `webhook_secret` directly on the `GitHubAppInstallation` row,
      Cloak-encrypted. Each customer's GHES App has its own secret.

    * **Global env var** — github.com installations leave
      `webhook_secret` `nil` and rely on
      `TUIST_GITHUB_APP_WEBHOOK_SECRET`, which is the secret of the
      single Tuist App registered on github.com.

  Strategy: gather every row that could plausibly own the request
  (matching `installation.id` from the body and/or the App ID from
  `installation.app_id` / `X-GitHub-Hook-Installation-Target-ID`) and
  iterate them, computing the HMAC of the raw body against each row's
  `webhook_secret`. The row whose signature matches GitHub's is the
  one that owns the request — `webhook_secret` is the natural
  disambiguator because it's a per-row cryptographic capability, so
  even when the schema permits two rows to share an
  `(installation_id, app_id)` pair across different `client_url`s
  (the composite unique index is per host), the right row is the
  unique one whose secret verifies.

  github.com webhooks have no matching per-installation row (their
  `webhook_secret` is nil), so they fall through to the env var; HMAC
  verification then runs against that.
  """
  def resolve_webhook_secret(conn) do
    body = conn.body_params
    installation_id = body_get(body, ["installation", "id"])
    app_id = app_id_from_request(conn, body)

    case find_matching_installation(conn, installation_id, app_id) do
      {:ok, installation} ->
        {:ok, installation.webhook_secret, assign(conn, :github_installation, installation)}

      :error ->
        # No per-installation row matches. Fall back to the env var so
        # github.com webhooks (and any unsigned-by-us deliveries) still
        # get HMAC-checked.
        Environment.github_app_webhook_secret()
    end
  end

  defp find_matching_installation(_conn, nil, nil), do: :error

  defp find_matching_installation(conn, installation_id, app_id) do
    raw_body = conn.assigns[:raw_body] |> List.wrap() |> IO.iodata_to_binary()
    signature = conn |> get_req_header("x-hub-signature-256") |> List.first()

    candidates =
      VCS.list_github_app_installations_for_webhook(
        installation_id && to_string(installation_id),
        app_id && to_string(app_id)
      )

    Enum.find_value(candidates, :error, fn installation ->
      if is_binary(installation.webhook_secret) and
           webhook_signature_matches?(raw_body, installation.webhook_secret, signature) do
        {:ok, installation}
      end
    end)
  end

  defp webhook_signature_matches?(_raw_body, _secret, nil), do: false

  defp webhook_signature_matches?(raw_body, secret, signature) do
    expected =
      "sha256=" <>
        (:hmac
         |> :crypto.mac(:sha256, secret, raw_body)
         |> Base.encode16(case: :lower))

    Plug.Crypto.secure_compare(signature, expected)
  end

  # Looks up the installation by `installation_id`, disambiguating with
  # the App ID from the body or the `X-GitHub-Hook-Installation-Target-ID`
  # header. The composite unique index on
  # `(client_url, installation_id)` means two GitHub instances can have
  # rows sharing an `installation_id`, so a disambiguator is required.
  #
  # Three branches, depending on what we know about the App ID:
  #
  #   * Request App ID matches `Environment.github_app_id()` → it's a
  #     github.com webhook. github.com rows leave `app_id` NULL (the
  #     runtime falls back to `TUIST_GITHUB_APP_*` env vars), so an
  #     `app_id = ?` filter would miss them. Pin by
  #     `client_url='https://github.com'`.
  #
  #   * `Environment.github_app_id()` is `nil` (self-hosted instance
  #     without a configured github.com App ID) → we can't tell the
  #     two cases apart from the header alone. Try the github.com row
  #     first, fall back to an `app_id` lookup. github.com is the more
  #     common deployment, so the first try usually wins.
  #
  #   * Otherwise → it's a GHES App registered via the manifest flow.
  #     Pin by `app_id`. (Cross-instance `app_id` collisions on the
  #     same `installation_id` are theoretically possible but require
  #     two unrelated GHES instances to assign overlapping numeric IDs
  #     to the Apps registered for this Tuist deployment; the schema
  #     allows it but the chance is very low. If it ever happens, the
  #     HMAC step at `resolve_webhook_secret/1` is the next-line
  #     disambiguator — only one row's `webhook_secret` will verify.)
  defp lookup_installation_by_id(conn, body, installation_id) do
    case conn.assigns[:github_installation] do
      nil ->
        lookup_installation_by_id_uncached(conn, body, installation_id)

      installation ->
        # `resolve_webhook_secret/1` already picked the row by HMAC
        # verification — trust that result rather than redoing a
        # potentially-ambiguous DB lookup here. We deliberately do NOT
        # gate this on `installation.installation_id == installation_id`
        # because the manifest-flow bootstrap race (the `installation.created`
        # webhook arriving before the redirect-driven setup callback)
        # leaves the row's `installation_id` nil while the body carries
        # the freshly-assigned one. Falling through to a DB lookup keyed
        # on the body's id would miss the pending row entirely.
        {:ok, installation}
    end
  end

  defp lookup_installation_by_id_uncached(conn, body, installation_id) do
    case app_id_from_request(conn, body) do
      nil ->
        VCS.get_github_app_installation_by_installation_id(installation_id)

      app_id ->
        app_id_string = to_string(app_id)
        env_app_id = Environment.github_app_id()

        cond do
          env_app_id == app_id_string ->
            VCS.get_github_app_installation_by_installation_id(
              installation_id,
              client_url: VCS.default_client_url()
            )

          is_nil(env_app_id) ->
            github_com_or_app_id_lookup(installation_id, app_id_string)

          true ->
            VCS.get_github_app_installation_by_installation_id(
              installation_id,
              app_id: app_id_string
            )
        end
    end
  end

  defp github_com_or_app_id_lookup(installation_id, app_id) do
    case VCS.get_github_app_installation_by_installation_id(
           installation_id,
           client_url: VCS.default_client_url()
         ) do
      {:ok, _} = ok ->
        ok

      {:error, :not_found} ->
        VCS.get_github_app_installation_by_installation_id(installation_id, app_id: app_id)
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

      "issues" ->
        handle_issues(conn, params)

      "workflow_job" ->
        handle_workflow_job(conn, params)

      _ ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})
    end
  end

  # Hand off to the `:webhooks` Oban queue and acknowledge to
  # GitHub immediately. The synchronous variant of this handler
  # (account lookup + K8s LIST + ClickHouse INSERT inside the
  # request) caused the 2026-05-19 incident: every webhook held
  # a Phoenix worker for the full 10 s GitHub timeout while
  # downstream stalled, so the HTTP body-read pool saturated and
  # the ingress started 5xx-ing.
  #
  # Failure modes after this change:
  #
  #   * Payload missing `installation.id` → 200 OK, no enqueue.
  #     GitHub won't redeliver and there's nothing to dispatch
  #     against — same shape as the previous `:ignored` branch.
  #   * `Oban.insert/1` returns `{:error, _}` → 503 so GitHub
  #     retries. Only triggers if PG is unreachable, which
  #     would have us 503-ing anyway.
  #   * Worker errors → Oban retries with backoff up to
  #     `max_attempts`. The HTTP layer is done.
  # Actions that the dispatch pipeline persists or claims against.
  # `Tuist.Runners.Dispatch.handle_webhook/2` only branches on these
  # two — every other action (notably `in_progress`, ~33 % of
  # `workflow_job` traffic) falls through to the catch-all
  # `:ignored` branch in the worker. Short-circuiting here removes
  # the Oban.insert (and its Postgres write) for those events,
  # which under burst load was costing us ~one PG checkout per
  # webhook for work the worker was going to discard anyway.
  @dispatchable_workflow_job_actions ~w(queued completed)

  defp handle_workflow_job(conn, params) do
    installation_id =
      case params do
        %{"installation" => %{"id" => id}} when is_integer(id) -> id
        _ -> nil
      end

    delivery_guid = conn |> get_req_header("x-github-delivery") |> List.first()
    action = Map.get(params, "action")

    cond do
      is_nil(installation_id) ->
        conn |> put_status(:ok) |> json(%{status: "ok"})

      action not in @dispatchable_workflow_job_actions ->
        conn |> put_status(:ok) |> json(%{status: "ok"})

      true ->
        enqueue_dispatch(conn, params, installation_id, delivery_guid)
    end
  end

  defp enqueue_dispatch(conn, params, installation_id, delivery_guid) do
    args = %{
      "payload" => params,
      "installation_id" => installation_id,
      "delivery_guid" => delivery_guid
    }

    case args |> DispatchWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        conn |> put_status(:ok) |> json(%{status: "ok"})

      {:error, reason} ->
        Logger.warning("runners: failed to enqueue dispatch worker; returning 503",
          reason: inspect(reason)
        )

        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", reason: "transient"})
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

  defp handle_issues(
         conn,
         %{
           "action" => "closed",
           "issue" => %{"number" => issue_number},
           "repository" => %{"full_name" => repository_full_name},
           "installation" => %{"id" => installation_id}
         } = params
       ) do
    with {:ok, installation} <-
           lookup_installation_by_id(conn, params, to_string(installation_id)),
         {:ok, link} <-
           Automations.get_issue_link_by_github_coordinates(
             installation.id,
             repository_full_name,
             issue_number
           ),
         {:ok, link} <- Automations.resolve_issue_link(link),
         {:ok, test_case} <- Tests.get_test_case_by_id(link.test_case_id) do
      Automations.dispatch_issue_link_event(:closed, link, test_case)
    else
      {:error, :not_found} ->
        # Either no installation row, no IssueLink (issue wasn't created by
        # us), or the test_case no longer exists. All are normal no-ops.
        :ok

      other ->
        Logger.warning("GitHub issues.closed webhook handling failed: #{inspect(other)}")
        :ok
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_issues(conn, _params) do
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
        # Manifest-flow bootstrap race: when this webhook arrives before
        # the redirect-driven setup callback has filled the row's
        # `installation_id`, fill it from the body alongside the
        # html_url. Without this, the pending row stays orphaned with
        # `installation_id: nil` because the setup callback's
        # update path never runs (the user's browser already redirected
        # past it).
        attrs =
          if is_nil(github_app_installation.installation_id) do
            %{html_url: html_url, installation_id: installation_id}
          else
            %{html_url: html_url}
          end

        VCS.update_github_app_installation(github_app_installation, attrs)

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
