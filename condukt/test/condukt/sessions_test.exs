defmodule Condukt.SessionsTest do
  use ExUnit.Case, async: true

  alias Condukt.Session
  alias Condukt.Sessions

  defmodule Agent do
    @moduledoc false
    use Condukt.Agent

    @impl Condukt
    def model, do: "openrouter:test"
  end

  defp start_session(opts \\ []) do
    {:ok, pid} = Sessions.start(Agent, Keyword.merge([api_key: "test"], opts))
    id = Session.id(pid)
    # The id is read now rather than in the callback: several of these tests
    # end with the session already gone, and a dead process cannot be asked.
    on_exit(fn -> Sessions.stop(id) end)
    {pid, id}
  end

  # A registry drops an entry when it observes the process go down, which
  # happens after the DOWN message reaches anyone else monitoring it. Waiting
  # for the registry rather than assuming it has caught up is the difference
  # between a test that describes the system and one that races it.
  defp await_deregistered(id, remaining \\ 500)

  defp await_deregistered(id, remaining) when remaining <= 0, do: Sessions.alive?(id)

  defp await_deregistered(id, remaining) do
    if Sessions.alive?(id) do
      Process.sleep(10)
      await_deregistered(id, remaining - 10)
    else
      false
    end
  end

  test "a started session is registered under its own id" do
    {pid, id} = start_session()

    assert Sessions.whereis(id) == pid
    assert Sessions.alive?(id)
  end

  # The id a caller already has should be the only handle it needs, so a
  # reconnecting viewer never has to have kept a pid alive.
  test "the id alone reaches the session" do
    {_pid, id} = start_session()

    assert Session.id(Sessions.via(id)) == id
  end

  test "a caller-supplied id is used rather than generated" do
    id = "session-" <> Integer.to_string(System.unique_integer([:positive]))
    {pid, registered} = start_session(id: id)

    assert registered == id
    assert Sessions.whereis(id) == pid
  end

  test "running sessions can be listed and counted" do
    {_pid, id} = start_session()

    assert id in Sessions.list()
    assert Sessions.count() >= 1
  end

  test "stopping deregisters the session" do
    {pid, id} = start_session()
    reference = Process.monitor(pid)

    assert :ok = Sessions.stop(id)
    assert_receive {:DOWN, ^reference, :process, ^pid, _reason}

    refute await_deregistered(id)
    assert Sessions.whereis(id) == nil
  end

  # A caller cleaning up should not have to race the session's own exit.
  test "stopping something that is not running succeeds" do
    assert :ok = Sessions.stop("never-started")
  end

  test "an unknown id resolves to nothing rather than raising" do
    refute Sessions.alive?("unknown")
    assert Sessions.whereis("unknown") == nil
  end

  # Temporary on purpose: a conversation that crashed should not silently come
  # back without the turn it died in. Restarting is the caller's decision.
  test "a crashed session is not restarted" do
    {pid, id} = start_session()
    reference = Process.monitor(pid)

    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^reference, :process, ^pid, :killed}

    refute await_deregistered(id)
  end
end
