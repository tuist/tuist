defmodule Atlas.OrbitTest do
  # Profiles bound to the threads role are a singleton across the table.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use Atlas.DataCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.OrbitFixtures

  alias Atlas.Authorization.UserRole
  alias Atlas.Orbit
  alias Atlas.Orbit.Access
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Workers.RunThread
  alias Atlas.Repo

  test "Pip is the fixed mascot and assistant identity" do
    assert Orbit.agent_name() == "Pip"
    assert Atlas.Orbit.Agent.system_prompt() =~ "You are Pip,"
  end

  describe "private threads" do
    test "legacy first use creates once and subsequent calls reuse the latest conversation" do
      user = user_fixture()

      assert {:ok, thread, :created} = Orbit.ensure_private(user)
      assert {:ok, same, :existing} = Orbit.ensure_private(user)
      assert same.id == thread.id
      assert thread.kind == "private"
      assert Enum.map(thread.participants, & &1.user_id) == [user.id]
      assert Repo.aggregate(from(c in Thread, where: c.owner_id == ^user.id), :count) == 1
    end

    test "new conversations have independent histories and owner-scoped replay identities" do
      user = user_fixture()
      other = user_fixture(Atlas.Authorization.executive_scopes())
      request_id = Ecto.UUID.generate()
      assert {:ok, first, :created} = Orbit.create_private(user, %{"request_id" => request_id})
      assert {:ok, replay, :existing} = Orbit.create_private(user, %{"request_id" => request_id})
      assert replay.id == first.id
      assert {:ok, second, :created} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
      assert first.id != second.id
      assert first.title == "New conversation"
      assert Enum.map(second.participants, & &1.user_id) == [user.id]

      assert {:ok, own, :created} = Orbit.create_private(other, %{"request_id" => request_id})
      assert own.id != first.id
      assert {:error, :not_found} = Orbit.fetch(other, first.id)
      assert {:error, :not_found} = Orbit.fetch(other, second.id)
      assert {:error, :forbidden} = Orbit.add_participant(user, second, other.id)

      attrs = message_attrs("First\n  question")
      assert {:ok, _, :created} = Orbit.post_message(user, first, attrs)
      assert {:ok, _, :existing} = Orbit.post_message(user, first, attrs)
      assert {:ok, _, :created} = Orbit.post_message(user, first, message_attrs("Follow-up"))
      assert {:ok, _, :created} = Orbit.post_message(user, second, message_attrs("Separate question"))
      assert {:ok, first} = Orbit.fetch(user, first.id)
      assert {:ok, second} = Orbit.fetch(user, second.id)
      assert first.title == "First question"
      assert second.title == "Separate question"

      assert first |> Orbit.list_messages() |> elem(0) |> Enum.filter(&(&1.kind == "human")) |> Enum.map(& &1.body) ==
               ["First\n  question", "Follow-up"]

      assert second |> Orbit.list_messages() |> elem(0) |> Enum.filter(&(&1.kind == "human")) |> Enum.map(& &1.body) ==
               ["Separate question"]

      assert {:ok, latest, :existing} = Orbit.ensure_private(user)
      assert latest.id == second.id
      assert {:ok, replay, :existing} = Orbit.create_private(user, %{"request_id" => request_id})
      assert replay.id == first.id
    end

    test "private creation requires a UUID and first prompt titles are codepoint bounded" do
      user = user_fixture()

      for value <- [nil, "bad", [], %{}] do
        assert {:error, {:invalid_field, :request_id}} = Orbit.create_private(user, %{"request_id" => value})
      end

      {:ok, thread, :created} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
      body = "a" <> String.duplicate("\u0301", 300)
      assert {:ok, _, :created} = Orbit.post_message(user, thread, message_attrs(body))
      assert {:ok, fetched} = Orbit.fetch(user, thread.id)
      assert length(String.codepoints(fetched.title)) == 200
    end

    test "nobody else can read a private thread, including administrators" do
      owner = user_fixture()
      admin = user_fixture(Atlas.Authorization.executive_scopes())
      {:ok, thread, :created} = Orbit.ensure_private(owner)

      assert {:error, :not_found} = Orbit.fetch(admin, thread.id)
      assert {[], _meta} = Orbit.list_for_user(admin)
    end
  end

  describe "shared threads" do
    test "the creator owns it and listed people participate" do
      owner = user_fixture()
      member = user_fixture()

      assert {:ok, thread} =
               Orbit.create_shared(owner, %{
                 "title" => "  Launch plan  ",
                 "participant_ids" => [member.id, owner.id]
               })

      assert thread.title == "Launch plan"
      assert thread.owner_id == owner.id
      assert thread.participants |> Enum.map(& &1.user_id) |> Enum.sort() == Enum.sort([owner.id, member.id])
      assert {:ok, _} = Orbit.fetch(member, thread.id)
    end

    test "rejects malformed or unknown participants and blank titles" do
      owner = user_fixture()

      assert {:error, {:invalid_field, :participant_ids}} =
               Orbit.create_shared(owner, %{"title" => "x", "participant_ids" => ["../admin"]})

      assert {:error, {:invalid_field, :participant_ids}} =
               Orbit.create_shared(owner, %{"title" => "x", "participant_ids" => [Ecto.UUID.generate()]})

      assert {:error, %Ecto.Changeset{}} = Orbit.create_shared(owner, %{"title" => "   "})
    end

    test "the sensitivity ratchet hides history from participants who lack its scopes" do
      owner = user_fixture(["finance:read"])
      member = user_fixture(["finance:read"])
      {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Runway", "participant_ids" => [member.id]})

      Repo.update_all(from(c in Thread, where: c.id == ^thread.id),
        set: [required_scopes: ["finance:read"]]
      )

      assert {:ok, _} = Orbit.fetch(member, thread.id)

      outsider = user_fixture()
      assert {:error, :missing_access} = Orbit.add_participant(owner, thread, outsider.id)

      # Losing the scope later hides the thread as well.
      Repo.delete_all(from role in UserRole, where: role.user_id == ^member.id)
      assert {:error, :not_found} = Orbit.fetch(member, thread.id)
      assert {[], _} = Orbit.list_for_user(member)
      assert Enum.map(Access.audience(Repo.get!(Thread, thread.id)), & &1.id) == [owner.id]
    end

    test "only the owner adds people; members may leave; the owner cannot" do
      owner = user_fixture()
      member = user_fixture()
      other = user_fixture()
      {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})

      assert {:error, :forbidden} = Orbit.add_participant(member, thread, other.id)
      assert {:ok, _} = Orbit.add_participant(owner, thread, other.id)
      assert {:error, :forbidden} = Orbit.remove_participant(member, thread, other.id)
      assert :ok = Orbit.remove_participant(member, thread, member.id)
      assert {:error, :forbidden} = Orbit.remove_participant(owner, thread, owner.id)
      assert {:error, :not_found} = Orbit.fetch(member, thread.id)

      bodies = thread |> Orbit.list_messages() |> elem(0) |> Enum.map(& &1.body)
      assert Enum.any?(bodies, &String.contains?(&1, "added"))
      assert Enum.any?(bodies, &String.contains?(&1, "left"))
    end

    test "adding someone cancels an active run that read data for the previous audience" do
      orbit_profile_fixture()
      owner = user_fixture()
      other = user_fixture()
      {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Team"})
      {:ok, _message, :created} = Orbit.post_message(owner, thread, message_attrs("Summarize"))
      run = Repo.get_by!(Run, thread_id: thread.id)

      assert {:ok, _} = Orbit.add_participant(owner, thread, other.id)
      assert Repo.get!(Run, run.id).cancel_requested_at
    end
  end

  describe "messages" do
    test "client ids make posts idempotent and addressed messages queue one durable run" do
      orbit_profile_fixture()
      user = user_fixture()
      {:ok, thread, _} = Orbit.ensure_private(user)
      attrs = message_attrs("What changed this week?")

      assert {:ok, message, :created} = Orbit.post_message(user, thread, attrs)
      assert {:ok, same, :existing} = Orbit.post_message(user, thread, attrs)
      assert same.id == message.id
      assert message.address_agent

      assert [%Run{status: "queued", initiator_id: initiator, acting_user_id: acting, trigger_seq: trigger} = run] =
               Repo.all(from r in Run, where: r.thread_id == ^thread.id)

      assert initiator == user.id and acting == user.id and trigger == message.position
      assert_enqueued(worker: RunThread, args: %{"run_id" => run.id})

      # A second message while the run is active does not start another run.
      {:ok, _second, :created} = Orbit.post_message(user, thread, message_attrs("And last week?"))
      assert Repo.aggregate(from(r in Run, where: r.thread_id == ^thread.id), :count) == 1
    end

    test "without a threads profile the message is kept and a notice explains why" do
      user = user_fixture()
      {:ok, thread, _} = Orbit.ensure_private(user)

      assert {:ok, _message, :created} = Orbit.post_message(user, thread, message_attrs("Hello"))
      assert Repo.all(from r in Run, where: r.thread_id == ^thread.id) == []

      assert [%Message{kind: "human"}, %Message{kind: "system", body: body}] =
               thread |> Orbit.list_messages() |> elem(0)

      assert body =~ "Connect an AI account"
    end

    test "shared threads can post without addressing the assistant" do
      orbit_profile_fixture()
      owner = user_fixture()
      {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Team"})

      attrs = Map.put(message_attrs("Human-only aside"), "address_agent", false)
      assert {:ok, message, :created} = Orbit.post_message(owner, thread, attrs)
      refute message.address_agent
      assert Repo.all(from r in Run, where: r.thread_id == ^thread.id) == []
    end

    test "validates body and client id" do
      user = user_fixture()
      {:ok, thread, _} = Orbit.ensure_private(user)

      assert {:error, {:invalid_field, :body}} = Orbit.post_message(user, thread, message_attrs("   "))

      assert {:error, {:invalid_field, :body}} =
               Orbit.post_message(user, thread, message_attrs(String.duplicate("x", 16_001)))

      assert {:error, {:invalid_field, :client_id}} =
               Orbit.post_message(user, thread, %{"body" => "Hi", "client_id" => "nope"})
    end

    test "pages newest first while keeping each page chronological" do
      user = user_fixture()
      {:ok, thread, _} = Orbit.ensure_private(user)

      Repo.transaction(fn ->
        locked = Orbit.lock!(thread.id)
        for n <- 1..55, do: Orbit.append!(locked, %{kind: "system", body: "n#{n}"})
      end)

      {first, meta} = Orbit.list_messages(thread, 1)
      assert meta == %{page: 1, total_pages: 2, total_count: 55}
      assert hd(first).body == "n6" and List.last(first).body == "n55"
      {second, _meta} = Orbit.list_messages(thread, 2)
      assert Enum.map(second, & &1.body) == Enum.map(1..5, &"n#{&1}")
    end
  end

  describe "signals" do
    test "open a shared thread acting as the owner and append repeats to it" do
      orbit_profile_fixture()
      owner = user_fixture(["engineering:read"])
      member = user_fixture(["engineering:read"])

      attrs = %{
        owner_id: owner.id,
        participant_ids: [member.id],
        source_type: "alert_rule",
        source_id: "rule-1:issue-1",
        title: "Error rate spike",
        summary: "Errors doubled in the last hour.",
        required_scopes: ["engineering:read"]
      }

      assert {:ok, thread} = Orbit.open_for_signal(attrs)
      assert thread.origin == "signal"
      assert thread.required_scopes == ["engineering:read"]

      assert [%Run{initiator_id: nil, acting_user_id: acting}] =
               Repo.all(from r in Run, where: r.thread_id == ^thread.id)

      assert acting == owner.id

      assert {:ok, same} = Orbit.open_for_signal(%{attrs | summary: "Still elevated."})
      assert same.id == thread.id
      assert thread |> Orbit.list_messages() |> elem(0) |> Enum.count(&(&1.kind == "system")) == 2
    end

    test "refuse participants who could not see the signal" do
      owner = user_fixture(["finance:read"])
      member = user_fixture()

      assert {:error, :missing_access} =
               Orbit.open_for_signal(%{
                 owner_id: owner.id,
                 participant_ids: [member.id],
                 source_type: "finance",
                 source_id: "burn",
                 title: "Burn increased",
                 summary: "Monthly burn rose.",
                 required_scopes: ["finance:read"]
               })

      assert {:error, {:invalid_field, :required_scopes}} =
               Orbit.open_for_signal(%{
                 owner_id: owner.id,
                 source_type: "x",
                 source_id: "y",
                 title: "t",
                 summary: "s",
                 required_scopes: ["made:up"]
               })
    end
  end

  defp message_attrs(body), do: %{"body" => body, "client_id" => Ecto.UUID.generate()}
end
