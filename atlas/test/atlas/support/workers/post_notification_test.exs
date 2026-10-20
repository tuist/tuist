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
    stub(Config, :slack_filtered_channel_id, fn -> "C-FILTERED" end)
    stub(API, :find_message_by_metadata, fn :company, _, _, _ -> {:ok, nil} end)

    args = %{
      "event" => "inbound_received",
      "thread_id" => thread.id,
      "notification_id" => Ecto.UUID.generate()
    }

    %{args: args}
  end

  test "uses the last delivery attempt to fall back for unknown filtered-channel errors", %{args: args} do
    expect(API, :post_message, fn :company, "C-FILTERED", _, _, _ -> {:error, "restricted_action"} end)

    expect(API, :post_message, fn :company, "C-SUPPORT", _, _, opts ->
      assert opts[:client_msg_id] == args["notification_id"]
      {:ok, %{"channel" => "C-SUPPORT", "ts" => "1724515200.000100"}}
    end)

    assert :ok = perform_job(PostNotification, args, attempt: 5, max_attempts: 5)
  end

  test "retries an unknown filtered-channel error before the last delivery attempt", %{args: args} do
    expect(API, :post_message, fn :company, "C-FILTERED", _, _, _ -> {:error, "restricted_action"} end)

    assert {:error, "restricted_action"} = perform_job(PostNotification, args, attempt: 1, max_attempts: 5)
  end
end
