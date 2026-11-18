defmodule Condukt.Session.Durable do
  @moduledoc false
  # The part of a session that survives its process: which run is in flight,
  # the journal records that describe it, and what a restarted session does
  # with them.
  #
  # A journaled run writes one record per step, each before the step is shown
  # or acted on:
  #
  #   {:run_start, run_id, %{message: user_message, request_id: id, max_turns: n, base: fingerprint}}
  #   {:assistant, run_id, message}     a model response
  #   {:input, run_id, messages}        steering that joined the run
  #   {:tool_intent, run_id, %{call_id: id, replay_safe: boolean}}
  #                                     written before the tool runs
  #   {:tool_result, run_id, message}   in the order the calls finish
  #   {:messages, run_id, messages}     compaction replaced the history mid-run
  #   {:resume, run_id, nil}            a restarted session continued the run
  #   {:run_end, run_id, result}        the run ended, written before its snapshot
  #
  # The snapshot stays the record of finished runs. When a run ends the session
  # writes its end, saves the snapshot, stamped with the run's id, and only
  # then clears the journal, so a crash between the two leaves records that
  # recovery skips because the snapshot already covers their run. When the save
  # fails the journal is kept, and runs that start later append after it, so
  # recovery replays every run the snapshot does not cover, oldest first. A run
  # with an end is settled with the result it ended with, keeping every step it
  # stored, even where the live session dropped some, as it does for an aborted
  # run; only the newest run without an end is interrupted.
  #
  # A record that would let a step happen unrecorded must be stored before the
  # step: the prompt, each response, each tool intent. When storing one fails
  # the step does not happen. Results are stored best-effort: a call whose
  # result is missing reads as interrupted, which errs on the safe side.
  #
  # Run ids are integers that only grow within one store: the next id is one
  # past the largest the snapshot or the journal has seen. The first run after
  # the snapshot must also start from the snapshot's history, by `base`, so a
  # journal left behind by another history, as a restored backup has, is not
  # replayed onto it.

  alias Condukt.Message
  alias Condukt.SessionStore
  alias Condukt.SessionStore.Snapshot

  require Logger

  @default_restart_limit 5
  @max_requests 50

  defstruct enabled: false,
            restart_limit: @default_restart_limit,
            run_seq: 0,
            last_run_id: nil,
            requests: [],
            current: nil,
            interrupted: nil

  def default_restart_limit, do: @default_restart_limit

  @doc """
  Reads the journal of a store that has one and folds it over the restored
  snapshot.

  Returns `{:ok, durable, messages}`, where `messages` is the session's
  history: the snapshot's messages, followed by any finished runs the snapshot
  missed. The interrupted run, if there is one, is not part of that history
  until it is resumed or given up. Returns `{:error, reason}` when the journal
  cannot be read: a session started without it would reuse the ids of the
  runs it holds, and a later recovery would merge them.
  """
  def load(store, store_opts, nil), do: load(store, store_opts, %Snapshot{})

  def load(store, store_opts, %Snapshot{} = snapshot) do
    {last_run_id, requests} = Snapshot.runs(snapshot)

    durable = %__MODULE__{
      enabled: SessionStore.journal?(store),
      run_seq: last_run_id || 0,
      last_run_id: last_run_id,
      requests: requests
    }

    if durable.enabled,
      do: load_journal(durable, store, store_opts, snapshot.messages),
      else: {:ok, durable, snapshot.messages}
  end

  defp load_journal(durable, store, store_opts, messages) do
    with {:ok, records} <- SessionStore.load_journal(store, store_opts) do
      {durable, messages} = fold(durable, records, messages)
      {:ok, durable, messages}
    end
  end

  defp fold(durable, records, messages) do
    last = durable.last_run_id || 0
    records = Enum.filter(records, &match?({kind, id, _} when is_atom(kind) and is_integer(id), &1))
    run_seq = Enum.reduce(records, durable.run_seq, fn {_kind, id, _payload}, acc -> max(id, acc) end)

    # Runs are sequential, so each run's records are contiguous.
    runs =
      records
      |> Enum.filter(fn {_kind, id, _payload} -> id > last end)
      |> Enum.chunk_by(fn {_kind, id, _payload} -> id end)
      |> follows(messages)

    {finished, newest} =
      if runs != [] and not ended?(List.last(runs)), do: Enum.split(runs, -1), else: {runs, []}

    {durable, messages} = Enum.reduce(finished, {%{durable | run_seq: run_seq}, messages}, &settle_finished/2)

    case newest do
      [[{:run_start, run_id, start} | rest]] ->
        {%{durable | interrupted: replay(run_id, start, rest, messages)}, messages}

      [] ->
        {durable, messages}

      _ ->
        Logger.warning("ignoring a session journal run without its start")
        {durable, messages}
    end
  end

  defp follows([[{:run_start, _id, %{base: base}} | _rest] | _more] = runs, messages) when base != nil do
    if base == fingerprint(messages) do
      runs
    else
      Logger.warning("ignoring a session journal that does not follow the session's snapshot")
      []
    end
  end

  defp follows(runs, _messages), do: runs

  @doc "Identifies a history cheaply: its length and its last message."
  def fingerprint(messages), do: {length(messages), :erlang.phash2(List.last(messages))}

  defp ended?(records), do: Enum.any?(records, &match?({:run_end, _id, _result}, &1))

  # A run that ended, or was followed by another one, but whose snapshot failed
  # to save. Its messages become history and its request id gets the outcome
  # it ended with, so a retry does not run it again. A run followed by another
  # but without an end, written by a build without end records or because the
  # write failed, gets the outcome it can be shown to have had.
  defp settle_finished([{:run_start, run_id, start} | rest], {durable, messages}) do
    run = replay(run_id, start, rest, messages)
    messages = close(run.messages)

    result =
      case List.keyfind(rest, :run_end, 0) do
        {:run_end, _id, result} -> result
        nil -> inferred_outcome(messages)
      end

    {%{record_request(durable, run.request_id, result) | last_run_id: run_id}, messages}
  end

  defp settle_finished(_records, acc) do
    Logger.warning("ignoring a session journal run without its start")
    acc
  end

  # The outcome a closed run that never stored its end can be shown to have
  # had: its answer when the last message is one, or else an interruption.
  defp inferred_outcome(messages) do
    case List.last(messages) do
      %Message{role: :assistant} = answer -> {:ok, Message.text(answer)}
      _last -> {:error, :interrupted}
    end
  end

  defp replay(run_id, start, records, messages) do
    Enum.reduce(records, start_run(run_id, start, messages), &apply_record/2)
  end

  defp start_run(run_id, start, messages) do
    %{
      run_id: run_id,
      request_id: start[:request_id],
      input: start[:input],
      max_turns: start[:max_turns],
      messages: messages ++ [start.message],
      prompt_index: length(messages),
      turn: 0,
      restarts: 0,
      assistant: nil,
      intents: %{}
    }
  end

  # A result that was never stored, because its write failed or its task
  # exited, leaves its call without one, and results are stored in the order
  # they finish. The round before the next response is closed so the history
  # stays one the model accepts, in the order the model asked.
  defp apply_record({:assistant, _id, message}, run) do
    %{
      run
      | messages: close(run.messages) ++ [message],
        assistant: message,
        intents: %{},
        turn: run.turn + 1,
        restarts: 0
    }
  end

  defp apply_record({:tool_intent, _id, %{call_id: call_id, replay_safe: safe?}}, run) do
    %{run | intents: Map.put(run.intents, call_id, safe?)}
  end

  defp apply_record({:tool_result, _id, message}, run) do
    %{run | messages: run.messages ++ [message], restarts: 0}
  end

  # Steering is taken before a model request, after the round before it.
  defp apply_record({:input, _id, messages}, run) do
    %{run | messages: close(run.messages) ++ messages, assistant: nil, intents: %{}}
  end

  # The same adjustment the session makes to its protected prompt boundary
  # when compaction replaces messages under a running turn. Compaction only
  # runs between rounds, so the last round is complete and the compacted
  # history may no longer hold it: what follows is the next model request. The
  # live history had every result of that round, even one whose record is
  # missing, so the boundary moves by the closed history's length.
  defp apply_record({:messages, _id, messages}, run) do
    %{
      run
      | messages: messages,
        prompt_index: run.prompt_index + length(messages) - length(close(run.messages)),
        assistant: nil,
        intents: %{}
    }
  end

  defp apply_record({:resume, _id, _payload}, run), do: %{run | restarts: run.restarts + 1}
  defp apply_record(_record, run), do: run

  @doc "What the caller sees of an interrupted run, or nil."
  def interrupted_info(%__MODULE__{interrupted: nil}), do: nil

  def interrupted_info(%__MODULE__{interrupted: run}) do
    %{run_id: run.run_id, request_id: run.request_id, restarts: run.restarts}
  end

  @doc "The stored outcome of a finished request, or `:error`."
  def request_result(%__MODULE__{requests: requests}, request_id) when not is_nil(request_id) do
    case List.keyfind(requests, request_id, 0) do
      {^request_id, result} -> {:ok, result}
      nil -> :error
    end
  end

  def request_result(_durable, _request_id), do: :error

  @doc "Whether a submission with this request id is the interrupted run's own."
  def resumes?(%__MODULE__{interrupted: %{request_id: request_id}}, request_id) when not is_nil(request_id), do: true
  def resumes?(_durable, _request_id), do: false

  @doc """
  Starts a run that is journaled, or that carries a request id to remember.
  """
  def begin_run(%__MODULE__{} = durable, request_id, journaled?) do
    run_id = durable.run_seq + 1
    %{durable | run_seq: run_id, current: %{run_id: run_id, request_id: request_id, journaled: journaled?}}
  end

  @doc "Whether the current run writes to the journal."
  def journaling?(%__MODULE__{current: current}), do: match?(%{journaled: true}, current)

  @doc """
  Gives up the interrupted run because the caller started another one.

  Returns the durable state with the interrupted run as the current one, so the
  caller finishes it like any other, the history to keep, which is what the run
  stored with every unanswered tool call closed, and the run's outcome: its
  answer when it stored one, or else an interruption.
  """
  def abandon(%__MODULE__{interrupted: run} = durable) do
    messages = close(run.messages)
    {%{durable | interrupted: nil, current: current(run)}, messages, inferred_outcome(messages)}
  end

  defp current(run), do: %{run_id: run.run_id, request_id: run.request_id, journaled: true}

  @doc "Records how the current run ended. The caller saves the snapshot next."
  def finish_run(%__MODULE__{current: nil} = durable, _result), do: durable

  def finish_run(%__MODULE__{current: current} = durable, result) do
    %{record_request(durable, current.request_id, result) | current: nil, last_run_id: current.run_id}
  end

  defp record_request(durable, nil, _result), do: durable

  defp record_request(durable, request_id, result) do
    requests = Enum.take([{request_id, result} | List.keydelete(durable.requests, request_id, 0)], @max_requests)
    %{durable | requests: requests}
  end

  @doc """
  Forgets everything a cleared session no longer has. Run ids keep growing, and
  the next snapshot covers every run so far, so none of them comes back.
  """
  def reset(%__MODULE__{} = durable) do
    %{durable | last_run_id: durable.run_seq, requests: [], current: nil, interrupted: nil}
  end

  @doc """
  Takes the interrupted run back up.

  Returns `{:ok, durable, plan, records}`, where `records` must be journaled
  before the plan runs, or `{:give_up, durable, messages, reason}` when the run
  has been restarted `restart_limit` times in a row without making progress.
  """
  def resume(%__MODULE__{interrupted: run} = durable, replay_safe?) do
    durable = %{durable | interrupted: nil, current: current(run)}

    # An integer is smaller than any atom, so `:infinity` never gives up.
    if run.restarts >= durable.restart_limit do
      {:give_up, durable, close(run.messages), {:restart_limit, run.restarts}}
    else
      {plan, synthesized} = plan(run, replay_safe?)
      # The resume record goes last: the synthesized results are progress, the
      # restart that follows them is not.
      records = Enum.map(synthesized, &{:tool_result, run.run_id, &1}) ++ [{:resume, run.run_id, nil}]
      {:ok, durable, plan, records}
    end
  end

  defp plan(run, replay_safe?) do
    plan = %{
      step: :model,
      messages: run.messages,
      turn: run.turn,
      max_turns: run.max_turns,
      prompt_index: run.prompt_index
    }

    {results, prefix} = split_results(run.messages)
    calls = if run.assistant, do: Message.tool_calls(run.assistant), else: []
    missing = Enum.reject(calls, fn {id, _name, _args} -> Map.has_key?(results, id) end)

    cond do
      # Crashed during the model request: the request is made again.
      is_nil(run.assistant) ->
        {plan, []}

      # The final answer was stored but the run never closed.
      calls == [] ->
        {%{plan | step: :answered}, []}

      # Crashed between a tool round and the next request. Results are stored
      # as calls finish, so they are put back in the order they were asked for.
      missing == [] ->
        {%{plan | messages: prefix ++ Enum.map(calls, &Map.fetch!(results, elem(&1, 0)))}, []}

      # A call with a recorded intent may have taken effect. It runs again only
      # when its tool was replay-safe when it ran and still is now; otherwise
      # the model is told.
      true ->
        {interrupted, rerun} =
          Enum.split_with(missing, fn {id, name, _args} ->
            Map.has_key?(run.intents, id) and not (run.intents[id] and replay_safe?.(name))
          end)

        synthesized = Enum.map(interrupted, &interrupted_result/1)
        results = Map.merge(results, Map.new(synthesized, &{&1.tool_call_id, &1}))

        tools = %{step: :tools, prefix: prefix, calls: calls, results: results, rerun: rerun, interrupted: synthesized}
        {Map.merge(plan, tools), synthesized}
    end
  end

  @doc """
  Gives every call of the last tool round a result, in call order, so the
  history can be sent to a model again.
  """
  def close(messages) do
    {results, prefix} = split_results(messages)

    prefix
    |> List.last()
    |> Message.tool_calls()
    |> case do
      [] -> messages
      calls -> prefix ++ Enum.map(calls, &Map.get_lazy(results, elem(&1, 0), fn -> interrupted_result(&1) end))
    end
  end

  # The trailing tool results, by call id, and the messages before them.
  defp split_results(messages) do
    {results, prefix} = messages |> Enum.reverse() |> Enum.split_while(&match?(%Message{role: :tool_result}, &1))
    {Map.new(results, &{&1.tool_call_id, &1}), Enum.reverse(prefix)}
  end

  @doc "The result a call gets when it was interrupted and is not run again."
  def interrupted_result({id, name, _args}) do
    Message.tool_result(
      id,
      {:error,
       "#{name} was interrupted: the session stopped while it was running, so whether it took effect " <>
         "is unknown. It was not run again."}
    )
  end

  @doc "Appends records to the journal, returning `{:error, {:journal_failed, reason}}` when the store fails."
  def append(store, store_opts, records) do
    case SessionStore.append_journal(store, records, store_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to append to the session journal: #{inspect(reason)}")
        {:error, {:journal_failed, reason}}
    end
  end

  @doc "Clears the journal, logging a failure."
  def clear(store, store_opts) do
    case SessionStore.clear_journal(store, store_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to clear the session journal: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
