defmodule Atlas.Orbit.ProgressTest do
  use Atlas.DataCase, async: true

  import Atlas.OrbitFixtures

  alias Atlas.Orbit
  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Progress
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Viewers
  alias Atlas.Repo

  test "compaction is visible without advancing the message revision; only actual pruning adds a notice" do
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    run = running(thread, owner)
    meta = %{agent: Agent, session_id: run.session_id}
    revision = Repo.get!(Orbit.Thread, thread.id).last_seq

    Progress.handle_event([:condukt, :compact, :start], %{}, meta, nil)
    assert Viewers.snapshot(thread).agent_status == "compacting"
    assert Repo.get!(Orbit.Thread, thread.id).last_seq == revision

    Progress.handle_event([:condukt, :compact, :stop], %{}, Map.put(meta, :changed, false), nil)
    assert Viewers.snapshot(thread).agent_status == "running"
    refute Repo.exists?(from message in Message, where: message.run_id == ^run.id)

    Progress.handle_event([:condukt, :compact, :start], %{}, meta, nil)
    Progress.handle_event([:condukt, :compact, :stop], %{}, Map.put(meta, :changed, true), nil)
    notice = Repo.get_by!(Message, run_id: run.id)
    assert notice.kind == "system" and notice.body =~ "Context compacted"
    assert Viewers.snapshot(thread).agent_status == "running"
  end

  test "stale sessions, cancelled runs and other agents cannot publish activity" do
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    run = running(thread, owner)
    event = [:condukt, :compact, :start]
    Progress.handle_event(event, %{}, %{agent: Agent, session_id: "old-session"}, nil)
    Progress.handle_event(event, %{}, %{agent: __MODULE__, session_id: run.session_id}, nil)
    assert Repo.get!(Run, run.id).activity == nil
    Repo.update!(Ecto.Changeset.change(run, cancel_requested_at: DateTime.utc_now()))
    Progress.handle_event(event, %{}, %{agent: Agent, session_id: run.session_id}, nil)
    assert Repo.get!(Run, run.id).activity == nil
  end

  defp running(thread, user) do
    Repo.insert!(%Run{
      thread_id: thread.id,
      acting_user_id: user.id,
      status: "running",
      trigger_seq: 0,
      session_id: Ecto.UUID.generate()
    })
  end
end
