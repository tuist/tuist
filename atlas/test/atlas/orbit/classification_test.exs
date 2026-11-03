defmodule Atlas.Orbit.ClassificationTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Atlas.OrbitFixtures

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.Sessions.Event
  alias Atlas.Agents.Sessions.Session
  alias Atlas.Audit.Activity
  alias Atlas.LLMs.Runner
  alias Atlas.Orbit
  alias Atlas.Orbit.Classification
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Workers.ClassifyThread

  test "real structured inference labels once, preserves recency, and redacts audits" do
    user = user_fixture()
    {:ok, thread} = Orbit.create_shared(user, %{"title" => "Build failures"})
    stub(Runner, :orbit_configured?, fn _ -> true end)

    {:ok, message, :created} =
      Orbit.post_message(user, thread, %{
        "body" => "PRIVATE classifier evidence",
        "client_id" => Ecto.UUID.generate(),
        "address_agent" => false
      })

    assert_enqueued(worker: ClassifyThread, args: %{thread_id: thread.id, message_id: message.id, user_id: user.id})
    before = Repo.reload!(thread)
    caller = self()

    stub(Sessions, :with_session, fn agent, label, fun ->
      Mimic.call_original(Sessions, :with_session, [
        agent,
        label,
        [],
        fn opts ->
          session_id = Keyword.fetch!(opts, :id)
          handler = "classification-test-#{session_id}"

          :telemetry.attach_many(
            handler,
            [[:condukt, :agent, :start], [:condukt, :llm_turn, :start]],
            fn _, _, metadata, _ ->
              if metadata[:session_id] == session_id, do: Ecto.Adapters.SQL.Sandbox.allow(Repo, caller, self())
            end,
            nil
          )

          on_exit(fn -> :telemetry.detach(handler) end)
          fun.(opts)
        end
      ])
    end)

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(body)
      send(caller, {:request, request})

      result =
        if Enum.any?(request["messages"], &(&1["role"] == "tool")),
          do: completion(%{"role" => "assistant", "content" => ""}),
          else: tool_call("submit_result", %{"domain" => "engineering"})

      Req.Test.json(conn, result)
    end

    stub(Runner, :orbit_client_opts, fn ^user, _ ->
      [
        model: ReqLLM.model!(%{id: "atlas-orbit", provider: :openai}),
        api_key: "fixture-only",
        llm_request_options: [req_http_options: [plug: plug]]
      ]
    end)

    assert :ok = Classification.classify(thread.id, message.id, user.id)
    assert_receive {:request, request}
    assert inspect(request["messages"]) =~ "PRIVATE classifier evidence"
    assert Enum.map(request["tools"], & &1["function"]["name"]) == ["submit_result"]
    labeled = Repo.get!(Thread, thread.id)
    assert labeled.domain == "engineering"
    assert labeled.updated_at == before.updated_at
    assert labeled.last_seq == before.last_seq + 1
    assert :ok = Classification.classify(thread.id, message.id, user.id)
    assert Repo.reload!(labeled).last_seq == labeled.last_seq
    session = Repo.one!(from s in Session, where: s.agent == ^inspect(Classification))
    assert session.result == %{"redacted" => true}
    refute inspect(session) =~ "PRIVATE classifier evidence"
    refute inspect(Repo.all(from e in Event, where: e.agent_session_id == ^session.id)) =~ "PRIVATE classifier evidence"

    assert {:ok, archived} = Orbit.set_status(user, labeled, "archived")
    archived = archived |> Ecto.Changeset.change(domain: nil) |> Repo.update!()
    assert :ok = Classification.classify(thread.id, message.id, user.id)
    backfilled = Repo.reload!(archived)
    assert backfilled.domain == "engineering"
    assert backfilled.status == "archived"
    assert backfilled.updated_at == archived.updated_at
    assert backfilled.last_seq == archived.last_seq + 1
  end

  test "a lost audience cannot be labeled, including archived history" do
    owner = user_fixture()
    outsider = user_fixture()
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Builds"})

    {:ok, message, :created} =
      Orbit.post_message(owner, thread, %{
        "body" => "A build",
        "client_id" => Ecto.UUID.generate(),
        "address_agent" => false
      })

    reject(&Runner.orbit_client_opts/2)
    assert :ok = Classification.classify(thread.id, message.id, outsider.id)
    assert {:ok, _} = Orbit.set_status(owner, thread, "archived")
    assert :ok = Classification.classify(thread.id, message.id, outsider.id)
    assert Repo.reload!(thread).domain == nil
  end

  test "backfill dry run is read only and application queues only eligible history once" do
    owner = user_fixture()
    unconfigured = user_fixture()
    stub(Runner, :orbit_configured?, fn user -> user.id != unconfigured.id end)
    reject(&Runner.orbit_client_opts/2)

    history = fn user, attrs, message_attrs ->
      {:ok, thread} = Orbit.create_shared(user, Map.merge(%{"title" => "Historical conversation"}, attrs))
      {:ok, message} = Repo.transaction(fn -> Orbit.append!(thread, message_attrs) end)
      {thread, message}
    end

    {:ok, private, :created} = Orbit.ensure_private(owner)

    {:ok, private_message} =
      Repo.transaction(fn -> Orbit.append!(private, %{kind: "human", body: "A private build question"}) end)

    {archived, archived_message} = history.(owner, %{}, %{kind: "human", body: "A shared build question"})
    {:ok, archived} = Orbit.set_status(owner, archived, "archived")

    {signal, signal_message} =
      history.(owner, %{}, %{kind: "system", body: "Build failures increased", address_agent: true})

    signal = signal |> Ecto.Changeset.change(origin: "signal") |> Repo.update!()

    {labeled, _} = history.(owner, %{}, %{kind: "human", body: "Already labeled"})
    labeled |> Ecto.Changeset.change(domain: "people") |> Repo.update!()
    {denied, _} = history.(owner, %{}, %{kind: "human", body: "Restricted evidence"})
    denied |> Ecto.Changeset.change(required_scopes: ["engineering:read"]) |> Repo.update!()
    history.(unconfigured, %{}, %{kind: "human", body: "No provider"})
    history.(owner, %{}, %{kind: "human", body: " \n\t "})
    history.(owner, %{}, %{kind: "tool", body: "Tool evidence is not a source"})
    history.(owner, %{}, %{kind: "system", body: "Manual system notice", address_agent: true})

    history.(owner, %{}, %{
      kind: "system",
      body: "",
      private_body: "Private catch-up",
      notice_kind: "private_handoff",
      recipient_id: owner.id
    })

    {orphan, _} = history.(owner, %{}, %{kind: "human", body: "No owner"})
    orphan |> Ecto.Changeset.change(owner_id: nil) |> Repo.update!()

    before =
      Repo.all(from thread in Thread, order_by: thread.id, select: {thread.id, thread.last_seq, thread.updated_at})

    audits = Repo.aggregate(Activity, :count)

    assert Classification.backfill(dry_run: true) == %{scanned: 5, eligible: 3, enqueued: 0}
    assert all_enqueued(worker: ClassifyThread) == []
    assert Repo.aggregate(Activity, :count) == audits
    assert Classification.backfill(limit: 1, dry_run: true).scanned == 1
    assert Classification.backfill() == %{scanned: 5, eligible: 3, enqueued: 3}
    assert Classification.backfill() == %{scanned: 5, eligible: 3, enqueued: 0}

    expected =
      for {thread, message} <- [{private, private_message}, {archived, archived_message}, {signal, signal_message}] do
        %{"thread_id" => thread.id, "message_id" => message.id, "user_id" => owner.id}
      end

    assert all_enqueued(worker: ClassifyThread) |> Enum.map(& &1.args) |> Enum.sort() == Enum.sort(expected)

    assert Repo.all(from thread in Thread, order_by: thread.id, select: {thread.id, thread.last_seq, thread.updated_at}) ==
             before

    assert Repo.reload!(labeled).domain == "people"
  end

  test "backfill reaches histories beyond its first batch" do
    owner = user_fixture()
    stub(Runner, :orbit_configured?, fn _ -> true end)
    reject(&Runner.orbit_client_opts/2)

    for _ <- 1..101 do
      {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Historical build question"})
      {:ok, _} = Repo.transaction(fn -> Orbit.append!(thread, %{kind: "human", body: "Build evidence"}) end)
    end

    assert Classification.backfill() == %{scanned: 101, eligible: 101, enqueued: 101}
    assert length(all_enqueued(worker: ClassifyThread)) == 101
  end
end
