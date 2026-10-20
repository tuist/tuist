defmodule Atlas.Slack.ConversationResponder do
  @moduledoc """
  Streams Slack thread responses into threaded Slack messages.
  """

  alias Atlas.Agents.Sessions
  alias Atlas.LLMs.Errors, as: LLMErrors
  alias Atlas.LLMs.Runner
  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.Bot
  alias Atlas.Slack.ConversationAgent

  require Logger

  @update_interval_ms 900
  @min_update_chars 80
  @no_reply_token "[[NO_REPLY]]"

  def respond(event, app_key, channel, opts \\ [])

  def respond(%{"channel" => channel_id, "ts" => event_ts} = event, app_key, channel, opts)
      when is_binary(channel_id) and is_binary(event_ts) do
    app_key = normalize_app_key(app_key)
    thread_ts = event["thread_ts"] || event_ts
    slack_user = resolve_slack_user(app_key, event["user"])
    account = ConversationAgent.account_from_channel(channel)
    current? = Keyword.get(opts, :current?, fn -> true end)
    final? = Keyword.get(opts, :final?, true)

    reply_context = %{
      event: event,
      app_key: app_key,
      channel_id: channel_id,
      thread_ts: thread_ts,
      account: account,
      current?: current?
    }

    with :ok <- ensure_current(current?),
         {:ok, llm} <- Runner.fetch_config(),
         :ok <- set_status(app_key, channel_id, thread_ts, "is working on this request...", loading_messages()),
         {:ok, _text} <- stream_reply(channel, slack_user, llm, reply_context) do
      clear_status(app_key, channel_id, thread_ts)
    else
      {:error, :superseded} ->
        {:error, :superseded}

      {:error, :llm_not_configured} = error ->
        clear_status(app_key, channel_id, thread_ts)

        post_error(
          app_key,
          channel_id,
          thread_ts,
          "Language model is not configured. Set LLM_API_KEY and LLM_MODEL on the server."
        )

        error

      {:error, reason} = error ->
        clear_status(app_key, channel_id, thread_ts)
        Logger.warning("Slack conversation responder failed: #{inspect(reason)}")

        cond do
          LLMErrors.hard_failure?(reason) ->
            post_error(app_key, channel_id, thread_ts, "Language model provider is currently unavailable.")
            error

          final? ->
            post_error(app_key, channel_id, thread_ts, "I could not complete that request.")
            :ok

          true ->
            error
        end
    end
  end

  def respond(_event, _app_key, _channel, _opts), do: :ignored

  defp stream_reply(channel, slack_user, llm, reply_context) do
    %{
      event: event,
      app_key: app_key,
      channel_id: channel_id,
      thread_ts: thread_ts,
      account: account,
      current?: current?
    } =
      reply_context

    thread_messages = load_thread_messages(event, app_key, channel_id, thread_ts)
    client_opts = Runner.client_opts(llm)

    slack_session_opts =
      client_opts
      |> Keyword.put(:requester_slack_user, slack_user)
      |> Keyword.put(:thread_ts, thread_ts)

    opts =
      client_opts ++
        [
          load_project_instructions: false,
          max_turns: 8
        ] ++
        ConversationAgent.slack_session_options(app_key, channel, slack_session_opts)

    prompt = ConversationAgent.build_prompt(event, channel, slack_user, thread_messages)

    opts =
      if account do
        Keyword.put(opts, :account_id, account.id)
      else
        opts
      end

    Sessions.with_session(ConversationAgent, prompt, opts, fn condukt_opts ->
      Condukt.Session.with_transient(ConversationAgent, condukt_opts, fn agent ->
        agent
        |> Condukt.stream(prompt)
        |> Enum.reduce_while(initial_state(), fn stream_event, state ->
          handle_stream_event(stream_event, state, event, app_key, channel_id, thread_ts, account, current?)
        end)
        |> finalize_stream_result(event, app_key, channel_id, thread_ts, account, current?)
      end)
    end)
  end

  defp handle_stream_event({:text, chunk}, state, event, app_key, channel_id, thread_ts, account, current?)
       when is_binary(chunk) do
    case ensure_current(current?) do
      :ok ->
        state = %{state | text: state.text <> chunk}

        if should_update?(state) do
          state = flush_response(state, event, app_key, channel_id, thread_ts, account, "Responding")

          if state.error do
            {:halt, state}
          else
            {:cont, state}
          end
        else
          {:cont, state}
        end

      {:error, :superseded} ->
        {:halt, %{state | error: :superseded}}
    end
  end

  defp handle_stream_event(
         {:tool_call, name, _id, _args},
         state,
         event,
         app_key,
         channel_id,
         thread_ts,
         account,
         current?
       ) do
    case ensure_current(current?) do
      :ok ->
        tool_name = name |> to_string() |> String.replace("_", " ")
        status = "Using #{tool_name}"
        set_status(app_key, channel_id, thread_ts, "is #{String.downcase(status)}...", loading_messages())

        state =
          state
          |> Map.put(:status, status)
          |> flush_response(event, app_key, channel_id, thread_ts, account, status)

        if state.error do
          {:halt, state}
        else
          {:cont, state}
        end

      {:error, :superseded} ->
        {:halt, %{state | error: :superseded}}
    end
  end

  defp handle_stream_event(
         {:tool_result, _id, _result},
         state,
         event,
         app_key,
         channel_id,
         thread_ts,
         account,
         current?
       ) do
    case ensure_current(current?) do
      :ok ->
        set_status(app_key, channel_id, thread_ts, "is reading the result...", loading_messages())

        state = flush_response(state, event, app_key, channel_id, thread_ts, account, "Reading result")

        if state.error do
          {:halt, state}
        else
          {:cont, state}
        end

      {:error, :superseded} ->
        {:halt, %{state | error: :superseded}}
    end
  end

  defp handle_stream_event(
         {:error, :no_result_submitted},
         %{text: text} = state,
         _event,
         _app_key,
         _channel_id,
         _thread_ts,
         _account,
         _current?
       )
       when is_binary(text) do
    if String.trim(text) == "" do
      {:halt, %{state | error: :no_result_submitted}}
    else
      Logger.warning("Slack conversation stream finished without a submitted result; keeping streamed text")
      {:halt, state}
    end
  end

  defp handle_stream_event({:error, reason}, state, _event, _app_key, _channel_id, _thread_ts, _account, _current?) do
    {:halt, %{state | error: reason}}
  end

  defp handle_stream_event(:done, state, _event, _app_key, _channel_id, _thread_ts, _account, current?) do
    case ensure_current(current?) do
      :ok -> {:halt, state}
      {:error, :superseded} -> {:halt, %{state | error: :superseded}}
    end
  end

  defp handle_stream_event(_stream_event, state, _event, _app_key, _channel_id, _thread_ts, _account, _current?),
    do: {:cont, state}

  defp finalize_stream_result(%{error: nil} = state, event, app_key, channel_id, thread_ts, account, current?) do
    case ensure_current(current?) do
      :ok ->
        case String.trim(state.text) do
          @no_reply_token ->
            clear_partial_response(state, app_key, channel_id)
            {:ok, :no_reply}

          _text ->
            state = flush_response(state, event, app_key, channel_id, thread_ts, account, "Done", force: true)

            with %{error: nil, text: text} <- state,
                 text when text != "" <- String.trim(text),
                 :ok <- stop_response(state, app_key, channel_id) do
              {:ok, text}
            else
              %{error: reason} -> {:error, reason}
              "" -> {:error, :empty_response}
              {:error, reason} -> {:error, reason}
            end
        end

      {:error, :superseded} ->
        clear_partial_response(state, app_key, channel_id)
        {:error, :superseded}
    end
  end

  defp finalize_stream_result(
         %{error: :superseded} = state,
         _event,
         app_key,
         channel_id,
         _thread_ts,
         _account,
         _current?
       ) do
    clear_partial_response(state, app_key, channel_id)
    {:error, :superseded}
  end

  defp finalize_stream_result(%{error: reason}, _event, _app_key, _channel_id, _thread_ts, _account, _current?),
    do: {:error, reason}

  defp ensure_current(current?) when is_function(current?, 0) do
    if current?.() do
      :ok
    else
      {:error, :superseded}
    end
  end

  defp ensure_current(_current?), do: :ok

  defp flush_response(state, event, app_key, channel_id, thread_ts, account, status, _opts \\ []) do
    delta = pending_text(state)

    if String.trim(delta) == "" do
      state
    else
      state
      |> do_flush_response(delta, event, app_key, channel_id, thread_ts, account, status)
      |> mark_updated()
    end
  end

  defp do_flush_response(%{mode: nil} = state, delta, event, app_key, channel_id, thread_ts, account, status) do
    stream_opts = [
      markdown_text: delta,
      recipient_user_id: event["user"],
      recipient_team_id: event["atlas_team_id"]
    ]

    case API.start_stream(app_key, channel_id, thread_ts, stream_opts) do
      {:ok, %{"ts" => stream_ts}} when is_binary(stream_ts) ->
        %{state | mode: :stream, stream_ts: stream_ts}

      {:ok, response} ->
        Logger.warning("Slack stream start did not include a timestamp: #{inspect(response)}")
        start_update_fallback(state, app_key, channel_id, thread_ts, account, status)

      {:error, reason} ->
        Logger.warning("Slack stream start failed, falling back to message updates: #{inspect(reason)}")
        start_update_fallback(state, app_key, channel_id, thread_ts, account, status)
    end
  end

  defp do_flush_response(
         %{mode: :stream, stream_ts: stream_ts} = state,
         delta,
         _event,
         app_key,
         channel_id,
         _thread_ts,
         _account,
         _status
       ) do
    case API.append_stream(app_key, channel_id, stream_ts, delta) do
      {:ok, _response} -> state
      {:error, reason} -> %{state | error: reason}
    end
  end

  defp do_flush_response(
         %{mode: :update, reply_ts: reply_ts} = state,
         _delta,
         _event,
         app_key,
         channel_id,
         _thread_ts,
         account,
         status
       ) do
    case update_reply(app_key, channel_id, reply_ts, state.text, account, status) do
      {:ok, _response} -> state
      {:error, reason} -> %{state | error: reason}
    end
  end

  defp start_update_fallback(state, app_key, channel_id, thread_ts, account, status) do
    text = non_empty_text(state.text, "Working on it...")

    case API.post_message(
           app_key,
           channel_id,
           text,
           ConversationAgent.blocks_for_text(text, account: account, status: status),
           thread_ts: thread_ts
         ) do
      {:ok, %{"ts" => reply_ts}} when is_binary(reply_ts) ->
        %{state | mode: :update, reply_ts: reply_ts}

      {:ok, response} ->
        %{state | error: {:missing_reply_ts, response}}

      {:error, reason} ->
        %{state | error: reason}
    end
  end

  defp stop_response(%{mode: :stream, stream_ts: stream_ts}, app_key, channel_id) when is_binary(stream_ts) do
    case API.stop_stream(app_key, channel_id, stream_ts) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning("Slack stream stop failed: #{inspect(reason)}")
        :ok
    end
  end

  defp stop_response(%{mode: :update}, _app_key, _channel_id), do: :ok
  defp stop_response(%{mode: nil}, _app_key, _channel_id), do: {:error, :empty_response}

  defp clear_partial_response(%{mode: :stream, stream_ts: stream_ts}, app_key, channel_id) when is_binary(stream_ts) do
    _ = API.stop_stream(app_key, channel_id, stream_ts, markdown_text: "")
    :ok
  end

  defp clear_partial_response(%{mode: :update, reply_ts: reply_ts}, app_key, channel_id) when is_binary(reply_ts) do
    _ = API.update_message(app_key, channel_id, reply_ts, "", [])
    :ok
  end

  defp clear_partial_response(_state, _app_key, _channel_id), do: :ok

  defp set_status(app_key, channel_id, thread_ts, status, loading_messages) do
    case API.set_assistant_thread_status(app_key, channel_id, thread_ts, status, loading_messages: loading_messages) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Slack assistant status update failed: #{inspect(reason)}")
        :ok
    end
  end

  defp clear_status(app_key, channel_id, thread_ts) do
    set_status(app_key, channel_id, thread_ts, "", [])
  end

  defp update_reply(app_key, channel_id, reply_ts, text, account, status) do
    text = non_empty_text(text, "Working on it...")

    API.update_message(
      app_key,
      channel_id,
      reply_ts,
      text,
      ConversationAgent.blocks_for_text(text, account: account, status: status)
    )
  end

  defp post_error(app_key, channel_id, thread_ts, message) do
    API.post_message(
      app_key,
      channel_id,
      message,
      ConversationAgent.error_blocks(message),
      thread_ts: thread_ts
    )
  end

  defp resolve_slack_user(_app_key, nil), do: nil

  defp resolve_slack_user(app_key, user_id) when is_binary(user_id) do
    case Slack.get_user(app_key, user_id) do
      nil ->
        case API.get_user_info(app_key, user_id) do
          {:ok, profile} ->
            case Slack.upsert_user(app_key, Map.delete(profile, :raw)) do
              {:ok, user} -> user
              {:error, _reason} -> nil
            end

          {:error, _reason} ->
            nil
        end

      user ->
        user
    end
  end

  defp load_thread_messages(%{"atlas_thread_messages" => thread_messages}, _app_key, _channel_id, _thread_ts)
       when is_list(thread_messages) do
    thread_messages
  end

  defp load_thread_messages(_event, app_key, channel_id, thread_ts) do
    case API.list_thread_messages(app_key, channel_id, thread_ts) do
      {:ok, thread_messages} ->
        thread_messages

      {:error, reason} ->
        Logger.warning("Failed to load Slack thread transcript for #{channel_id}/#{thread_ts}: #{inspect(reason)}")
        []
    end
  end

  defp normalize_app_key(app_key) do
    Bot.normalize_app_key!(app_key)
  end

  defp should_update?(%{text: text, last_text: last_text, last_update_ms: last_update_ms}) do
    enough_text? = String.length(text) - String.length(last_text) >= @min_update_chars
    enough_time? = System.monotonic_time(:millisecond) - last_update_ms >= @update_interval_ms
    enough_text? and enough_time?
  end

  defp pending_text(%{text: text, last_text: last_text}) do
    String.replace_prefix(text, last_text, "")
  end

  defp mark_updated(%{text: text} = state) do
    %{state | last_text: text, last_update_ms: System.monotonic_time(:millisecond)}
  end

  defp initial_state do
    %{
      text: "",
      last_text: "",
      status: "Working",
      error: nil,
      last_update_ms: 0,
      mode: nil,
      stream_ts: nil,
      reply_ts: nil
    }
  end

  defp loading_messages do
    [
      "Checking Atlas context",
      "Reading recent activity",
      "Preparing the response"
    ]
  end

  defp non_empty_text(text, fallback) do
    case String.trim(text || "") do
      "" -> fallback
      text -> text
    end
  end
end
