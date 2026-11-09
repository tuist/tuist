defmodule Condukt.Session.Turn do
  @moduledoc """
  State belonging to the turn a session is currently running.

  These fields move together: whether a turn is in flight, its cancellation
  reference, worker and reply destination, the messages queued to join or
  follow it, and who is watching it. Grouping them keeps the session's
  own struct inside the 32-key limit that decides whether the virtual machine
  stores it as a flat map or a hash map, and, more usefully, makes it obvious
  which parts of a session are per-turn and which outlive one.

  `abort_ref` identifies the running turn. Native loops verify it against the
  session before each provider attempt, after inference, and before admitting
  each tool; stream events and results carry it too. Aborting replaces it and
  wakes retry backoff without killing the worker, so tools already admitted
  may still finish.
  """

  defstruct streaming: false,
            abort_ref: nil,
            recipient: nil,
            worker: nil,
            prompt_index: nil,
            steering_messages: [],
            follow_up_messages: [],
            subscribers: []

  @doc "A turn that has not started."
  def new, do: %__MODULE__{}

  @doc """
  Marks a turn as started with its reply destination and protected prompt boundary.
  """
  def start(%__MODULE__{} = turn, recipient, prompt_index) do
    %{turn | streaming: true, abort_ref: make_ref(), recipient: recipient, worker: nil, prompt_index: prompt_index}
  end

  @doc """
  Marks the turn finished, leaving the queues and subscribers alone.

  Those outlive a single turn: a subscriber stays attached for the next one, and
  a message queued while this turn ran is meant for the one after it.
  """
  def finish(%__MODULE__{} = turn), do: %{turn | streaming: false, recipient: nil, worker: nil, prompt_index: nil}

  @doc """
  Abandons the running turn.

  Replacing the reference makes the session reject late results, stream events,
  and further tool admissions from that turn.
  """
  def abort(%__MODULE__{} = turn) do
    %{turn | abort_ref: make_ref(), streaming: false, recipient: nil, worker: nil, prompt_index: nil}
  end

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
end
