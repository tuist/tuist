defmodule TuistOpsWeb.SlackEventsControllerTest do
  use TuistOps.DataCase, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  alias TuistOps.Paging.Workers.PageWorker
  alias TuistOpsWeb.SlackEventsController

  defp post_event(params) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> SlackEventsController.create(params)
  end

  defp mention_event(event_id, event_overrides \\ %{}) do
    %{
      "type" => "event_callback",
      "event_id" => event_id,
      "event" =>
        Map.merge(
          %{
            "type" => "app_mention",
            "channel" => "C0BT0B97686",
            "user" => "U0CAROUSELL1",
            "ts" => "1795773300.658309",
            "text" => "<@U0TUISTOPS> builds are down"
          },
          event_overrides
        )
    }
  end

  defp page_jobs, do: Repo.all(from(j in Oban.Job, where: j.worker == ^inspect(PageWorker)))

  test "answers Slack's URL verification challenge" do
    conn = post_event(%{"type" => "url_verification", "challenge" => "abc123"})
    assert json_response(conn, 200) == %{"challenge" => "abc123"}
  end

  test "queues one page job per event, even when Slack retries it" do
    assert post_event(mention_event("Ev1")).status == 200
    assert post_event(mention_event("Ev1")).status == 200
    assert post_event(mention_event("Ev2")).status == 200

    assert page_jobs() |> Enum.map(& &1.args["event_id"]) |> Enum.sort() == ["Ev1", "Ev2"]
  end

  test "ignores mentions posted by bots" do
    post_event(mention_event("Ev3", %{"bot_id" => "B0BOT"}))
    assert page_jobs() == []
  end
end
