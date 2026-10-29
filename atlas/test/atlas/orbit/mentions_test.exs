defmodule Atlas.Orbit.MentionsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Atlas.OrbitFixtures
  import Atlas.PushFixtures

  alias Atlas.Authorization.UserRole
  alias Atlas.LLMs.Runner
  alias Atlas.Orbit
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.ModelFence
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Tools
  alias Atlas.Push
  alias Atlas.Push.Config
  alias Atlas.Push.Workers.Deliver

  setup do
    stub(Runner, :orbit_configured?, fn _ -> false end)
    stub(Config, :capabilities, fn -> %{"ios" => true, "android" => true} end)
    stub(Config, :available?, fn _, _ -> true end)
    owner = user_fixture(["finance:read", "documents:read"])
    {:ok, thread, _} = Orbit.ensure_private(owner)
    %{owner: owner, thread: thread}
  end

  test "explicit IDs atomically promote, invite, provide factual excerpts and enqueue once", %{
    owner: owner,
    thread: thread
  } do
    newcomer = user_fixture()
    {:ok, ios} = Push.register(newcomer, native_client_id(newcomer), Ecto.UUID.generate(), ios_device())
    {:ok, android} = Push.register(newcomer, native_client_id(newcomer), Ecto.UUID.generate(), android_device())
    {:ok, _} = Repo.transaction(fn -> Orbit.append!(thread, %{kind: "human", body: "\n \t"}) end)
    {:ok, _, :created} = Orbit.post_message(owner, thread, attrs("Initial\nrequest"))
    {:ok, _} = Repo.transaction(fn -> Orbit.append!(thread, %{kind: "agent", body: "Latest factual reply"}) end)
    Repo.update!(Ecto.Changeset.change(Repo.reload!(thread), title: "Pip"))
    params = attrs("Please join", [newcomer.id, newcomer.id])

    assert {:ok, message, :created} = Orbit.post_message(owner, thread, params)
    assert message.mentioned_user_ids == [newcomer.id]
    assert {:ok, shared} = Orbit.fetch(newcomer, thread.id)
    assert shared.kind == "shared" and shared.owner_id == owner.id and shared.title == "Initial request"
    assert length(shared.participants) == 2
    notice = Repo.get_by!(Message, thread_id: thread.id, notice_kind: "private_handoff")
    assert notice.kind == "system"
    assert notice.recipient_id == newcomer.id
    assert notice.body == ""
    assert notice.private_body =~ "not an AI-generated summary"
    assert notice.private_body =~ "> Initial\n> request"
    assert notice.private_body =~ "> Latest factual reply"

    {recipient_history, _} = Orbit.list_messages(shared, 1, newcomer)
    {owner_history, _} = Orbit.list_messages(shared, 1, owner)
    {agent_history, _} = Orbit.list_messages(shared)
    assert Enum.any?(recipient_history, &(&1.id == notice.id))
    refute Enum.any?(owner_history ++ agent_history, &(&1.id == notice.id))
    refute Atlas.Orbit.Agent.transcript(recipient_history) =~ "Conversation so far"
    assert Enum.any?(owner_history, &(&1.notice_kind == "joined" and &1.body =~ "joins the conversation"))

    assert {:ok, replay, :existing} =
             Orbit.post_message(owner, thread, %{params | "mention_ids" => [Ecto.UUID.generate()]})

    assert replay.id == message.id
    assert {:ok, _, :existing} = Orbit.post_message(owner, thread, %{params | "mention_ids" => "bad"})

    assert Repo.aggregate(
             from(m in Message, where: m.thread_id == ^thread.id and m.notice_kind == "private_handoff"),
             :count
           ) ==
             1

    jobs = all_enqueued(worker: Deliver)
    assert Enum.sort(Enum.map(jobs, & &1.args["registration_id"])) == Enum.sort([ios.id, android.id])

    for job <- jobs do
      assert job.args["kind"] == "orbit_mentioned"
      assert job.args["message_id"] == message.id
      assert job.args["user_id"] == newcomer.id
      refute Map.has_key?(job.args, "body")
      refute Map.has_key?(job.args, "title")
    end
  end

  test "replaying an earlier unmentioned private message never promotes or invites replacement IDs", %{
    owner: owner,
    thread: thread
  } do
    newcomer = user_fixture()
    params = attrs("Original private question")
    assert {:ok, original, :created} = Orbit.post_message(owner, thread, params)
    revision = Repo.reload!(thread).last_seq
    assert {:ok, replay, :existing} = Orbit.post_message(owner, thread, %{params | "mention_ids" => [newcomer.id]})
    assert replay.id == original.id and replay.mentioned_user_ids == []
    assert Repo.reload!(thread).kind == "private" and Repo.reload!(thread).last_seq == revision
    assert {:error, :not_found} = Orbit.fetch(newcomer, thread.id)
    refute_enqueued(worker: Deliver)
  end

  test "unknown, malformed and history-ineligible IDs reject the entire mutation", %{owner: owner, thread: thread} do
    allowed = user_fixture(["finance:read", "documents:read"])
    denied = user_fixture(["finance:read"])
    thread = Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["finance:read", "documents:read"]))

    for ids <- [
          [allowed.id, denied.id],
          [allowed.id, Ecto.UUID.generate()],
          ["bad"],
          nil,
          %{},
          List.duplicate(allowed.id, 11)
        ] do
      assert {:error, {:invalid_field, :mention_ids}} = Orbit.post_message(owner, thread, attrs("Do not publish", ids))
      assert Repo.reload!(thread).kind == "private"
      assert Repo.reload!(thread).last_seq == 0
      assert {:error, :not_found} = Orbit.fetch(allowed, thread.id)
      refute_enqueued(worker: Deliver)
    end
  end

  test "rollback after membership expansion restores title, participants, cancellation and notifications", %{
    owner: owner,
    thread: thread
  } do
    newcomer = user_fixture()
    run = running_run(thread, owner)

    assert {:error, {:invalid_field, :attachment_ids}} =
             Orbit.post_message(
               owner,
               thread,
               Map.put(attrs("Join", [newcomer.id]), "attachment_ids", [Ecto.UUID.generate()])
             )

    assert Repo.reload!(thread).kind == "private"
    assert Repo.reload!(thread).title == "New conversation"
    assert Repo.reload!(thread).last_seq == 0
    assert Repo.reload!(run).cancel_requested_at == nil
    assert {:error, :not_found} = Orbit.fetch(newcomer, thread.id)
    refute_enqueued(worker: Deliver)
  end

  test "delivery enqueue rollback leaves no promoted audience, handoff, message or job", %{owner: owner, thread: thread} do
    newcomer = user_fixture()
    {:ok, _} = Push.register(newcomer, native_client_id(newcomer), Ecto.UUID.generate(), ios_device())

    expect(Oban, :insert_all, fn jobs ->
      assert length(jobs) == 1
      Repo.rollback(:enqueue_failed)
    end)

    assert {:error, :enqueue_failed} = Orbit.post_message(owner, thread, attrs("Join", [newcomer.id]))
    assert Repo.reload!(thread).kind == "private" and Repo.reload!(thread).last_seq == 0
    assert {:error, :not_found} = Orbit.fetch(newcomer, thread.id)
    refute_enqueued(worker: Deliver)
  end

  test "only the owner expands the audience; members can ping current people without another handoff", %{owner: owner} do
    member = user_fixture()
    outsider = user_fixture()
    {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Meaningful title", "participant_ids" => [member.id]})
    assert {:error, :forbidden} = Orbit.post_message(member, shared, attrs("Invite", [outsider.id]))
    assert {:error, :not_found} = Orbit.fetch(outsider, shared.id)
    assert {:ok, _, :created} = Orbit.post_message(member, shared, attrs("@any name is not an invitation", [owner.id]))
    assert {:ok, _, :created} = Orbit.post_message(owner, shared, attrs("@outsider without selected ID"))

    assert Repo.aggregate(
             from(m in Message, where: m.thread_id == ^shared.id and m.notice_kind == "private_handoff"),
             :count
           ) == 1

    assert {:ok, _, :created} = Orbit.post_message(owner, shared, attrs("Invite", [outsider.id]))
    assert Repo.reload!(shared).title == "Meaningful title"
    assert {:ok, _} = Orbit.fetch(outsider, shared.id)
  end

  test "promotion fences in-flight model dispatch, tools and final replies", %{owner: owner, thread: thread} do
    newcomer = user_fixture()
    run = running_run(thread, owner)
    assert ModelFence.authorized?(%{private: %{orbit_model_fence: {run.id, 0}}})
    assert {:ok, _, :created} = Orbit.post_message(owner, thread, attrs("Join", [newcomer.id]))
    assert Repo.reload!(run).cancel_requested_at
    refute ModelFence.authorized?(%{private: %{orbit_model_fence: {run.id, 0}}})
    assert {:error, _} = Tools.call(run.id, 0, "list_tasks", %{})
    assert :ok = Runs.complete(run.id, 0, {:ok, "Private in-flight response must not publish"})
    assert Repo.reload!(run).status == "cancelled"
    refute Repo.exists?(from m in Message, where: m.thread_id == ^thread.id and m.kind == "agent")
    refute_enqueued(worker: Deliver, args: %{kind: "orbit_completed"})
  end

  test "an already completed reply becomes the handoff excerpt; titles are bounded at first-message promotion", %{
    owner: owner,
    thread: thread
  } do
    newcomer = user_fixture()
    run = running_run(thread, owner)
    assert :ok = Runs.complete(run.id, 0, {:ok, String.duplicate("Reply ", 400)})
    body = "Start\n" <> String.duplicate("a\u0301", 200)
    assert {:ok, _, :created} = Orbit.post_message(owner, thread, attrs(body, [newcomer.id]))
    assert length(String.codepoints(Repo.reload!(thread).title)) == 200
    notice = Repo.get_by!(Message, thread_id: thread.id, notice_kind: "private_handoff")
    assert notice.body == ""
    assert notice.private_body =~ "Reply Reply"
    assert byte_size(notice.private_body) < 7_000
  end

  test "recaps remain recipient-only across multiple invites, access loss and deletion", %{owner: owner, thread: thread} do
    first = user_fixture(["finance:read"])
    second = user_fixture(["finance:read"])
    thread = Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["finance:read"]))

    assert {:ok, _, :created} =
             Orbit.post_message(owner, thread, attrs("Investigate the balance", [first.id, second.id]))

    for person <- [first, second] do
      {history, _} = Orbit.list_messages(thread, 1, person)
      assert [notice] = Enum.filter(history, &(&1.notice_kind == "private_handoff"))
      assert notice.recipient_id == person.id
      assert notice.body =~ "Investigate the balance"
    end

    # The old server selects body without recipient awareness. Its readable text
    # must contain none of the private recap, even after a new server has written it.
    legacy = Repo.all(from m in Message, where: m.thread_id == ^thread.id, select: m.body)
    refute Enum.any?(legacy, &String.contains?(&1, "Conversation so far"))

    assert {:ok, _} = Orbit.add_participant(owner, thread, first.id)

    assert Repo.aggregate(from(m in Message, where: m.thread_id == ^thread.id and not is_nil(m.recipient_id)), :count) ==
             2

    Repo.delete_all(from role in UserRole, where: role.user_id == ^first.id)
    assert {[], %{total_count: 0}} = Orbit.list_messages(thread, 1, first)
    assert :ok = Orbit.remove_participant(owner, thread, second.id)
    assert {[], %{total_count: 0}} = Orbit.list_messages(thread, 1, second)
    Repo.delete!(first)
    refute Repo.exists?(from m in Message, where: m.recipient_id == ^first.id)
    assert Repo.exists?(from m in Message, where: m.thread_id == ^thread.id and m.notice_kind == "joined")
  end

  test "archival, removal and scope revocation cannot be bypassed by stale handles", %{owner: owner, thread: thread} do
    newcomer = user_fixture()
    Repo.update!(Ecto.Changeset.change(thread, status: "archived"))
    assert {:error, :archived} = Orbit.post_message(owner, thread, attrs("Join", [newcomer.id]))
    assert {:error, _} = Orbit.mention_people(owner, thread)
    Repo.update!(Ecto.Changeset.change(Repo.reload!(thread), status: "active", required_scopes: ["finance:read"]))
    Repo.delete_all(from role in UserRole, where: role.user_id == ^owner.id)
    assert {:error, :not_found} = Orbit.post_message(owner, thread, attrs("Join", [newcomer.id]))
    assert {:error, :not_found} = Orbit.mention_people(owner, thread)
  end

  defp attrs(body, ids \\ []) do
    %{"body" => body, "client_id" => Ecto.UUID.generate(), "address_agent" => false, "mention_ids" => ids}
  end

  defp running_run(thread, owner) do
    Repo.insert!(%Run{
      thread_id: thread.id,
      acting_user_id: owner.id,
      initiator_id: owner.id,
      status: "running",
      trigger_seq: 0,
      resume_count: 0
    })
  end
end
