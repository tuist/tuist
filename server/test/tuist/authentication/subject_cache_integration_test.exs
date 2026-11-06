defmodule Tuist.Authentication.SubjectCacheIntegrationTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Authentication.SubjectCache
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_global

  setup do
    cache = String.to_atom("auth_integration_#{UUIDv7.generate()}")
    start_supervised!({SubjectCache, cache: cache})
    %{cache: cache}
  end

  for change <- [:revocation, :scope, :deactivation] do
    test "#{change} takes effect by the original deadline", %{cache: cache} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, {token, value}} =
        Accounts.create_account_token(%{account: user.account, name: "bounded", scopes: ["project:cache:read"]})

      clock = :atomics.new(1, [])
      opts = [cache: cache, monotonic: fn -> :atomics.get(clock, 1) end]
      assert {:ok, %{subject: %{scopes: ["project:cache:read"]}, valid_until: 60_000}} = SubjectCache.fetch(value, opts)

      case unquote(change) do
        :revocation -> Accounts.delete_account_token(token)
        :scope -> token |> Ecto.Changeset.change(scopes: ["project:builds:read"]) |> Repo.update!()
        :deactivation -> user |> Ecto.Changeset.change(active: false) |> Repo.update!()
      end

      :atomics.put(clock, 1, 59_999)
      assert {:ok, %{subject: %{scopes: ["project:cache:read"]}, valid_until: 60_000}} = SubjectCache.fetch(value, opts)
      :atomics.put(clock, 1, 60_000)

      case unquote(change) do
        :scope -> assert {:ok, %{subject: %{scopes: ["project:builds:read"]}}} = SubjectCache.fetch(value, opts)
        _ -> assert SubjectCache.fetch(value, opts) == {:ok, nil}
      end
    end
  end

  test "malformed credential ids are invalid rather than backend failures", %{cache: cache} do
    assert SubjectCache.fetch("tuist_not-a-uuid_secret", cache: cache) == {:ok, nil}
  end

  test "the snapshot carries only verified JWT expiry" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, token, claims} = Tuist.Guardian.encode_and_sign(user, %{}, ttl: {1, :minute})
    assert %{subject: %{id: id}, expires_at: expiry} = Tuist.Authentication.authenticated_subject_snapshot(token)
    assert id == user.id
    assert expiry == claims["exp"]
    assert Tuist.Authentication.authenticated_subject_snapshot(token <> "tampered") == nil
  end
end
