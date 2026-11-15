defmodule Condukt.Session.Parking do
  @moduledoc false
  # The running turn's parked tool calls and the signals sent to it.
  #
  # The session's parked tool calls and signals. Waits, early signals, and
  # woken calls belong to the running turn; `:end_turn` drops them and closes
  # every key the turn used, keeping only the closed keys, so a retry of an
  # old key is answered `:closed` in later turns too. Keys are scoped to the
  # session, so a tool includes its tool call id in each key.
  #
  # `park/4`, `signal/3`, and `expire/2` only decide. They return records, and
  # the session applies each with `apply_record/2`, so a journal that stores
  # the records before they are applied, and `replay/1` that folds them back,
  # rebuild the same waits, early signals, and used keys after a restart:
  #
  #     {:park, call_id, %{tool, signals, until, state}}
  #     {:signal, key, value}       delivered, early or waking a wait
  #     {:timeout, call_id}         the call's deadline came first
  #     {:done, call_id}            a woken call returned a result
  #     :end_turn                   the turn ended; its keys close
  #
  # A woken wait keeps its event until the call parks again or is done, so a
  # restart after the wake calls `wake/3` again with the same event and state.
  # `running` (woken calls the worker took), `blocked` (the worker waits for a
  # wake), `timer`, and `published` are process state: a restarted turn
  # rebuilds them from its records and the clock.

  alias Condukt.Park

  defstruct blocked: false,
            waits: %{},
            running: %{},
            inbox: %{},
            settled: %{},
            timer: nil,
            published: nil

  # Signals a turn holds for keys no call has parked on yet. Senders are not
  # authenticated, so this bounds what they can make a session keep.
  @max_inbox 100

  def new, do: %__MODULE__{}

  @doc "Decides a call's park. An early signal under one of its keys wakes it once applied."
  def park(%__MODULE__{} = parking, {id, name}, state, %Park{} = park) do
    case Enum.find(park.signals, &unavailable?(parking, id, &1)) do
      nil ->
        {:ok, [{:park, id, %{tool: name, signals: park.signals, until: park.until, state: state}}]}

      key ->
        {:error, {:signal_key_used, key}}
    end
  end

  @doc """
  Decides a delivery: `{:ok, records}`, or `{:error, reason}` with
  `:duplicate`, `:closed`, or `:inbox_full`.
  """
  def signal(%__MODULE__{} = parking, key, value) do
    cond do
      Map.get(parking.settled, key) == :closed -> {:error, :closed}
      Map.get(parking.settled, key) == :consumed -> {:error, :duplicate}
      Map.has_key?(parking.inbox, key) -> {:error, :duplicate}
      waited_on?(parking, key) -> {:ok, [{:signal, key, value}]}
      map_size(parking.inbox) >= @max_inbox -> {:error, :inbox_full}
      true -> {:ok, [{:signal, key, value}]}
    end
  end

  @doc "The records that wake the waits whose deadline is at or before `now`."
  def expire(%__MODULE__{} = parking, now) do
    for {id, %{wake: nil, until: until}} <- Enum.sort(parking.waits),
        is_integer(until) and until <= now,
        do: {:timeout, id}
  end

  @doc "Whether a woken call waits to run again."
  def ready?(%__MODULE__{} = parking), do: Enum.any?(parking.waits, fn {_id, wait} -> wait.wake != nil end)

  @doc "Takes the woken calls, as `%{call_id => {event, state}}`."
  def take_ready(%__MODULE__{} = parking) do
    {ready, waits} = Map.split_with(parking.waits, fn {_id, wait} -> wait.wake != nil end)
    resumed = Map.new(ready, fn {id, wait} -> {id, {wait.wake, wait.state}} end)
    {resumed, %{parking | waits: waits, running: Map.merge(parking.running, ready)}}
  end

  @doc "The earliest deadline of a call still waiting, in Unix milliseconds."
  def next_deadline(%__MODULE__{} = parking) do
    parking.waits
    |> Enum.flat_map(fn
      {_id, %{wake: nil, until: until}} when is_integer(until) -> [until]
      _wait -> []
    end)
    |> Enum.min(fn -> nil end)
  end

  @doc "The calls still waiting."
  def waiting(%__MODULE__{} = parking) do
    for {id, %{wake: nil} = wait} <- Enum.sort(parking.waits) do
      Map.merge(%{tool_call_id: id, tool: wait.tool}, Park.describe(wait))
    end
  end

  @doc "The parked calls and the woken ones running again, which an abort cancels."
  def cancellable(%__MODULE__{} = parking), do: Enum.sort(Map.merge(parking.running, parking.waits))

  @doc "Rebuilds the parking state from its records."
  def replay(records), do: Enum.reduce(records, new(), &apply_record(&2, &1))

  @doc "Applies one record."
  def apply_record(%__MODULE__{} = parking, {:park, id, info}) do
    parking = %{
      parking
      | waits: Map.put(parking.waits, id, Map.put(info, :wake, nil)),
        running: Map.delete(parking.running, id)
    }

    wake_from_inbox(parking, id)
  end

  def apply_record(%__MODULE__{} = parking, {:signal, key, value}) do
    parking = %{parking | inbox: Map.put(parking.inbox, key, value)}

    case Enum.find(Enum.sort(parking.waits), fn {_id, wait} -> wait.wake == nil and key in wait.signals end) do
      {id, _wait} -> wake_from_inbox(parking, id)
      nil -> parking
    end
  end

  def apply_record(%__MODULE__{} = parking, {:timeout, id}) do
    case Map.fetch(parking.waits, id) do
      {:ok, %{wake: nil} = wait} ->
        %{
          parking
          | waits: Map.put(parking.waits, id, %{wait | wake: :timeout}),
            settled: Map.merge(parking.settled, Map.new(wait.signals, &{&1, :closed}))
        }

      _other ->
        parking
    end
  end

  def apply_record(%__MODULE__{} = parking, {:done, id}) do
    %{parking | waits: Map.delete(parking.waits, id), running: Map.delete(parking.running, id)}
  end

  def apply_record(%__MODULE__{} = parking, :end_turn) do
    keys =
      Map.keys(parking.settled) ++
        Map.keys(parking.inbox) ++
        Enum.flat_map(Map.merge(parking.running, parking.waits), fn {_id, wait} -> wait.signals end)

    %{new() | settled: Map.new(keys, &{&1, :closed})}
  end

  defp wake_from_inbox(parking, id) do
    wait = Map.fetch!(parking.waits, id)

    case Enum.find(wait.signals, &Map.has_key?(parking.inbox, &1)) do
      nil ->
        parking

      signal ->
        # The wait is over, so its other keys close with it, as on a timeout.
        siblings = List.delete(wait.signals, signal)

        settled =
          parking.settled
          |> Map.merge(Map.new(siblings, &{&1, :closed}))
          |> Map.put(signal, :consumed)

        %{
          parking
          | inbox: Map.drop(parking.inbox, wait.signals),
            settled: settled,
            waits: Map.put(parking.waits, id, %{wait | wake: {:signal, signal, Map.fetch!(parking.inbox, signal)}})
        }
    end
  end

  defp waited_on?(parking, key),
    do: Enum.any?(parking.waits, fn {_id, wait} -> wait.wake == nil and key in wait.signals end)

  # A key that already served a wait, or that another call still waits on.
  defp unavailable?(parking, id, key) do
    Map.has_key?(parking.settled, key) or
      Enum.any?(parking.waits, fn {other, wait} -> other != id and wait.wake == nil and key in wait.signals end)
  end
end
