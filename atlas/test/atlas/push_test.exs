defmodule Atlas.PushTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Atlas.PushFixtures
  import Atlas.TimeOffFixtures, only: [user_fixture: 0]

  alias Atlas.Audit.Activity
  alias Atlas.OAuth.Clients
  alias Atlas.Push
  alias Atlas.Push.Config
  alias Atlas.Push.Installation
  alias Atlas.Push.Workers.Deliver
  alias Boruta.Ecto.Token

  setup do
    stub(Config, :capabilities, fn -> %{"ios" => true, "android" => true} end)
    stub(Config, :available?, fn platform, _environment -> platform in ["ios", "android"] end)
    user = user_fixture()
    %{user: user, client_id: native_client_id(user), installation_id: Ecto.UUID.generate()}
  end

  describe "register/4" do
    test "creates a live registration and refreshes it in place", %{user: user, client_id: client_id} = context do
      token = String.upcase(ios_token())
      device = ios_device(%{"token" => token, "environment" => "sandbox"})

      assert {:ok, installation} = Push.register(user, client_id, context.installation_id, device)
      assert installation.token == String.downcase(token)
      assert installation.environment == "sandbox"
      assert installation.user_id == user.id

      assert {:ok, refreshed} = Push.register(user, client_id, context.installation_id, device)
      assert refreshed.id == installation.id
      assert refreshed.token_updated_at == installation.token_updated_at

      rotated = ios_token()

      assert {:ok, rotated_installation} =
               Push.register(user, client_id, context.installation_id, ios_device(%{"token" => rotated}))

      assert rotated_installation.id == installation.id
      assert rotated_installation.token == rotated
      assert DateTime.compare(rotated_installation.token_updated_at, installation.token_updated_at) in [:gt, :eq]
    end

    test "stores only the encrypted token", %{user: user, client_id: client_id} = context do
      token = ios_token()
      assert {:ok, _} = Push.register(user, client_id, context.installation_id, ios_device(%{"token" => token}))

      %{rows: [[stored, hash]]} = Repo.query!("SELECT token, token_hash FROM push_installations")
      refute stored =~ token
      refute stored =~ Base.decode16!(token, case: :lower)
      assert hash == Installation.token_hash("ios", token)
    end

    test "rejects malformed devices and installation IDs", %{user: user, client_id: client_id} = context do
      invalid = [
        ios_device(%{"token" => "abc"}),
        ios_device(%{"token" => String.duplicate("zz", 32)}),
        ios_device(%{"token" => ios_token() <> "a"}),
        ios_device(%{"environment" => "development"}),
        android_device(%{"environment" => "sandbox"}),
        android_device(%{"token" => "has space token value"}),
        Map.delete(ios_device(), "environment"),
        Map.put(ios_device(), "user_id", user.id),
        ios_device(%{"platform" => "web"}),
        ios_device(%{"token" => 123})
      ]

      for device <- invalid do
        assert {:error, :invalid} = Push.register(user, client_id, context.installation_id, device)
      end

      for id <- ["not-a-uuid", String.upcase(Ecto.UUID.generate()), nil] do
        assert {:error, :invalid} = Push.register(user, client_id, id, ios_device())
      end

      assert Repo.aggregate(Installation, :count) == 0
    end

    test "returns unavailable when the platform's provider is not configured", %{user: user} = context do
      stub(Config, :available?, fn platform, _environment -> platform == "ios" end)

      assert {:error, :unavailable} = Push.register(user, context.client_id, context.installation_id, android_device())
      assert {:ok, _} = Push.register(user, context.client_id, context.installation_id, ios_device())
    end

    test "rejects sandbox registrations when only production credentials are configured", context do
      stub(Config, :available?, fn platform, environment -> platform == "ios" and environment == "production" end)

      assert {:error, :unavailable} =
               Push.register(
                 context.user,
                 context.client_id,
                 context.installation_id,
                 ios_device(%{"environment" => "sandbox"})
               )

      assert Repo.aggregate(Installation, :count) == 0
      assert {:ok, _} = Push.register(context.user, context.client_id, context.installation_id, ios_device())
    end

    test "a registration arriving after its deletion cannot resurrect it",
         %{user: user, client_id: client_id} = context do
      device = ios_device()
      assert {:ok, _} = Push.register(user, client_id, context.installation_id, device)
      assert :ok = Push.unregister(user, client_id, context.installation_id)

      assert {:error, :retired} = Push.register(user, client_id, context.installation_id, device)

      tombstone = Repo.get_by!(Installation, installation_id: context.installation_id)
      assert %{retired_reason: "unregistered", user_id: nil, token: nil, token_hash: nil} = tombstone

      # The client rotates its installation ID and registers again.
      assert {:ok, %Installation{}} = Push.register(user, client_id, Ecto.UUID.generate(), device)
    end

    test "deleting an unknown installation leaves a tombstone for a late first registration", context do
      assert :ok = Push.unregister(context.user, context.client_id, context.installation_id)
      assert {:error, :retired} = Push.register(context.user, context.client_id, context.installation_id, ios_device())
    end

    test "never moves an installation to another user", %{user: user, client_id: client_id} = context do
      device = ios_device()
      assert {:ok, original} = Push.register(user, client_id, context.installation_id, device)
      other = user_fixture()

      # A different OAuth client with a different token cannot claim or retire it.
      assert {:error, :conflict} =
               Push.register(other, Ecto.UUID.generate(), context.installation_id, ios_device())

      assert Repo.reload!(original).retired_at == nil

      # The same app installation (same OAuth client) retires the previous owner's
      # row, so its queued deliveries die, and must rotate before registering.
      assert {:error, :retired} = Push.register(other, client_id, context.installation_id, device)
      assert %{retired_reason: "owner_changed", user_id: nil} = Repo.reload!(original)
      assert Push.deliverable(original.id, user.id) == nil

      assert {:ok, new_installation} = Push.register(other, client_id, Ecto.UUID.generate(), device)
      assert new_installation.user_id == other.id
    end

    test "possessing the device token also proves the installation", %{user: user} = context do
      device = ios_device()
      assert {:ok, original} = Push.register(user, context.client_id, context.installation_id, device)

      assert {:error, :retired} =
               Push.register(user_fixture(), Ecto.UUID.generate(), context.installation_id, device)

      assert Repo.reload!(original).retired_reason == "owner_changed"
    end

    test "a device token belongs to only one live installation across accounts", %{user: user} = context do
      device = ios_device()
      assert {:ok, first} = Push.register(user, context.client_id, context.installation_id, device)

      other = user_fixture()
      assert {:ok, second} = Push.register(other, Ecto.UUID.generate(), Ecto.UUID.generate(), device)

      assert %{retired_reason: "superseded", user_id: nil} = Repo.reload!(first)
      assert second.user_id == other.id
    end

    test "an installation cannot change platform", %{user: user} = context do
      assert {:ok, _} = Push.register(user, context.client_id, context.installation_id, ios_device())
      assert {:error, :conflict} = Push.register(user, context.client_id, context.installation_id, android_device())
    end

    test "keeps at most ten live registrations per user, evicting the oldest", %{user: user, client_id: client_id} do
      ids =
        for _ <- 1..11 do
          {:ok, installation} = Push.register(user, client_id, Ecto.UUID.generate(), ios_device())
          installation.id
        end

      live = Installation |> where([i], is_nil(i.retired_at)) |> select([i], i.id) |> Repo.all()
      assert length(live) == 10
      assert %{retired_reason: "evicted"} = Repo.get!(Installation, hd(ids))
    end
  end

  describe "unregister/3" do
    test "only the owner or the same app installation can delete", %{user: user, client_id: client_id} = context do
      assert {:ok, installation} = Push.register(user, client_id, context.installation_id, ios_device())
      other = user_fixture()

      assert :ok = Push.unregister(other, Ecto.UUID.generate(), context.installation_id)
      assert Repo.reload!(installation).retired_at == nil

      # Next signed-in user cleaning up after an offline sign-out on the same app.
      assert :ok = Push.unregister(other, client_id, context.installation_id)
      assert %{retired_reason: "unregistered"} = Repo.reload!(installation)

      assert :ok = Push.unregister(user, client_id, context.installation_id)
      assert {:error, :invalid} = Push.unregister(user, client_id, "bad")
    end
  end

  describe "notify_user/3" do
    test "the generic activity kind is available to product code with a day-long lifetime", %{user: user} = context do
      {:ok, _} = Push.register(user, context.client_id, context.installation_id, android_device())
      task_id = Ecto.UUID.generate()

      assert {:ok, 1} = Push.notify_user(user.id, "activity", {"tasks", task_id})
      assert [%Oban.Job{args: %{"kind" => "activity", "expires_at" => expires_at}}] = all_enqueued(worker: Deliver)
      {:ok, expires_at, _} = DateTime.from_iso8601(expires_at)
      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 86_400, 60
    end

    test "queues one ID-only job per live registration on configured platforms", %{user: user} = context do
      ios_token = ios_token()
      {:ok, ios} = Push.register(user, context.client_id, context.installation_id, ios_device(%{"token" => ios_token}))
      {:ok, android} = Push.register(user, context.client_id, Ecto.UUID.generate(), android_device())
      {:ok, retired} = Push.register(user, context.client_id, Ecto.UUID.generate(), ios_device())
      :ok = Push.unregister(user, context.client_id, retired.installation_id)
      {:ok, _} = Push.register(user_fixture(), Ecto.UUID.generate(), Ecto.UUID.generate(), ios_device())
      stub(Config, :capabilities, fn -> %{"ios" => true, "android" => false} end)

      task_id = Ecto.UUID.generate()
      assert {:ok, 1} = Push.notify_user(user.id, "self_test", {"tasks", task_id})

      assert [%Oban.Job{args: args}] = all_enqueued(worker: Deliver)
      assert args["registration_id"] == ios.id
      assert args["user_id"] == user.id
      assert args["screen"] == "tasks" and args["record_id"] == task_id
      assert {:ok, _, _} = DateTime.from_iso8601(args["expires_at"])
      refute inspect(args) =~ ios_token
      refute args["registration_id"] == android.id
    end

    test "accepts only fixed kinds and allowlisted destinations", %{user: user} do
      for {kind, destination} <- [
            {"arbitrary", {"profile", nil}},
            {"self_test", {"settings", nil}},
            {"self_test", {"profile", Ecto.UUID.generate()}},
            {"self_test", {"tasks", "not-a-uuid"}},
            {"self_test", "profile"}
          ] do
        assert {:error, :invalid_notification} = Push.notify_user(user.id, kind, destination)
      end
    end
  end

  describe "retire_invalidated/2" do
    test "compares the rejected token and environment before retiring", %{user: user, client_id: client_id} = context do
      token = ios_token()

      {:ok, sandbox} =
        Push.register(
          user,
          client_id,
          context.installation_id,
          ios_device(%{"token" => token, "environment" => "sandbox"})
        )

      # The same token moved to production while a sandbox send was in flight.
      {:ok, production} =
        Push.register(
          user,
          client_id,
          context.installation_id,
          ios_device(%{"token" => token, "environment" => "production"})
        )

      assert :kept = Push.retire_invalidated(sandbox)
      assert Repo.reload!(production).retired_at == nil

      {:ok, rotated} = Push.register(user, client_id, context.installation_id, ios_device())
      assert :kept = Push.retire_invalidated(production)
      assert Repo.reload!(rotated).retired_at == nil
      assert :retired = Push.retire_invalidated(rotated)
      assert %{retired_reason: "provider_invalidated"} = Repo.reload!(rotated)
    end

    test "APNs 410 keeps registrations refreshed after Apple's timestamp, even with the same token", context do
      device = ios_device()
      {:ok, installation} = Push.register(context.user, context.client_id, context.installation_id, device)
      apple_saw_invalid_at = DateTime.add(installation.last_registered_at, -1)

      assert :kept = Push.retire_invalidated(installation, unregistered_at: apple_saw_invalid_at)
      assert Repo.reload!(installation).retired_at == nil

      assert :retired = Push.retire_invalidated(installation, unregistered_at: DateTime.add(DateTime.utc_now(), 60))
    end
  end

  describe "session binding" do
    test "normal refresh rotations keep the registration deliverable", %{user: user, client_id: client_id} = context do
      {:ok, installation} = Push.register(user, client_id, context.installation_id, ios_device())

      for _rotation <- 1..2, do: rotate_refresh_grant(client_id, user)

      active =
        Repo.aggregate(
          from(t in Token, where: t.client_id == ^client_id and is_nil(t.refresh_token_revoked_at)),
          :count
        )

      assert active == 1
      assert %Installation{id: id} = Push.deliverable(installation.id, user.id)
      assert id == installation.id
      assert {:ok, 1} = Push.notify_user(user.id, "activity", {"tasks", Ecto.UUID.generate()})
    end

    test "a revoked refresh grant stops delivery and retires the registration",
         %{user: user, client_id: client_id} = ctx do
      {:ok, installation} = Push.register(user, client_id, ctx.installation_id, ios_device())

      Repo.update_all(from(t in Token, where: t.client_id == ^client_id),
        set: [refresh_token_revoked_at: DateTime.utc_now()]
      )

      assert {:ok, 0} = Push.notify_user(user.id, "activity", {"tasks", Ecto.UUID.generate()})
      assert Push.deliverable(installation.id, user.id) == nil
      assert %{retired_reason: "session_ended", token: nil, user_id: nil} = Repo.reload!(installation)

      assert [%{metadata: %{"reason" => "session_ended"}}] =
               Repo.all(from a in Activity, where: a.action == "push_installation.retired")
    end

    test "an access-token revocation or expired refresh TTL also ends the session", %{user: user} do
      revoked_client = native_client_id(user)
      expired_client = native_client_id(user)
      {:ok, revoked} = Push.register(user, revoked_client, Ecto.UUID.generate(), ios_device())
      {:ok, expired} = Push.register(user, expired_client, Ecto.UUID.generate(), ios_device())

      Repo.update_all(from(t in Token, where: t.client_id == ^revoked_client),
        set: [revoked_at: DateTime.utc_now()]
      )

      ttl = Clients.get_client(expired_client).refresh_token_ttl
      past = NaiveDateTime.add(NaiveDateTime.utc_now(), -(ttl + 60))
      Repo.update_all(from(t in Token, where: t.client_id == ^expired_client), set: [inserted_at: past])

      assert Push.deliverable(revoked.id, user.id) == nil
      assert Push.deliverable(expired.id, user.id) == nil
    end

    test "a grant held by another user does not keep the registration alive", %{user: user} = context do
      other_users_client = native_client_id(user_fixture())
      {:ok, installation} = Push.register(user, other_users_client, context.installation_id, ios_device())

      assert Push.deliverable(installation.id, user.id) == nil
    end

    test "prune retires registrations whose session ended without a DELETE",
         %{user: user, client_id: client_id} = ctx do
      {:ok, ended} = Push.register(user, client_id, ctx.installation_id, ios_device())
      live_client = native_client_id(user)
      {:ok, live} = Push.register(user, live_client, Ecto.UUID.generate(), ios_device())

      Repo.update_all(from(t in Token, where: t.client_id == ^client_id),
        set: [refresh_token_revoked_at: DateTime.utc_now()]
      )

      assert {:ok, %{session_ended: 1}} = Push.prune()
      assert Repo.reload!(ended).retired_reason == "session_ended"
      assert Repo.reload!(live).retired_at == nil
    end
  end

  describe "audit" do
    test "records registration, retirement and enqueue without tokens", %{user: user, client_id: client_id} = context do
      token = ios_token()

      {:ok, installation} =
        Push.register(user, client_id, context.installation_id, ios_device(%{"token" => token}), interface: "api")

      {:ok, _} =
        Push.register(user, client_id, context.installation_id, ios_device(%{"token" => token}), interface: "api")

      {:ok, 1} = Push.notify_user(user.id, "activity", {"tasks", Ecto.UUID.generate()})
      :ok = Push.unregister(user, client_id, context.installation_id, interface: "api")

      activities = Repo.all(from a in Activity, where: like(a.action, "push_%"), order_by: a.id)

      assert Enum.map(activities, & &1.action) == [
               "push_installation.registered",
               "push_notification.queued",
               "push_installation.retired"
             ]

      [registered, queued, retired] = activities
      assert registered.actor_id == user.id and registered.interface == "api"
      assert registered.target_id == installation.id

      assert registered.metadata == %{
               "platform" => "ios",
               "environment" => "production",
               "created" => true,
               "token_rotated" => false
             }

      assert %{"kind" => "activity", "screen" => "tasks", "queued" => 1} = queued.metadata
      assert retired.metadata == %{"reason" => "unregistered", "platform" => "ios"}
      refute inspect(activities) =~ token
    end
  end

  describe "prune/0" do
    test "retires stale registrations and deletes old tombstones", %{user: user, client_id: client_id} do
      {:ok, stale} = Push.register(user, client_id, Ecto.UUID.generate(), ios_device())
      {:ok, fresh} = Push.register(user, client_id, Ecto.UUID.generate(), ios_device())
      {:ok, old} = Push.register(user, client_id, Ecto.UUID.generate(), ios_device())
      :ok = Push.unregister(user, client_id, old.installation_id)

      long_ago = DateTime.add(DateTime.utc_now(), -200, :day)
      Repo.update_all(where(Installation, id: ^stale.id), set: [last_registered_at: long_ago])
      Repo.update_all(where(Installation, id: ^old.id), set: [retired_at: long_ago])

      assert {:ok, %{retired: 1, deleted: 1}} = Push.prune()
      assert %{retired_reason: "stale"} = Repo.reload!(stale)
      assert Repo.reload!(fresh).retired_at == nil
      assert Repo.get(Installation, old.id) == nil
    end
  end
end
