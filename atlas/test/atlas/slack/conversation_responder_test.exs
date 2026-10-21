defmodule Atlas.Slack.ConversationResponderTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Agents.Sessions.Session
  alias Atlas.LLMs.Runner
  alias Atlas.Slack.API
  alias Atlas.Slack.Channel
  alias Atlas.Slack.ConversationResponder

  setup :verify_on_exit!

  defp event do
    %{"channel" => "C123", "ts" => "1710000001.100000"}
  end

  defp channel do
    %Channel{slack_app: :company, channel_id: "C123", channel_name: "general"}
  end

  test "posts the user-facing fallback in Slack on the final attempt when the LLM call fails" do
    stub(Runner, :fetch_config, fn -> {:error, :overloaded} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)

    expect(API, :post_message, fn :company,
                                  "C123",
                                  "I could not complete that request.",
                                  _blocks,
                                  [thread_ts: "1710000001.100000"] ->
      {:ok, %{"ts" => "1710000002.100000"}}
    end)

    assert :ok =
             ConversationResponder.respond(event(), :company, channel(),
               current?: fn -> true end,
               final?: true
             )
  end

  test "does not post the user-facing fallback while non-final retries remain" do
    stub(Runner, :fetch_config, fn -> {:error, :overloaded} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)

    reject(&API.post_message/5)

    assert {:error, :overloaded} =
             ConversationResponder.respond(event(), :company, channel(),
               current?: fn -> true end,
               final?: false
             )
  end

  test "posts one fallback immediately for permanent language model provider errors" do
    reason = {:api_error, %{status: 402, body: %{"error" => "credit_limit"}}}

    stub(Runner, :fetch_config, fn -> {:error, reason} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)

    expect(API, :post_message, fn :company,
                                  "C123",
                                  "Language model provider is currently unavailable.",
                                  _blocks,
                                  [thread_ts: "1710000001.100000"] ->
      {:ok, %{"ts" => "1710000002.100000"}}
    end)

    assert {:error, ^reason} =
             ConversationResponder.respond(event(), :company, channel(),
               current?: fn -> true end,
               final?: false
             )
  end

  test "delivers local-mode replies without using the Finch model streaming path" do
    text = "The request is handled."
    stub(Runner, :fetch_config, fn -> {:ok, %{mode: :local}} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)
    stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" -> {:ok, []} end)

    expect(Condukt, :run, fn agent, prompt, opts ->
      assert is_pid(agent)
      assert prompt =~ "Slack"
      assert opts[:max_turns] == 8
      {:ok, text}
    end)

    reject(&Condukt.stream/2)

    expect(API, :start_stream, fn :company, "C123", "1710000001.100000", opts ->
      assert opts[:markdown_text] == text
      {:ok, %{"ts" => "1710000002.100000"}}
    end)

    expect(API, :stop_stream, fn :company, "C123", "1710000002.100000" -> {:ok, %{}} end)
    reject(&API.post_message/5)

    assert :ok = ConversationResponder.respond(event(), :company, channel())
    assert %Session{status: "succeeded", result: %{"text" => ^text}} = Repo.one!(Session)
  end

  test "posts the fallback when local inference fails on the final attempt" do
    reason = %{status: 500}
    stub(Runner, :fetch_config, fn -> {:ok, %{mode: :local}} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)
    stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" -> {:ok, []} end)
    expect(Condukt, :run, fn _agent, _prompt, _opts -> {:error, reason} end)
    reject(&API.start_stream/4)

    expect(API, :post_message, fn :company, "C123", "I could not complete that request.", _blocks, _opts ->
      {:ok, %{"ts" => "1710000002.100000"}}
    end)

    assert :ok = ConversationResponder.respond(event(), :company, channel(), final?: true)
    assert %Session{status: "failed"} = Repo.one!(Session)
  end

  test "preserves retryable local inference failures before the final attempt" do
    stub(Runner, :fetch_config, fn -> {:ok, %{mode: :local}} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)
    stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" -> {:ok, []} end)
    expect(Condukt, :run, fn _agent, _prompt, _opts -> {:error, :timeout} end)
    reject(&API.start_stream/4)
    reject(&API.post_message/5)

    assert {:error, :timeout} = ConversationResponder.respond(event(), :company, channel(), final?: false)
    assert %Session{status: "failed"} = Repo.one!(Session)
  end

  test "treats a non-text local result as an empty response instead of crashing" do
    stub(Runner, :fetch_config, fn -> {:ok, %{mode: :local}} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)
    stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" -> {:ok, []} end)
    expect(Condukt, :run, fn _agent, _prompt, _opts -> {:ok, nil} end)
    reject(&API.start_stream/4)
    reject(&API.post_message/5)

    assert {:error, :empty_response} = ConversationResponder.respond(event(), :company, channel(), final?: false)
    assert %Session{status: "failed"} = Repo.one!(Session)
  end

  test "discards a buffered local reply superseded during generation" do
    stub(Runner, :fetch_config, fn -> {:ok, %{mode: :local}} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)
    stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" -> {:ok, []} end)

    expect(Condukt, :run, fn _agent, _prompt, _opts ->
      Process.put(:reply_superseded, true)
      {:ok, "A stale answer"}
    end)

    reject(&API.start_stream/4)
    reject(&API.post_message/5)

    assert {:error, :superseded} =
             ConversationResponder.respond(event(), :company, channel(),
               current?: fn -> not Process.get(:reply_superseded, false) end
             )
  end

  test "respects no-reply decisions in local mode" do
    stub(Runner, :fetch_config, fn -> {:ok, %{mode: :local}} end)
    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)
    stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" -> {:ok, []} end)
    expect(Condukt, :run, fn _agent, _prompt, _opts -> {:ok, "[[NO_REPLY]]"} end)
    reject(&API.start_stream/4)
    reject(&API.post_message/5)

    assert :ok = ConversationResponder.respond(event(), :company, channel())
  end

  test "keeps streamed text when the stream finishes without a submitted result" do
    text = "The latest production failure is HIVE-10."

    stub(Runner, :fetch_config, fn ->
      {:ok, %{model: "openai:gpt-4.1", api_key: "api-key"}}
    end)

    stub(API, :set_assistant_thread_status, fn :company, "C123", _thread_ts, _status, _opts -> :ok end)
    stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" -> {:ok, []} end)

    expect(Condukt, :stream, fn _agent, _prompt ->
      [{:text, text}, {:error, :no_result_submitted}]
    end)

    expect(API, :start_stream, fn :company, "C123", "1710000001.100000", opts ->
      assert Keyword.fetch!(opts, :markdown_text) == text
      {:ok, %{"ts" => "1710000002.100000"}}
    end)

    expect(API, :stop_stream, fn :company, "C123", "1710000002.100000" ->
      {:ok, %{"ts" => "1710000002.100000"}}
    end)

    reject(&API.post_message/5)

    assert :ok =
             ConversationResponder.respond(event(), :company, channel(),
               current?: fn -> true end,
               final?: true
             )
  end
end
