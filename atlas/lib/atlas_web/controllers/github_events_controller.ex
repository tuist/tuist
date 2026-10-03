defmodule AtlasWeb.GitHubEventsController do
  use AtlasWeb, :controller

  alias Atlas.Integrations
  alias Atlas.Integrations.GitHubEvents

  require Logger

  def handle(conn, _params) do
    raw_body = conn.private[:raw_body]
    event_type = get_req_header(conn, "x-github-event") |> List.first()
    signature = get_req_header(conn, "x-hub-signature-256") |> List.first()

    with {:ok, apps} <- candidate_github_apps(conn.body_params),
         {:ok, github_app} <- verify_against_apps(apps, raw_body, signature) do
      GitHubEvents.handle_event(event_type, conn.body_params, github_app_id: github_app.id)
      json(conn, %{ok: true})
    else
      {:error, :no_webhook_secret} ->
        Logger.warning("GitHub event received but no app has a webhook secret configured")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})
    end
  end

  # The installation id in the body is unverified, so it only orders the
  # candidates: an app whose installation matches is tried first. Payloads that
  # carry no installation, or one Atlas has not stored, still get verified
  # against every configured secret rather than rejected outright.
  defp candidate_github_apps(payload) do
    installation_id = get_in(payload, ["installation", "id"])

    Integrations.list_github_apps()
    |> Enum.filter(&is_binary(&1.webhook_secret))
    |> Enum.sort_by(&(to_string(&1.installation_id) == to_string(installation_id)), :desc)
    |> case do
      [] -> {:error, :no_webhook_secret}
      apps -> {:ok, apps}
    end
  end

  defp verify_against_apps(apps, raw_body, signature) do
    Enum.find_value(apps, {:error, :invalid_signature}, fn app ->
      case GitHubEvents.verify_signature(raw_body, signature, app.webhook_secret) do
        :ok -> {:ok, app}
        {:error, _reason} -> nil
      end
    end)
  end
end
