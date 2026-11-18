defmodule Tuist.HallsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Halls
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)

    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    [ana, ben, cai] = for _ <- 1..3, do: AccountsFixtures.user_fixture(preload: [:account])
    :ok = Accounts.add_user_to_organization(ana, organization, role: :admin)
    # Halls are for every member, not only the admins that threads require.
    :ok = Accounts.add_user_to_organization(ben, organization, role: :user)
    :ok = Accounts.add_user_to_organization(cai, organization, role: :user)

    %{account: account, ana: ana, ben: ben, cai: cai}
  end

  test "every member reads and writes a hall, and each keeps their own unread count", %{
    account: account,
    ana: ana,
    ben: ben
  } do
    assert {:ok, hall} =
             Halls.create(ana, account, %{"request_id" => uuid(), "name" => "# Release Talk", "topic" => " Ship it "})

    assert %{kind: :hall, name: "release-talk", topic: "Ship it", unread: 0} = hall

    {:ok, _} = Halls.message(ana, account, hall.id, message("Canary is out"))
    {:ok, _} = Halls.message(ana, account, hall.id, message("Please try it"))
    assert {:ok, after_ben} = Halls.message(ben, account, hall.id, message("On it"))

    assert [%{author: %{handle: a}, mine: false}, _, %{body: "On it", mine: true}] = after_ben.messages
    assert a == ana.account.name

    # Ana wrote the first two, so only Ben's reply is unread for her; Ben has
    # read everything up to his own reply.
    assert {:ok, %{halls: [%{unread: 1, last_message: %{body: "On it"}}]}} = Halls.list(ana, account)
    assert {:ok, %{halls: [%{unread: 0}]}} = Halls.list(ben, account)

    assert {:ok, %{read_position: 3}} = Halls.read(ana, account, hall.id, 3)
    assert {:ok, %{read_position: 3}} = Halls.read(ana, account, hall.id, 1)
    assert {:ok, %{read_position: 3}} = Halls.read(ana, account, hall.id, 99)
    assert {:ok, %{halls: [%{unread: 0}]}} = Halls.list(ana, account)
  end

  test "hall names are unique per organization and creation replays safely", %{account: account, ana: ana, ben: ben} do
    request = %{"request_id" => uuid(), "name" => "general"}
    assert {:ok, hall} = Halls.create(ana, account, request)
    assert {:ok, %{id: id}} = Halls.create(ana, account, request)
    assert id == hall.id
    assert {:error, :request_conflict} = Halls.create(ana, account, %{request | "name" => "random"})
    assert {:error, :name_taken} = Halls.create(ben, account, %{"request_id" => uuid(), "name" => "General"})
    assert {:error, :invalid_arguments} = Halls.create(ana, account, %{"request_id" => uuid(), "name" => "no/slashes"})
  end

  test "messages replay under their request ID and conflict when the text differs", %{account: account, ana: ana} do
    {:ok, hall} = Halls.create(ana, account, %{"request_id" => uuid(), "name" => "general"})
    attrs = message("Hello")
    {:ok, _} = Halls.message(ana, account, hall.id, attrs)
    assert {:ok, %{messages: [_]}} = Halls.message(ana, account, hall.id, attrs)
    assert {:error, :request_conflict} = Halls.message(ana, account, hall.id, %{attrs | "content" => "Hi"})
  end

  test "a direct conversation is the same one for the same people and private to them", %{
    account: account,
    ana: ana,
    ben: ben,
    cai: cai
  } do
    assert {:ok, direct} = Halls.direct(ana, account, %{"request_id" => uuid(), "user_ids" => [ben.id]})
    assert %{kind: :direct, members: [%{id: ben_id}]} = direct
    assert ben_id == ben.id
    assert {:ok, %{id: same}} = Halls.direct(ben, account, %{"request_id" => uuid(), "user_ids" => [ana.id, ben.id]})
    assert same == direct.id

    {:ok, _} = Halls.message(ana, account, direct.id, message("Lunch?"))
    assert {:ok, %{directs: [%{id: ^same, unread: 1}]}} = Halls.list(ben, account)
    assert {:ok, %{directs: []}} = Halls.list(cai, account)
    assert {:error, :not_found} = Halls.get(cai, account, direct.id)
    assert {:error, :not_found} = Halls.message(cai, account, direct.id, message("Me too"))
    assert {:error, :not_found} = Halls.read(cai, account, direct.id, 1)
  end

  test "direct conversations only include two to eight members of the organization", %{account: account, ana: ana} do
    outsider = AccountsFixtures.user_fixture()
    request = fn ids -> Halls.direct(ana, account, %{"request_id" => uuid(), "user_ids" => ids}) end
    assert {:error, :invalid_arguments} = request.([outsider.id])
    assert {:error, :invalid_arguments} = request.([ana.id])
    assert {:error, :invalid_arguments} = request.(Enum.to_list(1..8))
    assert {:error, :invalid_arguments} = request.(["1"])
  end

  test "halls need membership, both luft flags and an organization", %{account: account, ana: ana} do
    {:ok, hall} = Halls.create(ana, account, %{"request_id" => uuid(), "name" => "general"})
    stranger = AccountsFixtures.user_fixture()
    assert {:error, :forbidden} = Halls.get(stranger, account, hall.id)
    assert {:error, :forbidden} = Halls.list(ana, ana.account)

    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> false end)
    assert {:error, :forbidden} = Halls.list(ana, account)
  end

  test "request IDs never collide across halls, directs and authors", %{account: account, ana: ana, ben: ben} do
    request_id = uuid()
    {:ok, hall} = Halls.create(ana, account, %{"request_id" => request_id, "name" => "general"})
    # A direct conversation reusing a hall's request ID still starts.
    assert {:ok, %{kind: :direct}} = Halls.direct(ben, account, %{"request_id" => request_id, "user_ids" => [ana.id]})

    # Ben replaying Ana's message request is a conflict, not a silent success.
    attrs = message("Hello")
    {:ok, _} = Halls.message(ana, account, hall.id, attrs)
    assert {:error, :request_conflict} = Halls.message(ben, account, hall.id, attrs)
  end

  test "the people list leaves out members who can't be messaged", %{account: account, ana: ana, ben: ben, cai: cai} do
    Repo.update_all(from(u in Tuist.Accounts.User, where: u.id == ^cai.id), set: [active: false])
    assert {:ok, people} = Halls.people(ana, account)
    ids = Enum.map(people, & &1.id)
    assert ben.id in ids
    refute cai.id in ids
  end

  test "inviting people makes them members of a hall, from its creation or later", %{
    account: account,
    ana: ana,
    ben: ben,
    cai: cai
  } do
    assert {:ok, hall} =
             Halls.create(ana, account, %{"request_id" => uuid(), "name" => "design", "user_ids" => [ben.id]})

    assert hall.member_ids == [ben.id]
    assert {:ok, %{member_ids: members}} = Halls.invite(ben, account, hall.id, %{"user_ids" => [cai.id, ben.id]})
    assert members == Enum.sort([ben.id, cai.id])
    # Opening a hall joins it too, and inviting someone again changes nothing.
    {:ok, _} = Halls.read(cai, account, hall.id, 1)
    assert {:ok, %{member_ids: ^members}} = Halls.invite(ana, account, hall.id, %{"user_ids" => [cai.id]})

    outsider = AccountsFixtures.user_fixture()
    assert {:error, :invalid_arguments} = Halls.invite(ana, account, hall.id, %{"user_ids" => [outsider.id]})
    assert {:error, :invalid_arguments} = Halls.invite(ana, account, hall.id, %{"user_ids" => []})

    assert {:error, :invalid_arguments} =
             Halls.create(ana, account, %{"request_id" => uuid(), "name" => "other", "user_ids" => [outsider.id]})

    # A direct conversation keeps the people it started with.
    {:ok, direct} = Halls.direct(ana, account, %{"request_id" => uuid(), "user_ids" => [ben.id]})
    assert {:error, :invalid_arguments} = Halls.invite(ana, account, direct.id, %{"user_ids" => [cai.id]})
  end

  defp uuid, do: Ecto.UUID.generate()
  defp message(content), do: %{"request_id" => uuid(), "content" => content}
end
