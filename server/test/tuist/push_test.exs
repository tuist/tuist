defmodule Tuist.PushTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.Installation
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    %{client: Clients.public!()}
  end

  defp sign_in(user, client, previous \\ nil) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    grant =
      Repo.insert!(%Token{
        type: "access_token",
        value: bearer,
        previous_token: previous && previous.value,
        refresh_token: Ecto.UUID.generate(),
        client_id: client.id,
        sub: to_string(user.id),
        scope: ""
      })

    {:ok, session} = Push.oauth_session(bearer, user)
    {grant, session}
  end

  defp ios(token \\ apns_token()), do: %{platform: "ios", token: token, environment: "production"}
  defp apns_token, do: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
  defp installation_id, do: Ecto.UUID.generate()
  defp ids(installations), do: installations |> Enum.map(& &1.installation_id) |> Enum.sort()

  test "associates installations with the user who registered them", %{client: client} do
    user = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)
    id = installation_id()
    token = String.upcase(apns_token())

    assert {:ok, %Installation{id: registration_id} = installation} = Push.register(user, session, id, ios(token))
    assert installation.user_id == user.id
    assert Repo.reload!(installation).token == String.downcase(token)

    # Refreshing keeps the same registration.
    assert {:ok, %Installation{id: ^registration_id}} = Push.register(user, session, id, ios(token))
    assert ids(Push.live_installations(user.id)) == [id]
  end

  test "rejects devices that do not match their platform", %{client: client} do
    user = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)

    assert {:error, :invalid} = Push.register(user, session, installation_id(), ios("not-hex"))

    assert {:error, :invalid} =
             Push.register(user, session, installation_id(), %{
               platform: "android",
               token: String.duplicate("a", 32),
               environment: "sandbox"
             })

    assert {:error, :invalid} = Push.register(user, session, String.upcase(installation_id()), ios())
  end

  test "ownership never moves to another user", %{client: client} do
    owner = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {_grant, owner_session} = sign_in(owner, client)
    {_grant, other_session} = sign_in(other, client)
    id = installation_id()
    token = apns_token()
    {:ok, _installation} = Push.register(owner, owner_session, id, ios(token))

    # A different device token does not prove it is the same installation.
    assert {:error, :conflict} = Push.register(other, other_session, id, ios())
    assert ids(Push.live_installations(owner.id)) == [id]

    # The same device token does: the owner's row is retired and the app rotates.
    assert {:error, :retired} = Push.register(other, other_session, id, ios(token))
    assert Push.live_installations(owner.id) == []
    assert {:error, :retired} = Push.register(owner, owner_session, id, ios(token))

    rotated = installation_id()
    assert {:ok, _installation} = Push.register(other, other_session, rotated, ios(token))
    assert ids(Push.live_installations(other.id)) == [rotated]
  end

  test "the same device token under a new installation supersedes the old one", %{client: client} do
    user = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)
    token = apns_token()
    {:ok, _installation} = Push.register(user, session, installation_id(), ios(token))

    reinstalled = installation_id()
    assert {:ok, _installation} = Push.register(user, session, reinstalled, ios(token))
    assert ids(Push.live_installations(user.id)) == [reinstalled]
  end

  test "unregistered installation IDs can never be registered again", %{client: client} do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)
    {_grant, _other_session} = sign_in(other, client)
    id = installation_id()
    {:ok, _installation} = Push.register(user, session, id, ios())

    # Another user's unregister is a silent no-op.
    assert :ok = Push.unregister(other, id)
    assert ids(Push.live_installations(user.id)) == [id]

    assert :ok = Push.unregister(user, id)
    assert Push.live_installations(user.id) == []
    assert {:error, :retired} = Push.register(user, session, id, ios())

    # A delete that arrives before its registration still wins.
    late = installation_id()
    assert :ok = Push.unregister(user, late)
    assert {:error, :retired} = Push.register(user, session, late, ios())
  end

  test "installations follow the sign-in they were registered under", %{client: client} do
    user = AccountsFixtures.user_fixture()
    {grant, session} = sign_in(user, client)
    id = installation_id()
    {:ok, _installation} = Push.register(user, session, id, ios())

    # Refresh rotation keeps the registration deliverable.
    {rotated, _session} = sign_in(user, client, grant)
    grant |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now()) |> Repo.update!()
    assert ids(Push.live_installations(user.id)) == [id]

    # Signing out (revoking the current refresh token) ends it.
    rotated |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now()) |> Repo.update!()
    assert Push.live_installations(user.id) == []

    assert %Installation{retired_reason: "session_ended", user_id: nil, token: nil} =
             Repo.get_by!(Installation, installation_id: id)
  end

  test "only OAuth sessions can register" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, bearer, _claims} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access")

    assert {:error, :oauth_session_required} = Push.oauth_session(bearer, user)
  end

  test "keeps at most ten live installations per user", %{client: client} do
    user = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)
    [oldest | newest] = for _ <- 1..11, do: installation_id()

    {:ok, oldest_installation} = Push.register(user, session, oldest, ios())

    oldest_installation
    |> Ecto.Changeset.change(
      last_registered_at: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    for id <- newest, do: {:ok, _installation} = Push.register(user, session, id, ios())

    assert ids(Push.live_installations(user.id)) == Enum.sort(newest)
    assert %Installation{retired_reason: "evicted"} = Repo.get_by!(Installation, installation_id: oldest)
  end

  test "prune retires stale installations and deletes old tombstones", %{client: client} do
    user = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)
    stale = installation_id()
    fresh = installation_id()
    {:ok, stale_installation} = Push.register(user, session, stale, ios())
    {:ok, _installation} = Push.register(user, session, fresh, ios())
    :ok = Push.unregister(user, installation_id())
    old_tombstone = installation_id()
    :ok = Push.unregister(user, old_tombstone)
    removed = installation_id()
    {:ok, removed_installation} = Push.register(user, session, removed, ios())
    :ok = Push.remove_device(user, removed_installation.id)

    days_ago = fn days -> DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second) end
    stale_installation |> Ecto.Changeset.change(last_registered_at: days_ago.(61)) |> Repo.update!()

    for id <- [old_tombstone, removed] do
      Installation
      |> Repo.get_by!(installation_id: id)
      |> Ecto.Changeset.change(retired_at: days_ago.(181))
      |> Repo.update!()
    end

    assert %{retired: 1, deleted: 1} = Push.prune()
    assert ids(Push.live_installations(user.id)) == [fresh]
    assert Repo.get_by(Installation, installation_id: old_tombstone) == nil
    # A removed device stays removed however long its app is away.
    assert {:error, :removed} = Push.register(user, session, removed, ios())
  end

  test "stores the device name as a single bounded line", %{client: client} do
    user = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)
    name = "  iPhone\n17\u200BPro " <> String.duplicate("x", 100)

    {:ok, installation} = Push.register(user, session, installation_id(), Map.put(ios(), :name, name))

    assert installation.device_name == String.slice("iPhone 17 Pro " <> String.duplicate("x", 100), 0, 64)
    assert {:error, :invalid} = Push.register(user, session, installation_id(), Map.put(ios(), :name, <<0xFF>>))
  end

  test "a device removed from the device list stays off until the app turns it back on", %{client: client} do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {_grant, session} = sign_in(user, client)
    id = installation_id()
    token = apns_token()
    {:ok, installation} = Push.register(user, session, id, ios(token))

    # Other users cannot remove it.
    assert :ok = Push.remove_device(other, installation.id)
    assert ids(Push.live_installations(user.id)) == [id]

    assert :ok = Push.remove_device(user, installation.id)
    assert Push.live_installations(user.id) == []

    # Refreshing the removed installation reports `:removed` rather than `:retired`,
    # so the app does not silently rotate and come back.
    assert {:error, :removed} = Push.register(user, session, id, ios(token))

    turned_back_on = installation_id()
    assert {:ok, _installation} = Push.register(user, session, turned_back_on, ios(token))
    assert ids(Push.live_installations(user.id)) == [turned_back_on]
  end
end
