defmodule Atlas.Slack.Workers.RespondToConversationTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.Channel
  alias Atlas.Slack.ConversationResponder
  alias Atlas.Slack.Workers.RespondToConversation

  setup :verify_on_exit!

  test "cancels before responding when a newer thread message already exists" do
    older_event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000001.100000"}
    newer_event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    assert :ok = RespondToConversation.start_or_replace(newer_event, :company, nil)

    job =
      build_job(RespondToConversation, %{
        "event" => older_event,
        "slack_app" => "company",
        "channel_id" => "C123",
        "thread_ts" => "1710000000.100000",
        "message_ts" => "1710000001.100000",
        "message_ts_micros" => 1_710_000_001_100_000
      })

    reject(&ConversationResponder.respond/4)

    assert {:cancel, :superseded} = RespondToConversation.perform(job)
  end

  test "passes a current? guard into the responder" do
    event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    job =
      build_job(RespondToConversation, %{
        "event" => event,
        "slack_app" => "company",
        "channel_id" => "C123",
        "thread_ts" => "1710000000.100000",
        "message_ts" => "1710000002.100000",
        "message_ts_micros" => 1_710_000_002_100_000
      })

    stub(Slack, :find_channel, fn :company, "C123" -> nil end)
    stub(API, :get_channel_info, fn :company, "C123" -> {:error, "channel_not_found"} end)

    expect(ConversationResponder, :respond, fn ^event, :company, nil, opts ->
      assert is_function(opts[:current?], 0)
      assert opts[:current?].() == true
      :ok
    end)

    assert :ok = RespondToConversation.perform(job)
  end

  test "falls back to Slack channel info when the channel is not tracked locally" do
    event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    job =
      build_job(RespondToConversation, %{
        "event" => event,
        "slack_app" => "company",
        "channel_id" => "C123",
        "thread_ts" => "1710000000.100000",
        "message_ts" => "1710000002.100000",
        "message_ts_micros" => 1_710_000_002_100_000
      })

    stub(Slack, :find_channel, fn :company, "C123" -> nil end)

    expect(API, :get_channel_info, fn :company, "C123" ->
      {:ok,
       %{
         slack_channel_id: "C123",
         name: "internal",
         is_shared: false,
         is_ext_shared: false
       }}
    end)

    expect(ConversationResponder, :respond, fn ^event, :company, %Channel{} = channel, opts ->
      assert channel.channel_id == "C123"
      assert channel.channel_name == "internal"
      assert channel.is_shared == false
      assert is_function(opts[:current?], 0)
      :ok
    end)

    assert :ok = RespondToConversation.perform(job)
  end

  test "tells the responder it is not the final attempt while retries remain" do
    event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    job =
      build_job(
        RespondToConversation,
        %{
          "event" => event,
          "slack_app" => "company",
          "channel_id" => "C123",
          "thread_ts" => "1710000000.100000",
          "message_ts" => "1710000002.100000",
          "message_ts_micros" => 1_710_000_002_100_000
        },
        attempt: 1,
        max_attempts: 3
      )

    stub(Slack, :find_channel, fn :company, "C123" -> nil end)
    stub(API, :get_channel_info, fn :company, "C123" -> {:error, "channel_not_found"} end)

    expect(ConversationResponder, :respond, fn ^event, :company, nil, opts ->
      assert opts[:final?] == false
      {:error, :overloaded}
    end)

    assert {:error, :overloaded} = RespondToConversation.perform(job)
  end

  test "tells the responder it is the final attempt on the last try" do
    event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    job =
      build_job(
        RespondToConversation,
        %{
          "event" => event,
          "slack_app" => "company",
          "channel_id" => "C123",
          "thread_ts" => "1710000000.100000",
          "message_ts" => "1710000002.100000",
          "message_ts_micros" => 1_710_000_002_100_000
        },
        attempt: 3,
        max_attempts: 3
      )

    stub(Slack, :find_channel, fn :company, "C123" -> nil end)
    stub(API, :get_channel_info, fn :company, "C123" -> {:error, "channel_not_found"} end)

    expect(ConversationResponder, :respond, fn ^event, :company, nil, opts ->
      assert opts[:final?] == true
      :ok
    end)

    assert :ok = RespondToConversation.perform(job)
  end

  test "cancels permanently when the LLM is not configured" do
    event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    job =
      build_job(RespondToConversation, %{
        "event" => event,
        "slack_app" => "company",
        "channel_id" => "C123",
        "thread_ts" => "1710000000.100000",
        "message_ts" => "1710000002.100000",
        "message_ts_micros" => 1_710_000_002_100_000
      })

    stub(Slack, :find_channel, fn :company, "C123" -> nil end)
    stub(API, :get_channel_info, fn :company, "C123" -> {:error, "channel_not_found"} end)

    expect(ConversationResponder, :respond, fn ^event, :company, nil, _opts ->
      {:error, :llm_not_configured}
    end)

    assert {:cancel, :llm_not_configured} = RespondToConversation.perform(job)
  end

  test "cancels permanent language model provider errors without retrying" do
    event = %{"channel" => "C123", "thread_ts" => "1710000000.100000", "ts" => "1710000002.100000"}

    job =
      build_job(
        RespondToConversation,
        %{
          "event" => event,
          "slack_app" => "company",
          "channel_id" => "C123",
          "thread_ts" => "1710000000.100000",
          "message_ts" => "1710000002.100000",
          "message_ts_micros" => 1_710_000_002_100_000
        },
        attempt: 1,
        max_attempts: 3
      )

    stub(Slack, :find_channel, fn :company, "C123" -> nil end)
    stub(API, :get_channel_info, fn :company, "C123" -> {:error, "channel_not_found"} end)

    expect(ConversationResponder, :respond, fn ^event, :company, nil, opts ->
      assert opts[:final?] == false
      {:error, {:api_error, %{status: 402, body: %{"error" => "credit_limit"}}}}
    end)

    assert {:cancel, :llm_credit_limit} = RespondToConversation.perform(job)
  end
end
