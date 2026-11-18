defmodule Atlas.Support.Workers.PostNotificationTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Repo
  alias Atlas.Slack.API
  alias Atlas.Support.Config
  alias Atlas.Support.Thread
  alias Atlas.Support.Workers.PostNotification

  setup :verify_on_exit!

  setup do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    thread =
      %Thread{}
      |> Thread.inbound_changeset(%{
        customer_email: "noreply@vendor.example",
        subject: "Package published",
        status: "resolved",
        last_message_at: now,
        resolved_at: now
      })
      |> Ecto.Changeset.put_change(:action_needed, false)
      |> Repo.insert!()

    stub(Config, :slack_channel_id, fn -> "C-SUPPORT" end)

    args = %{
      "event" => "inbound_received",
      "thread_id" => thread.id,
      "notification_id" => Ecto.UUID.generate()
    }

    %{args: args}
  end

  test "completes a no-action inbound without posting to Slack", %{args: args} do
    reject(&API.find_message_by_metadata/4)
    reject(&API.post_message/5)

    assert :ok = perform_job(PostNotification, args)
  end
end
