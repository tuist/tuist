defmodule TuistOpsWeb.SlackEventsController do
  @moduledoc """
  Slack Events API endpoint (`POST /webhooks/slack/events`), signed
  and verified by `TuistOpsWeb.Plugs.SlackWebhookPlug`. The bot only
  subscribes to `app_mention`, which customer contacts use to page
  on-call (`TuistOps.Paging`). Work is queued so Slack gets its
  acknowledgement within three seconds.
  """

  use TuistOpsWeb, :controller

  alias TuistOps.Paging.Workers.PageWorker

  def create(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def create(conn, %{
        "type" => "event_callback",
        "event_id" => event_id,
        "event" => %{"type" => "app_mention"} = event
      }) do
    # Messages posted by bots, including our own replies, never page.
    if is_binary(event["user"]) and is_nil(event["bot_id"]) do
      {:ok, _job} = %{event_id: event_id, event: event} |> PageWorker.new() |> Oban.insert()
    end

    send_resp(conn, 200, "")
  end

  def create(conn, _params), do: send_resp(conn, 200, "")
end
