defmodule Atlas.Slack.Workers.RespondToConversationSchedulingTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Repo
  alias Atlas.Slack.Workers.RespondToConversation
  alias Oban.Job

  @worker_name Oban.Worker.to_string(RespondToConversation)

  test "cancels queued jobs when a newer message arrives in the same thread" do
    event1 = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000001.100000"}
    event2 = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    assert :ok = RespondToConversation.start_or_replace(event1, :company, nil)
    assert_enqueued(worker: RespondToConversation, args: %{"message_ts" => "1710000001.100000"})

    assert :ok = RespondToConversation.start_or_replace(event2, :company, nil)

    jobs =
      Repo.all(
        from job in Job,
          where: job.worker == ^@worker_name
      )

    cancelled_job = Enum.find(jobs, &(&1.args["message_ts"] == "1710000001.100000"))
    newer_job = Enum.find(jobs, &(&1.args["message_ts"] == "1710000002.100000"))

    assert cancelled_job.state == "cancelled"
    assert newer_job.state == "available"
  end

  test "does not start a duplicate task for the same Slack message timestamp" do
    event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000001.100000"}

    assert :ok = RespondToConversation.start_or_replace(event, :company, nil)
    assert :ok = RespondToConversation.start_or_replace(event, :company, nil)

    jobs =
      Repo.all(
        from job in Job,
          where: job.worker == ^@worker_name
      )

    assert 1 == Enum.count(jobs, &(&1.args["message_ts"] == "1710000001.100000"))
  end

  test "ignores older out-of-order deliveries once a newer message is known" do
    older_event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000001.100000"}
    newer_event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    assert :ok = RespondToConversation.start_or_replace(newer_event, :company, nil)
    assert :ok = RespondToConversation.start_or_replace(older_event, :company, nil)

    jobs =
      Repo.all(
        from job in Job,
          where: job.worker == ^@worker_name
      )

    assert 1 ==
             Enum.count(jobs, fn job ->
               job.args["channel_id"] == "C123" and
                 job.args["thread_ts"] == "1710000000.100000"
             end)
  end
end
