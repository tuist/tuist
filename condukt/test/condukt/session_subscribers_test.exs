defmodule Condukt.SessionSubscribersTest do
  use ExUnit.Case, async: true

  alias Condukt.Session
  alias Condukt.Sessions

  defmodule Agent do
    @moduledoc false
    use Condukt.Agent

    @impl Condukt
    def model, do: "openrouter:test"
  end

  setup do
    {:ok, session} = Sessions.start(Agent, api_key: "test")
    on_exit(fn -> Sessions.stop(Session.id(session)) end)
    %{session: session}
  end

  defp subscribers(session), do: length(:sys.get_state(session).turn.subscribers)

  test "subscribing and unsubscribing are symmetric", %{session: session} do
    assert subscribers(session) == 0

    reference = make_ref()
    :ok = GenServer.call(session, {:subscribe, self(), reference})
    assert subscribers(session) == 1

    GenServer.cast(session, {:unsubscribe, self(), reference})
    # The cast is asynchronous; a call behind it means it has been handled.
    _state = :sys.get_state(session)
    assert subscribers(session) == 0
  end

  # The only other way out of the list is an explicit unsubscribe, and a
  # subscriber that crashes never sends one. Without a monitor the session
  # accumulates dead pids for as long as it lives and keeps sending to each.
  test "a subscriber that dies is dropped", %{session: session} do
    reference = make_ref()
    {viewer, monitor} = spawn_monitor(fn -> Process.sleep(:infinity) end)

    :ok = GenServer.call(session, {:subscribe, viewer, reference})
    assert subscribers(session) == 1

    Process.exit(viewer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^viewer, :killed}

    _state = :sys.get_state(session)
    assert subscribers(session) == 0
  end

  test "one subscriber dying leaves the others attached", %{session: session} do
    :ok = GenServer.call(session, {:subscribe, self(), make_ref()})

    {viewer, monitor} = spawn_monitor(fn -> Process.sleep(:infinity) end)
    :ok = GenServer.call(session, {:subscribe, viewer, make_ref()})
    assert subscribers(session) == 2

    Process.exit(viewer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^viewer, :killed}

    _state = :sys.get_state(session)
    assert subscribers(session) == 1
  end

  test "unrelated messages leave the session running", %{session: session} do
    send(session, :something_else)

    assert subscribers(session) == 0
    assert Process.alive?(session)
  end
end
