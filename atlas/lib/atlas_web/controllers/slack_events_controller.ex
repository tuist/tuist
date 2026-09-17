defmodule AtlasWeb.SlackEventsController do
  use AtlasWeb, :controller

  alias Atlas.Slack
  alias Atlas.Slack.Bot
  alias Atlas.Slack.Events, as: SlackEvents
  alias Atlas.Slack.Installation
  alias Atlas.Slack.Interactions

  require Logger

  def handle(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def handle(conn, %{"type" => "event_callback", "event" => event} = payload) do
    raw_body = conn.private[:raw_body]
    timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
    signature = get_req_header(conn, "x-slack-signature") |> List.first()

    with :ok <- verify_timestamp(timestamp),
         :ok <- verify_signature(raw_body, timestamp, signature),
         {:ok, slack_app} <- resolve_slack_app(payload) do
      event = put_authorized_user_ids(event, payload)

      SlackEvents.handle_event(event, slack_app)
      json(conn, %{ok: true})
    else
      {:error, :stale_timestamp} ->
        conn |> put_status(:unauthorized) |> json(%{error: "stale timestamp"})

      {:error, :no_signing_secret} ->
        Logger.warning("Slack event received but no Slack signing secret is configured")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})

      {:error, :unknown_team} ->
        json(conn, %{ok: true})
    end
  end

  def handle(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "unknown event type"})
  end

  def interactions(conn, %{"payload" => raw_payload}) when is_binary(raw_payload) do
    raw_body = conn.private[:raw_body]
    timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
    signature = get_req_header(conn, "x-slack-signature") |> List.first()

    with :ok <- verify_timestamp(timestamp),
         :ok <- verify_signature(raw_body, timestamp, signature),
         {:ok, payload} <- JSON.decode(raw_payload),
         {:ok, slack_app} <- resolve_slack_app(payload),
         {:ok, message} <- Interactions.handle_interaction(payload, slack_app) do
      json(conn, %{response_type: "ephemeral", text: message})
    else
      {:error, :stale_timestamp} ->
        conn |> put_status(:unauthorized) |> json(%{error: "stale timestamp"})

      {:error, :no_signing_secret} ->
        Logger.warning("Slack interaction received but no Slack signing secret is configured")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})

      {:error, :unknown_team} ->
        json(conn, %{response_type: "ephemeral", text: "Slack action ignored."})

      {:error, %JSON.DecodeError{}} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid payload"})

      {:error, message} when is_binary(message) ->
        json(conn, %{response_type: "ephemeral", text: message})
    end
  end

  def interactions(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing payload"})
  end

  defp verify_timestamp(nil), do: {:error, :stale_timestamp}

  defp verify_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, _} ->
        now = System.system_time(:second)

        if abs(now - ts) < 300 do
          :ok
        else
          {:error, :stale_timestamp}
        end

      :error ->
        {:error, :stale_timestamp}
    end
  end

  defp verify_signature(raw_body, timestamp, signature) do
    case Bot.signing_secret() do
      signing_secret when is_binary(signing_secret) and signing_secret != "" ->
        SlackEvents.verify_signature(raw_body, timestamp, signature, signing_secret)

      _signing_secret ->
        {:error, :no_signing_secret}
    end
  end

  # The request signature has already been verified against the app-wide signing
  # secret at this point, so the payload is authentic. We only look up the
  # installation to decide whether the workspace was explicitly disconnected
  # (in which case we stop handling its events) versus never installed / a
  # legacy single-workspace deployment (which we still record as :company).
  defp resolve_slack_app(payload) do
    team_id = team_id_from_payload(payload)

    case Slack.find_installation_by_team_id(team_id) do
      %Installation{disconnected_at: nil, app_key: app_key} -> {:ok, app_key}
      %Installation{} -> {:error, :unknown_team}
      nil -> fallback_app(team_id)
    end
  end

  # A workspace with no installation row falls back to the legacy :company app
  # so events keep flowing before the install completes. When an allowlist is
  # configured (ATLAS_SLACK_ALLOWED_TEAM_IDS), the same Slack app installed in
  # any other workspace must not be processed against company channels, so only
  # allowlisted teams fall back; everything else is rejected.
  defp fallback_app(team_id) do
    case Bot.allowed_team_ids() do
      [] -> {:ok, :company}
      allowed -> if is_binary(team_id) and team_id in allowed, do: {:ok, :company}, else: {:error, :unknown_team}
    end
  end

  defp team_id_from_payload(payload) when is_map(payload) do
    payload["team_id"] ||
      get_in(payload, ["team", "id"]) ||
      Enum.find_value(Map.get(payload, "authorizations", []), & &1["team_id"]) ||
      get_in(payload, ["event", "team"])
  end

  defp team_id_from_payload(_payload), do: nil

  defp put_authorized_user_ids(event, payload) do
    event = put_team_id(event, payload)

    authorized_user_ids =
      payload
      |> Map.get("authorizations", [])
      |> Enum.map(& &1["user_id"])
      |> Kernel.++(Map.get(payload, "authed_users", []))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case authorized_user_ids do
      [] -> event
      ids -> Map.put(event, "atlas_authorized_user_ids", ids)
    end
  end

  defp put_team_id(event, payload) do
    team_id =
      payload["team_id"] ||
        Enum.find_value(Map.get(payload, "authorizations", []), & &1["team_id"]) ||
        event["team"]

    case team_id do
      team_id when is_binary(team_id) -> Map.put(event, "atlas_team_id", team_id)
      _team_id -> event
    end
  end
end
