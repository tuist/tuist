defmodule Atlas.Agents.Sessions.TelemetryHandlerTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Agents.Sessions.{Event, Session, TelemetryHandler}
  alias Atlas.TestSupport.ExitingInspect
  alias Condukt.SessionID

  test "persists tool_call events emitted for a known session" do
    session = insert_running_session()

    emit(
      [:condukt, :tool_call, :start],
      %{system_time: System.system_time()},
      %{
        tool: "find_account",
        tool_call_id: "call_1",
        args: %{"emails" => ["a@example.com"]},
        agent: __MODULE__,
        session_id: session.id
      }
    )

    emit(
      [:condukt, :tool_call, :stop],
      %{duration: System.convert_time_unit(50, :millisecond, :native)},
      %{
        tool: "find_account",
        tool_call_id: "call_1",
        args: %{"emails" => ["a@example.com"]},
        agent: __MODULE__,
        session_id: session.id,
        status: :ok,
        result: %{"found" => false}
      }
    )

    events = Repo.all(from e in Event, where: e.agent_session_id == ^session.id, order_by: e.occurred_at)
    assert [start_event, stop_event] = events

    assert start_event.type == "tool_call"
    assert start_event.phase == "start"
    assert start_event.name == "find_account"
    assert start_event.metadata["args"] == %{"emails" => ["a@example.com"]}

    assert stop_event.phase == "stop"
    assert stop_event.duration_ms == 50
    assert stop_event.metadata["status"] == "ok"
    assert stop_event.metadata["result"] == %{"found" => false}
  end

  test "drops events whose session row does not exist" do
    emit(
      [:condukt, :run, :start],
      %{system_time: System.system_time()},
      %{session_id: SessionID.generate(), structured?: false, input?: false}
    )

    assert Repo.aggregate(Event, :count) == 0
  end

  test "drops events with no session_id metadata" do
    emit(
      [:condukt, :agent, :start],
      %{system_time: System.system_time()},
      %{agent: __MODULE__}
    )

    assert Repo.aggregate(Event, :count) == 0
  end

  test "stores subagent role in :name and parent/child ids in metadata" do
    session = insert_running_session()
    parent_id = session.id
    child_id = SessionID.generate()

    emit(
      [:condukt, :subagent, :stop],
      %{duration: System.convert_time_unit(120, :millisecond, :native)},
      %{
        agent: __MODULE__,
        role: :researcher,
        child_agent: __MODULE__,
        input?: false,
        output?: false,
        status: :ok,
        parent_session_id: parent_id,
        session_id: parent_id
      }
    )

    [event] = Repo.all(from e in Event, where: e.agent_session_id == ^parent_id)
    assert event.type == "subagent"
    assert event.name == "researcher"
    assert event.metadata["role"] == "researcher"
    assert event.metadata["status"] == "ok"
    refute Map.has_key?(event.metadata, "session_id")
    refute child_id == event.metadata["parent_session_id"]
  end

  @tag :capture_log
  test "swallows a failing insert so telemetry does not detach the handler" do
    session = insert_running_session()
    parent = self()

    # A process the SQL sandbox has not granted a connection to, which is what
    # an agent running under a task supervisor looks like. `:telemetry` detaches
    # a handler for the whole node the first time it raises, so an event emitted
    # from here must not be allowed to take the audit trail down with it.
    task =
      Task.async(fn ->
        Process.delete(:"$callers")
        send(parent, :ready)

        TelemetryHandler.handle_event(
          [:condukt, :run, :start],
          %{system_time: System.system_time()},
          %{agent: __MODULE__, session_id: session.id},
          nil
        )
      end)

    assert_receive :ready
    assert Task.await(task) == :ok
  end

  @tag :capture_log
  test "swallows an exiting insert so telemetry does not detach the handler" do
    session = insert_running_session()

    # `:telemetry` matches every exception class before it detaches, not only
    # raises, so an exit crossing the handler takes the audit trail down for the
    # whole node just as a raise would. `%ExitingInspect{}` exits from inside
    # `sanitize/1`, which is what a connection that has gone away underneath the
    # insert looks like from here.
    assert TelemetryHandler.handle_event(
             [:condukt, :run, :start],
             %{system_time: System.system_time()},
             %{agent: __MODULE__, session_id: session.id, detail: %ExitingInspect{}},
             nil
           ) == :ok

    assert Repo.aggregate(Event, :count) == 0
  end

  defp emit(event, measurements, metadata) do
    TelemetryHandler.handle_event(event, measurements, metadata, nil)
  end

  defp insert_running_session do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "audit:test:#{System.unique_integer([:positive])}",
        name: "Audit Test",
        segment: :lead
      })
      |> Repo.insert!()

    %{
      id: SessionID.generate(),
      agent: "Atlas.Agents.Sessions.TelemetryHandlerTest",
      prompt: "test prompt",
      status: "running",
      started_at: DateTime.utc_now(),
      account_id: account.id
    }
    |> Session.create_changeset()
    |> Repo.insert!()
  end
end
