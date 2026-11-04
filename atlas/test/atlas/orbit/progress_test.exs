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

  test "routine pruning checks keep the run running; only actual pruning adds a notice" do
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    run = running(thread, owner)
    meta = %{agent: Agent, session_id: run.session_id}
    revision = Repo.get!(Orbit.Thread, thread.id).last_seq

    Progress.handle_event([:condukt, :compact, :start], %{}, meta, nil)
    assert Viewers.snapshot(thread).agent_status == "running"
    assert Repo.get!(Orbit.Thread, thread.id).last_seq == revision

    Progress.handle_event([:condukt, :compact, :stop], %{}, Map.put(meta, :changed, false), nil)
    assert Viewers.snapshot(thread).agent_status == "running"
    refute Repo.exists?(from message in Message, where: message.run_id == ^run.id)

    Progress.handle_event([:condukt, :compact, :start], %{}, meta, nil)
    Progress.handle_event([:condukt, :compact, :stop], %{}, Map.put(meta, :changed, true), nil)
    notice = Repo.get_by!(Message, run_id: run.id)
    assert notice.kind == "system" and notice.body =~ "older context is ready"
    assert Viewers.snapshot(thread).agent_status == "running"
  end

  test "stale sessions, cancelled runs and other agents cannot publish pruning notices" do
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    run = running(thread, owner)
    event = [:condukt, :compact, :stop]
    Progress.handle_event(event, %{}, %{agent: Agent, session_id: "old-session", changed: true}, nil)
    Progress.handle_event(event, %{}, %{agent: __MODULE__, session_id: run.session_id, changed: true}, nil)
    assert Repo.get!(Run, run.id).activity == nil
    Repo.update!(Ecto.Changeset.change(run, cancel_requested_at: DateTime.utc_now()))
    Progress.handle_event(event, %{}, %{agent: Agent, session_id: run.session_id, changed: true}, nil)
    assert Repo.get!(Run, run.id).activity == nil
    refute Repo.exists?(from message in Message, where: message.run_id == ^run.id)
  end

  test "a failed compaction stop clears activity without claiming success or failing the run" do
    owner = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(owner)
    run = running(thread, owner)
    metadata = %{agent: Agent, session_id: run.session_id}
    Repo.update!(Ecto.Changeset.change(run, activity: "compacting"))

    Progress.handle_event(
      [:condukt, :compact, :stop],
      %{},
      Map.merge(metadata, %{status: :error, changed: false}),
      nil
    )

    assert Repo.get!(Run, run.id).activity == nil
    assert Repo.get!(Run, run.id).status == "running"
    refute Repo.exists?(from message in Message, where: message.run_id == ^run.id)
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
