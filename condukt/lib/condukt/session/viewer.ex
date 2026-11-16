defmodule Condukt.Session.Viewer do
  @moduledoc false

  # The process that owns a session's `Condukt.Session.View`.
  #
  # The session sends it raw events and changes and moves on; this process
  # redacts them, folds them into the view, numbers them, and sends them to
  # the watchers and the notifier. Viewer work, a slow redactor, and a slow
  # notifier then queue here instead of in front of the session's own turn.
  #
  # Order is what keeps it consistent. Everything comes from the session, in
  # the order the session sent it, including `view` and `watch` requests the
  # session forwards. So a view reflects every change the session made before
  # it handled the request, and `watch` returns the view and adds the watcher
  # in one step, with nothing lost or repeated after it. Events reach the
  # notifier from here too, so a notifier sees events and changes in one order.
  #
  # Linked to the session, so neither outlives the other's crash; it also
  # monitors the session, since a session that stops normally sends no exit
  # signal that would stop it.

  use GenServer

  alias Condukt.Notifier
  alias Condukt.Session.View

  def start_link(opts), do: GenServer.start_link(__MODULE__, Keyword.put(opts, :session, self()))

  @impl true
  def init(opts) do
    session = Keyword.fetch!(opts, :session)
    redactor = Keyword.fetch!(opts, :redactor)
    id = Keyword.fetch!(opts, :id)
    view = View.new(id, Keyword.fetch!(opts, :agent), View.redact(Keyword.fetch!(opts, :messages), redactor))

    {:ok,
     %{
       session: Process.monitor(session),
       id: id,
       view: view,
       redactor: redactor,
       notifier: Keyword.get(opts, :notifier),
       watchers: %{}
     }}
  end

  # An event the session published: the notifier gets it as is, as before,
  # and the view gets it redacted.
  @impl true
  def handle_cast({:event, event}, state) do
    Notifier.publish(state.notifier, state.id, event)
    {:noreply, record(state, event)}
  end

  # The session sends the queue whenever it might have changed, without
  # comparing, so the comparison happens here, on the redacted items.
  def handle_cast({:change, {:queue, items}}, state) do
    items = View.redact(items, state.redactor)
    if items == state.view.queue, do: {:noreply, state}, else: {:noreply, advance(state, {:queue, items})}
  end

  def handle_cast({:change, change}, state), do: {:noreply, record(state, change)}

  # Background sub-agents outlive turns, so their events build each one's run
  # under its name rather than under a call of the current turn.
  def handle_cast({:background_subagent_event, event}, state) do
    Notifier.publish(state.notifier, state.id, event)

    with {:subagent, call_id, child_event} <- event,
         {name, _entry} <- Enum.find(state.view.background, &match?({_name, %{call_id: ^call_id}}, &1)) do
      {:noreply, record(state, {:background_event, name, child_event})}
    else
      _other -> {:noreply, state}
    end
  end

  def handle_cast({:background_input, name, change}, state) do
    if Map.has_key?(state.view.background, name) do
      {:noreply, record(state, {:background_event, name, change})}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:view, from}, state) do
    GenServer.reply(from, state.view)
    {:noreply, state}
  end

  # A session call answered after everything the session sent before it.
  def handle_cast({:reply, from, reply}, state) do
    GenServer.reply(from, reply)
    {:noreply, state}
  end

  def handle_cast({:watch, pid, from}, state) do
    watchers = Map.put_new_lazy(state.watchers, pid, fn -> Process.monitor(pid) end)
    GenServer.reply(from, state.view)
    {:noreply, %{state | watchers: watchers}}
  end

  def handle_cast({:unwatch, pid}, state) do
    {monitor, watchers} = Map.pop(state.watchers, pid)
    if monitor, do: Process.demonitor(monitor, [:flush])
    {:noreply, %{state | watchers: watchers}}
  end

  @impl true
  def handle_info({:DOWN, session, :process, _pid, _reason}, %{session: session} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _monitor, :process, pid, _reason}, state) do
    {:noreply, %{state | watchers: Map.delete(state.watchers, pid)}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Redacts a change once, as it arrives, so redaction costs what the change
  # holds rather than what the history holds.
  defp record(state, change), do: advance(state, View.redact(change, state.redactor))

  # Numbers a redacted change, folds it in, and sends it on.
  defp advance(state, change) do
    %View{epoch: epoch, seq: seq} = state.view
    {:ok, view} = View.advance(state.view, epoch, seq + 1, change)

    for pid <- Map.keys(state.watchers) do
      send(pid, {:condukt_change, state.id, epoch, seq + 1, change})
    end

    Notifier.publish_change(state.notifier, state.id, epoch, seq + 1, change)
    %{state | view: view}
  end
end
