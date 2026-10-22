defmodule Atlas.ConversationsTest do
  # Profiles bound to the conversations role are a singleton across the table.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use Atlas.DataCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.ConversationsFixtures

  alias Atlas.Authorization.UserRole
  alias Atlas.Conversations
  alias Atlas.Conversations.Access
  alias Atlas.Conversations.Conversation
  alias Atlas.Conversations.Message
  alias Atlas.Conversations.Run
  alias Atlas.Conversations.Workers.RunConversation
  alias Atlas.Repo

  describe "private threads" do
    test "each person gets exactly one, created on first use" do
      user = user_fixture()

      assert {:ok, conversation, :created} = Conversations.ensure_private(user)
      assert {:ok, same, :existing} = Conversations.ensure_private(user)
      assert same.id == conversation.id
      assert conversation.kind == "private"
      assert Enum.map(conversation.participants, & &1.user_id) == [user.id]
      assert Repo.aggregate(from(c in Conversation, where: c.owner_id == ^user.id), :count) == 1
    end

    test "nobody else can read a private thread, including administrators" do
      owner = user_fixture()
      admin = user_fixture(Atlas.Authorization.executive_scopes())
      {:ok, conversation, :created} = Conversations.ensure_private(owner)

      assert {:error, :not_found} = Conversations.fetch(admin, conversation.id)
      assert {[], _meta} = Conversations.list_for_user(admin)
    end
  end

  describe "shared conversations" do
    test "the creator owns it and listed people participate" do
      owner = user_fixture()
      member = user_fixture()

      assert {:ok, conversation} =
               Conversations.create_shared(owner, %{
                 "title" => "  Launch plan  ",
                 "participant_ids" => [member.id, owner.id]
               })

      assert conversation.title == "Launch plan"
      assert conversation.owner_id == owner.id
      assert conversation.participants |> Enum.map(& &1.user_id) |> Enum.sort() == Enum.sort([owner.id, member.id])
      assert {:ok, _} = Conversations.fetch(member, conversation.id)
    end

    test "rejects malformed or unknown participants and blank titles" do
      owner = user_fixture()

      assert {:error, {:invalid_field, :participant_ids}} =
               Conversations.create_shared(owner, %{"title" => "x", "participant_ids" => ["../admin"]})

      assert {:error, {:invalid_field, :participant_ids}} =
               Conversations.create_shared(owner, %{"title" => "x", "participant_ids" => [Ecto.UUID.generate()]})

      assert {:error, %Ecto.Changeset{}} = Conversations.create_shared(owner, %{"title" => "   "})
    end

    test "the sensitivity ratchet hides history from participants who lack its scopes" do
      owner = user_fixture(["finance:read"])
      member = user_fixture(["finance:read"])
      {:ok, conversation} = Conversations.create_shared(owner, %{"title" => "Runway", "participant_ids" => [member.id]})

      Repo.update_all(from(c in Conversation, where: c.id == ^conversation.id),
        set: [required_scopes: ["finance:read"]]
      )

      assert {:ok, _} = Conversations.fetch(member, conversation.id)

      outsider = user_fixture()
      assert {:error, :missing_access} = Conversations.add_participant(owner, conversation, outsider.id)

      # Losing the scope later hides the conversation as well.
      Repo.delete_all(from role in UserRole, where: role.user_id == ^member.id)
      assert {:error, :not_found} = Conversations.fetch(member, conversation.id)
      assert {[], _} = Conversations.list_for_user(member)
      assert Enum.map(Access.audience(Repo.get!(Conversation, conversation.id)), & &1.id) == [owner.id]
    end

    test "only the owner adds people; members may leave; the owner cannot" do
      owner = user_fixture()
      member = user_fixture()
      other = user_fixture()
      {:ok, conversation} = Conversations.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})

      assert {:error, :forbidden} = Conversations.add_participant(member, conversation, other.id)
      assert {:ok, _} = Conversations.add_participant(owner, conversation, other.id)
      assert {:error, :forbidden} = Conversations.remove_participant(member, conversation, other.id)
      assert :ok = Conversations.remove_participant(member, conversation, member.id)
      assert {:error, :forbidden} = Conversations.remove_participant(owner, conversation, owner.id)
      assert {:error, :not_found} = Conversations.fetch(member, conversation.id)

      bodies = conversation |> Conversations.list_messages() |> elem(0) |> Enum.map(& &1.body)
      assert Enum.any?(bodies, &String.contains?(&1, "added"))
      assert Enum.any?(bodies, &String.contains?(&1, "left"))
    end

    test "adding someone cancels an active run that read data for the previous audience" do
      conversations_profile_fixture()
      owner = user_fixture()
      other = user_fixture()
      {:ok, conversation} = Conversations.create_shared(owner, %{"title" => "Team"})
      {:ok, _message, :created} = Conversations.post_message(owner, conversation, message_attrs("Summarize"))
      run = Repo.get_by!(Run, conversation_id: conversation.id)

      assert {:ok, _} = Conversations.add_participant(owner, conversation, other.id)
      assert Repo.get!(Run, run.id).cancel_requested_at
    end
  end

  describe "messages" do
    test "client ids make posts idempotent and addressed messages queue one durable run" do
      conversations_profile_fixture()
      user = user_fixture()
      {:ok, conversation, _} = Conversations.ensure_private(user)
      attrs = message_attrs("What changed this week?")

      assert {:ok, message, :created} = Conversations.post_message(user, conversation, attrs)
      assert {:ok, same, :existing} = Conversations.post_message(user, conversation, attrs)
      assert same.id == message.id
      assert message.address_agent

      assert [%Run{status: "queued", initiator_id: initiator, acting_user_id: acting, trigger_seq: trigger} = run] =
               Repo.all(from r in Run, where: r.conversation_id == ^conversation.id)

      assert initiator == user.id and acting == user.id and trigger == message.position
      assert_enqueued(worker: RunConversation, args: %{"run_id" => run.id})

      # A second message while the run is active does not start another run.
      {:ok, _second, :created} = Conversations.post_message(user, conversation, message_attrs("And last week?"))
      assert Repo.aggregate(from(r in Run, where: r.conversation_id == ^conversation.id), :count) == 1
    end

    test "without a conversations profile the message is kept and a notice explains why" do
      user = user_fixture()
      {:ok, conversation, _} = Conversations.ensure_private(user)

      assert {:ok, _message, :created} = Conversations.post_message(user, conversation, message_attrs("Hello"))
      assert Repo.all(from r in Run, where: r.conversation_id == ^conversation.id) == []

      assert [%Message{kind: "human"}, %Message{kind: "system", body: body}] =
               conversation |> Conversations.list_messages() |> elem(0)

      assert body =~ "not configured"
    end

    test "shared conversations can post without addressing the assistant" do
      conversations_profile_fixture()
      owner = user_fixture()
      {:ok, conversation} = Conversations.create_shared(owner, %{"title" => "Team"})

      attrs = Map.put(message_attrs("Human-only aside"), "address_agent", false)
      assert {:ok, message, :created} = Conversations.post_message(owner, conversation, attrs)
      refute message.address_agent
      assert Repo.all(from r in Run, where: r.conversation_id == ^conversation.id) == []
    end

    test "validates body and client id" do
      user = user_fixture()
      {:ok, conversation, _} = Conversations.ensure_private(user)

      assert {:error, {:invalid_field, :body}} = Conversations.post_message(user, conversation, message_attrs("   "))

      assert {:error, {:invalid_field, :body}} =
               Conversations.post_message(user, conversation, message_attrs(String.duplicate("x", 16_001)))

      assert {:error, {:invalid_field, :client_id}} =
               Conversations.post_message(user, conversation, %{"body" => "Hi", "client_id" => "nope"})
    end

    test "pages newest first while keeping each page chronological" do
      user = user_fixture()
      {:ok, conversation, _} = Conversations.ensure_private(user)

      Repo.transaction(fn ->
        locked = Conversations.lock!(conversation.id)
        for n <- 1..55, do: Conversations.append!(locked, %{kind: "system", body: "n#{n}"})
      end)

      {first, meta} = Conversations.list_messages(conversation, 1)
      assert meta == %{page: 1, total_pages: 2, total_count: 55}
      assert hd(first).body == "n6" and List.last(first).body == "n55"
      {second, _meta} = Conversations.list_messages(conversation, 2)
      assert Enum.map(second, & &1.body) == Enum.map(1..5, &"n#{&1}")
    end
  end

  describe "signals" do
    test "open a shared conversation acting as the owner and append repeats to it" do
      conversations_profile_fixture()
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

      assert {:ok, conversation} = Conversations.open_for_signal(attrs)
      assert conversation.origin == "signal"
      assert conversation.required_scopes == ["engineering:read"]

      assert [%Run{initiator_id: nil, acting_user_id: acting}] =
               Repo.all(from r in Run, where: r.conversation_id == ^conversation.id)

      assert acting == owner.id

      assert {:ok, same} = Conversations.open_for_signal(%{attrs | summary: "Still elevated."})
      assert same.id == conversation.id
      assert conversation |> Conversations.list_messages() |> elem(0) |> Enum.count(&(&1.kind == "system")) == 2
    end

    test "refuse participants who could not see the signal" do
      owner = user_fixture(["finance:read"])
      member = user_fixture()

      assert {:error, :missing_access} =
               Conversations.open_for_signal(%{
                 owner_id: owner.id,
                 participant_ids: [member.id],
                 source_type: "finance",
                 source_id: "burn",
                 title: "Burn increased",
                 summary: "Monthly burn rose.",
                 required_scopes: ["finance:read"]
               })

      assert {:error, {:invalid_field, :required_scopes}} =
               Conversations.open_for_signal(%{
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
