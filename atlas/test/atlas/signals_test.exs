defmodule Atlas.SignalsTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.AutomationsFixtures
  import Atlas.OrbitFixtures

  alias Atlas.Authorization.UserRole
  alias Atlas.Automations
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Run
  alias Atlas.LLMs.Runner
  alias Atlas.Orbit
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Thread
  alias Atlas.Signals
  alias Atlas.Signals.Signal
  alias Atlas.Users.BusinessProfile

  setup do
    stub(Runner, :orbit_configured?, fn _ -> true end)
    actor = user_fixture(["automation:write", "accounts:read"])
    %{actor: actor}
  end

  test "a published policy opens one correlated investigation, queues Pip and preserves retries", %{actor: actor} do
    member = user_fixture(["accounts:read"])
    profile(member, %{"responsibilities" => ["account:acme"]})
    source = source(actor, [member.id])
    envelope = envelope()
    assert {:error, :source_disabled} = Signals.ingest(actor, source.id, envelope)
    assert {:ok, _} = Signals.set_enabled(actor, source.id, true)
    assert {:ok, received} = Signals.ingest(actor, source.id, envelope)
    assert {:ok, ^received} = Signals.ingest(actor, source.id, envelope)
    assert {:error, :idempotency_conflict} = Signals.ingest(actor, source.id, %{envelope | "summary" => "Changed"})
    assert Repo.aggregate(Signal, :count) == 1
    assert %Run{input: input, trigger: "signal"} = Repo.get!(Run, received.execution_id)
    assert input == %{"signal_id" => received.id}
    assert %Run{status: "succeeded", outputs: outputs} = drain(received.execution_id)
    assert outputs["triage"]["status"] == "opened"
    refute JSON.encode!(outputs) =~ "Customer asks"
    assert {:ok, opened} = Signals.get(actor, received.id)
    assert opened.priority == "today"
    assert [%{"id" => id, "reason" => "responsibility"}] = opened.decision["routing"]
    assert id == member.id
    assert {:ok, thread} = Orbit.fetch(member, opened.thread_id)
    assert thread.priority == "today"
    assert thread.required_scopes == ["accounts:read"]
    assert Repo.get_by!(Atlas.Orbit.Run, thread_id: thread.id).acting_user_id == actor.id
    {messages, _} = Orbit.list_messages(thread)
    assert Enum.any?(messages, &(&1.body =~ envelope["summary"]))
    assert {:ok, replay} = Signals.decide(actor, decision(received.id))
    assert replay.thread_id == thread.id
    assert Repo.aggregate(from(m in Message, where: m.thread_id == ^thread.id), :count) == length(messages) + 1
    assert {:error, :idempotency_conflict} = Signals.decide(actor, %{decision(received.id) | "priority" => "now"})

    assert {:ok, next} = Signals.ingest(actor, source.id, %{envelope | "external_id" => "follow-up"})
    assert %Run{status: "succeeded"} = drain(next.execution_id)
    assert {:ok, next} = Signals.get(actor, next.id)
    assert next.thread_id == thread.id
    assert Repo.aggregate(Thread, :count) == 1

    assert {:ok, _, :created} =
             Orbit.post_message(member, thread, %{
               "body" => "Investigate the docs first",
               "client_id" => Ecto.UUID.generate(),
               "address_agent" => true
             })
  end

  test "routing ranks shared responsibilities, expertise and roles, never private descriptions", %{actor: actor} do
    role = user_fixture(["accounts:read"])
    expert = user_fixture(["accounts:read"])
    owner = user_fixture(["accounts:read"])
    private = user_fixture(["accounts:read"])
    denied = user_fixture([])
    outsider = user_fixture(["accounts:read"])
    profile(role, %{"role" => "support"})
    profile(expert, %{"expertise" => ["Caching"]})
    profile(owner, %{"responsibilities" => ["account:acme"]})
    profile(denied, %{"responsibilities" => ["account:acme"]})
    profile(outsider, %{"responsibilities" => ["account:acme"]})
    {:ok, _} = Atlas.Users.update_my_profile(private, "I own account:acme and caching support")
    source = source(actor, [role.id, expert.id, owner.id, private.id, denied.id])
    {:ok, _} = Signals.set_enabled(actor, source.id, true)
    {:ok, signal} = Signals.ingest(actor, source.id, envelope())
    assert {:ok, %{candidates: candidates}} = Signals.candidates(actor, signal.id)

    assert Enum.map(candidates, &{&1.id, &1.reason}) == [
             {owner.id, "responsibility"},
             {expert.id, "expertise"},
             {role.id, "business_role"}
           ]

    profile(owner, %{"enabled" => false, "responsibilities" => ["account:acme"]})
    assert {:ok, %{candidates: remaining}} = Signals.candidates(actor, signal.id)
    refute Enum.any?(remaining, &(&1.id == owner.id))
    assert {:error, :not_found} = Signals.get(outsider, signal.id)

    observer = user_fixture(["automation:read", "accounts:read"])
    assert {:ok, %{items: []}} = Signals.list(observer)
  end

  test "source audience also bounds human invitations and later evidence", %{actor: actor} do
    member = user_fixture(["accounts:read"])
    outsider = user_fixture(["accounts:read"])
    profile(member, %{"role" => "support"})
    source = source(actor, [member.id])
    {:ok, _} = Signals.set_enabled(actor, source.id, true)
    {:ok, signal} = Signals.ingest(actor, source.id, envelope())
    {:ok, signal} = Signals.decide(actor, decision(signal.id))
    {:ok, thread} = Orbit.fetch(actor, signal.thread_id)
    assert {:error, :missing_access} = Orbit.add_participant(actor, thread, outsider.id)

    assert {:error, {:invalid_field, :mention_ids}} =
             Orbit.post_message(actor, thread, %{
               "body" => "Please join",
               "client_id" => Ecto.UUID.generate(),
               "mention_ids" => [outsider.id]
             })

    assert {:ok, people} = Orbit.mention_people(actor, thread)
    refute Enum.any?(people, &(&1.id == outsider.id))
    Repo.delete_all(from assignment in UserRole, where: assignment.user_id == ^member.id)
    assert {:error, :not_found} = Orbit.fetch(member, thread.id)
    assert {[], _} = Orbit.list_for_user(member)
    {:ok, next} = Signals.ingest(actor, source.id, %{envelope() | "external_id" => "new-evidence"})
    before_count = Repo.aggregate(Message, :count)
    assert {:error, :missing_access} = Signals.decide(actor, decision(next.id))
    assert Repo.aggregate(Message, :count) == before_count
    assert {:ok, %{status: "pending"}} = Signals.get(actor, next.id)
  end

  test "ignore, pause, source isolation and priority order", %{actor: actor} do
    source = source(actor, [])
    second = source(actor, [])
    envelope = envelope()
    Enum.each([source, second], &Signals.set_enabled(actor, &1.id, true))
    {:ok, later} = Signals.ingest(actor, source.id, envelope)
    {:ok, now} = Signals.ingest(actor, second.id, envelope)
    {:ok, _} = Signals.decide(actor, decision(later.id, "ignored", "later"))
    {:ok, _} = Signals.decide(actor, decision(now.id, "opened", "now"))
    assert {:ok, %{items: items}} = Signals.list(actor)
    assert Enum.map(items, & &1.id) == [now.id, later.id]
    assert {:ok, %{items: [ignored]}} = Signals.list(actor, %{"status" => "ignored"})
    assert ignored.thread_id == nil
    {:ok, pending} = Signals.ingest(actor, source.id, %{envelope() | "external_id" => "pending"})
    {:ok, _} = Signals.set_enabled(actor, source.id, false)
    assert {:error, :source_disabled} = Signals.decide(actor, decision(pending.id))
    assert {:ok, _} = Signals.ingest(actor, source.id, envelope)
    assert {:error, :source_disabled} = Signals.ingest(actor, source.id, %{envelope() | "external_id" => "blocked"})
  end

  test "invalid evidence and failed workflow admission leave no partial signal", %{actor: actor} do
    source = source(actor, [])
    {:ok, _} = Signals.set_enabled(actor, source.id, true)

    for invalid <- [
          Map.put(envelope(), "occurred_at", "yesterday"),
          Map.put(envelope(), "data", %{"body" => String.duplicate("x", 12_000)}),
          Map.put(envelope(), "external_id", "invalid\0id"),
          Map.put(envelope(), "owner_id", actor.id)
        ] do
      assert {:error, _} = Signals.ingest(actor, source.id, invalid)
    end

    {:ok, workflow} =
      Automations.create_workflow(actor, %{
        "name" => "Incompatible",
        "source" => JSON.encode!(%{"steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{}}]}),
        "input_schema" => %{"type" => "object", "required" => ["not_signal_id"]}
      })

    {:ok, revision} = Automations.publish_workflow(actor, workflow.id)

    {:ok, invalid_source} =
      Signals.create_source(actor, %{
        "name" => "Incompatible",
        "revision_id" => revision.id,
        "reader_ids" => [],
        "required_scopes" => []
      })

    {:ok, _} = Signals.set_enabled(actor, invalid_source.id, true)
    assert {:error, _} = Signals.ingest(actor, invalid_source.id, envelope())
    assert Repo.aggregate(Signal, :count) == 0
    assert Repo.aggregate(Run, :count) == 0

    # Multibyte summaries and reasons must not duplicate evidence past Orbit's
    # body budget after admission has accepted the complete envelope.
    large =
      Map.merge(envelope(), %{
        "summary" => String.duplicate("🦊", 1000),
        "data" => %{"body" => String.duplicate("x", 7000)}
      })

    assert {:ok, received} = Signals.ingest(actor, source.id, large)
    assert {:ok, opened} = Signals.decide(actor, Map.put(decision(received.id), "reason", String.duplicate("🦊", 500)))
    {:ok, thread} = Orbit.fetch(actor, opened.thread_id)
    {messages, _} = Orbit.list_messages(thread)
    assert Enum.any?(messages, &String.contains?(&1.body, large["data"]["body"]))
    assert Enum.all?(messages, &(byte_size(&1.body) <= 16_000))
  end

  defp source(actor, readers) do
    {_, revision} =
      workflow_fixture(actor, [
        %{"id" => "triage", "behavior" => "signals.decide@1", "inputs" => decision(%{"$ref" => "input.signal_id"})}
      ])

    {:ok, source} =
      Signals.create_source(actor, %{
        "name" => "Customer questions",
        "revision_id" => revision.id,
        "reader_ids" => readers,
        "required_scopes" => ["accounts:read"],
        "routing_roles" => ["support"]
      })

    source
  end

  defp envelope do
    %{
      "external_id" => "external-#{System.unique_integer([:positive])}",
      "correlation_key" => "customer-conversation",
      "type" => "customer.question",
      "schema_version" => 1,
      "occurred_at" => "2026-10-28T10:00:00Z",
      "title" => "Customer asks about caching",
      "summary" => "Customer asks whether the docs cover remote caching",
      "subjects" => ["account:acme"],
      "topics" => ["caching"]
    }
  end

  defp decision(id, action \\ "opened", priority \\ "today"),
    do: %{"signal_id" => id, "action" => action, "priority" => priority, "reason" => "Source policy"}

  defp profile(user, attrs) do
    {:ok, profile} =
      BusinessProfile.update(
        user,
        Map.merge(%{"enabled" => true, "role" => "", "expertise" => [], "responsibilities" => []}, attrs)
      )

    profile
  end

  defp drain(id) do
    Enum.reduce_while(1..10, nil, fn _, _ ->
      assert {:ok, _} = Executor.advance(id)
      run = Repo.get!(Run, id)
      if run.status in ~w(succeeded failed cancelled), do: {:halt, run}, else: {:cont, run}
    end)
  end
end
