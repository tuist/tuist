defmodule Condukt.Session.Turn do
  @moduledoc """
  State belonging to the turn a session is currently running.

  These fields move together: whether a turn is in flight, its cancellation
  reference, worker and reply destination, the messages queued to join or
  follow it, and who is watching it. Grouping them keeps the session's
  own struct inside the 32-key limit that decides whether the virtual machine
  stores it as a flat map or a hash map, and, more usefully, makes it obvious
  which parts of a session are per-turn and which outlive one.

  `abort_ref` identifies the running turn. Stream events, results, and calls
  from the turn's worker carry it, so the session can tell a late one from a
  turn it already ended. Aborting replaces it and shuts the worker down.

  `worker` runs the turn under the session's turn supervisor. What the turn's
  tool calls start is not held here: each call is a process linked to the
  worker, and work it owns, such as a foreground sub-agent's session, is
  linked below it, so shutting the worker down takes all of it along.
  Background sub-agents belong to the session, not a turn, and survive.

  Input waits in four queues, taken in this order when the session is idle:
  `pending` callers whose `run` or `stream` arrived while a `queued` turn (one
  started from queued input, with nobody waiting on it) ran, steering that
  arrived too late for its turn, follow-ups, and background sub-agent
  `reports`. An abort withdraws all but the reports: an answer a sub-agent
  already gave is not undone by stopping the parent's current work.

  `history_rewritten` records that a compaction replaced history the turn
  started from, so the session's view takes the whole history when the turn
  ends rather than only what the turn added after `prompt_index`.
  """

  defstruct streaming: false,
            abort_ref: nil,
            recipient: nil,
            worker: nil,
            prompt_index: nil,
            steering_messages: [],
            follow_up_messages: [],
            subscribers: [],
            pending: [],
            reports: [],
            queued: false,
            history_rewritten: false

  @doc "A turn that has not started."
  def new, do: %__MODULE__{}

  @doc """
  Marks a turn as started with its reply destination and protected prompt boundary.
  """
  def start(%__MODULE__{} = turn, recipient, prompt_index) do
    %{
      turn
      | streaming: true,
        abort_ref: make_ref(),
        recipient: recipient,
        worker: nil,
        prompt_index: prompt_index,
        queued: false,
        history_rewritten: false
    }
  end

  @doc """
  Marks the turn finished, leaving the queues and subscribers alone.

  Those outlive a single turn: a subscriber stays attached for the next one, and
  a message queued while this turn ran is meant for the one after it.
  """
  def finish(%__MODULE__{} = turn) do
    %{
      turn
      | streaming: false,
        recipient: nil,
        worker: nil,
        prompt_index: nil,
        queued: false,
        history_rewritten: false
    }
  end

  @doc """
  Abandons the running turn.

  Replacing the reference makes the session reject late results, stream events,
  and further tool admissions from that turn. Pending callers, steering, and
  follow-ups are withdrawn with it, so an abort does not start another turn;
  the session answers the pending callers. Reports stay queued for later.
  """
  def abort(%__MODULE__{} = turn) do
    %{
      turn
      | abort_ref: make_ref(),
        streaming: false,
        recipient: nil,
        worker: nil,
        prompt_index: nil,
        queued: false,
        history_rewritten: false,
        pending: [],
        steering_messages: [],
        follow_up_messages: []
    }
  end

  @doc """
  Queues a caller's `{prompt, opts, recipient}` behind the running queued turn.
  """
  def enqueue(%__MODULE__{} = turn, pending), do: %{turn | pending: turn.pending ++ [pending]}

  @doc "Queues a background sub-agent's report under `tag`."
  def report(%__MODULE__{} = turn, tag, message), do: %{turn | reports: turn.reports ++ [{tag, message}]}

  @doc "Withdraws a report that has not started a turn yet, such as one a `wait` claimed."
  def withdraw_report(%__MODULE__{} = turn, tag) do
    %{turn | reports: Enum.reject(turn.reports, &match?({^tag, _message}, &1))}
  end

  @doc "Whether input other than reports waits to start a turn."
  def input_waiting?(%__MODULE__{} = turn) do
    turn.pending != [] or turn.steering_messages != [] or turn.follow_up_messages != []
  end

  @doc "Records that a compaction replaced the history this turn started from."
  def rewrite_history(%__MODULE__{} = turn), do: %{turn | history_rewritten: true}

  @doc "Adds a subscriber and the monitor watching it."
  def subscribe(%__MODULE__{} = turn, pid, ref, monitor) do
    %{turn | subscribers: [{pid, ref, monitor} | turn.subscribers]}
  end

  @doc """
  Removes one subscription, returning the monitors to demonitor with it.
  """
  def unsubscribe(%__MODULE__{} = turn, pid, ref) do
    {dropped, kept} = Enum.split_with(turn.subscribers, fn {p, r, _m} -> p == pid and r == ref end)
    {%{turn | subscribers: kept}, Enum.map(dropped, fn {_p, _r, monitor} -> monitor end)}
  end

  @doc "Drops the subscriber a monitor was watching, after it went down."
  def drop_monitored(%__MODULE__{} = turn, monitor) do
    %{turn | subscribers: Enum.reject(turn.subscribers, &match?({_, _, ^monitor}, &1))}
  end

  @doc "The subscribers listening under one reference."
  def listeners(%__MODULE__{} = turn, ref) do
    for {pid, ^ref, _monitor} <- turn.subscribers, do: pid
  end

  @doc "Queues a message to join the running turn."
  def steer(%__MODULE__{} = turn, message) do
    %{turn | steering_messages: turn.steering_messages ++ [message]}
  end

  @doc "Queues a message for after the running turn."
  def follow_up(%__MODULE__{} = turn, message) do
    %{turn | follow_up_messages: turn.follow_up_messages ++ [message]}
  end

  @doc "Takes the steering messages queued for the running turn's next step."
  def take_steering(%__MODULE__{} = turn), do: {turn.steering_messages, %{turn | steering_messages: []}}

  @doc """
  Takes the next input to start a turn with, or `nil`, in queue order.

  Returns a pending `{prompt, opts, recipient}` or a queued message.
  """
  def next_input(%__MODULE__{pending: [pending | rest]} = turn), do: {pending, %{turn | pending: rest}}

  def next_input(%__MODULE__{steering_messages: [message | rest]} = turn),
    do: {message, %{turn | steering_messages: rest}}

  def next_input(%__MODULE__{follow_up_messages: [message | rest]} = turn),
    do: {message, %{turn | follow_up_messages: rest}}

  def next_input(%__MODULE__{reports: [{_tag, message} | rest]} = turn), do: {message, %{turn | reports: rest}}
  def next_input(%__MODULE__{} = turn), do: {nil, turn}
end
