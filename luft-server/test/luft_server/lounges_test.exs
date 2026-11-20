defmodule LuftServer.LoungesTest do
  use LuftServerWeb.ConnCase, async: false

  alias LuftServer.Lounges
  alias LuftServer.Lounges.Lounge
  alias LuftServer.Lounges.Member
  alias LuftServer.Lounges.Message
  alias LuftServer.Lounges.Presence
  alias LuftServer.Repo
  alias LuftServer.Tuist.Scope

  setup_all do
    if !Process.whereis(LuftServer.PubSub),
      do: start_supervised!({Phoenix.PubSub, name: LuftServer.PubSub})

    if !Process.whereis(Presence), do: start_supervised!(Presence)
    :ok
  end

  defp scope(user_id \\ 1, account_id \\ 100) do
    %Scope{
      user_id: user_id,
      account_id: account_id,
      organization_id: 10,
      people: Enum.map(1..4, &%{id: &1, handle: "person-#{&1}", active: &1 != 4}),
      can_create_threads: false
    }
  end

  defp attrs(name \\ "general"), do: %{"name" => name, "request_id" => Ecto.UUID.generate()}
  defp message(body \\ "hello"), do: %{"content" => body, "request_id" => Ecto.UUID.generate()}
  defp direct(ids), do: %{"user_ids" => ids, "request_id" => Ecto.UUID.generate()}

  test "public lounges require an organization, are tenant scoped, and do not require thread creation permission" do
    {:ok, lounge} = Lounges.create(scope(), attrs())
    assert lounge.kind == :lounge
    assert {:ok, %{id: id}} = Lounges.get(scope(2), lounge.id)
    assert id == lounge.id
    assert {:error, :not_found} = Lounges.get(scope(1, 101), lounge.id)
    assert {:error, :not_found} = Lounges.message(scope(1, 101), lounge.id, message())
    assert {:error, :not_found} = Lounges.read(scope(1, 101), lounge.id, 1)
    assert {:ok, %{lounges: [], directs: []}} = Lounges.list(scope(1, 101))
    personal = %{scope() | organization_id: nil}
    assert {:error, :forbidden} = Lounges.create(personal, attrs("personal"))
    assert {:error, :not_found} = Lounges.get(personal, lounge.id)
    assert {:ok, %{lounges: []}} = Lounges.list(personal)
  end

  test "DMs are canonical and private even to another organization member" do
    {:ok, dm} = Lounges.direct(scope(), direct([2]))

    assert {:ok, %{id: id, members: [%{id: 1, handle: "person-1"}]}} =
             Lounges.direct(scope(2), direct([1, 2]))

    assert id == dm.id
    assert {:ok, %{directs: [%{id: ^id}]}} = Lounges.list(scope())
    assert {:ok, %{directs: []}} = Lounges.list(scope(3))
    assert {:error, :not_found} = Lounges.get(scope(3), id)
    assert {:error, :not_found} = Lounges.message(scope(3), id, message("private"))
    assert {:error, :not_found} = Lounges.read(scope(3), id, 1)
    assert {:error, :not_found} = Lounges.invite(scope(3), id, %{"user_ids" => [3]})
    assert {:error, :invalid_arguments} = Lounges.invite(scope(), id, %{"user_ids" => [3]})
    assert {:error, :not_found} = Lounges.get(scope(1, 101), id)
    assert {:error, :invalid_arguments} = Lounges.direct(scope(), direct([4]))
    assert {:error, :invalid_arguments} = Lounges.direct(scope(), direct([999]))
    assert Repo.aggregate(Member, :count) == 2
  end

  test "creation retries are idempotent and conflicting author, topic and name are rejected" do
    attrs = attrs()
    {:ok, first} = Lounges.create(scope(), attrs)
    assert {:ok, %{id: id}} = Lounges.create(scope(), attrs)
    assert id == first.id
    assert {:error, :request_conflict} = Lounges.create(scope(2), attrs)

    assert {:error, :request_conflict} =
             Lounges.create(scope(), Map.put(attrs, "topic", "changed"))

    assert {:error, :request_conflict} = Lounges.create(scope(), Map.put(attrs, "name", "other"))
    assert {:error, :name_taken} = Lounges.create(scope(), attrs("general"))
    assert Repo.aggregate(Lounge, :count) == 1
  end

  test "message retries do not allocate positions or replay another author's write" do
    {:ok, lounge} = Lounges.create(scope(), attrs())
    attrs = message()
    assert {:ok, %{last_position: 1}} = Lounges.message(scope(), lounge.id, attrs)
    assert {:ok, %{last_position: 1}} = Lounges.message(scope(), lounge.id, attrs)
    assert {:error, :request_conflict} = Lounges.message(scope(2), lounge.id, attrs)

    assert {:error, :request_conflict} =
             Lounges.message(scope(), lounge.id, Map.put(attrs, "content", "changed"))

    assert {:ok,
            %{
              last_position: 2,
              messages: [_, %{position: 2, author: %{id: 2, handle: "person-2"}, mine: true}]
            }} =
             Lounges.message(scope(2), lounge.id, message("next"))

    assert Repo.aggregate(Message, :count) == 2
    assert {:ok, %{read_position: 1}} = Lounges.get(scope(), lounge.id)
    assert {:ok, %{read_position: 2}} = Lounges.get(scope(2), lounge.id)
  end

  test "pagination is exclusive and chronological; read positions only advance and are capped" do
    {:ok, lounge} = Lounges.create(scope(), attrs())

    for n <- 1..55,
        do: assert({:ok, _} = Lounges.message(scope(), lounge.id, message("message #{n}")))

    assert {:ok, %{messages: page, has_more: true, next_before: 6}} =
             Lounges.get(scope(2), lounge.id)

    assert Enum.map(page, & &1.position) == Enum.to_list(6..55)

    assert {:ok, %{messages: older, has_more: false, next_before: nil}} =
             Lounges.get(scope(2), lounge.id, before: "6")

    assert Enum.map(older, & &1.position) == Enum.to_list(1..5)
    assert {:ok, %{read_position: 30}} = Lounges.read(scope(2), lounge.id, "30")
    assert {:ok, %{read_position: 30}} = Lounges.read(scope(2), lounge.id, 2)
    assert {:ok, %{read_position: 55}} = Lounges.read(scope(2), lounge.id, 1000)

    assert {:ok, %{read_position: 55}} =
             scope()
             |> Lounges.invite(lounge.id, %{"user_ids" => [2]})
             |> then(fn {:ok, _} -> Lounges.get(scope(2), lounge.id) end)

    for invalid <- [nil, 0, -1, "oops", "1x"] do
      assert {:error, :invalid_arguments} = Lounges.read(scope(2), lounge.id, invalid)
    end

    assert {:error, :invalid_arguments} = Lounges.get(scope(), lounge.id, before: "oops")
  end

  test "invites validate active upstream people and never reset read positions" do
    {:ok, lounge} = Lounges.create(scope(), Map.put(attrs(), "user_ids", [2]))
    assert lounge.member_ids == [2]
    assert {:error, :invalid_arguments} = Lounges.invite(scope(), lounge.id, %{"user_ids" => [4]})

    assert {:error, :invalid_arguments} =
             Lounges.invite(scope(), lounge.id, %{"user_ids" => [500]})

    assert {:ok, people} = Lounges.people(scope())
    assert Enum.map(people, & &1.id) == [2, 3]
    # Removed identities are not fetched from a local identity mirror.
    {:ok, _} = Lounges.message(scope(), lounge.id, message())

    assert {:ok, %{messages: [%{author: %{id: 1, handle: nil}}]}} =
             Lounges.get(%{scope(2) | people: []}, lounge.id)
  end
end
