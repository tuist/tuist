defmodule Tuist.Runners.ProfilesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @catalog [
    %{vcpus: 1, memory_gb: 2, key: "1vcpu-2gb", default?: false, pool_dispatch_label: ""},
    %{vcpus: 4, memory_gb: 16, key: "4vcpu-16gb", default?: true, pool_dispatch_label: ""},
    %{vcpus: 8, memory_gb: 32, key: "8vcpu-32gb", default?: false, pool_dispatch_label: ""}
  ]

  setup do
    stub(Catalog, :list, fn -> @catalog end)
    stub(Catalog, :default, fn -> Enum.find(@catalog, & &1.default?) end)

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "profiles-org-#{System.unique_integer([:positive])}",
        preload: [:account]
      )

    # `Accounts.create_organization` auto-bootstraps a protected
    # `linux` profile via `Profiles.create_default_for_account`.
    # The CRUD / matcher tests below assert behaviour on hand-
    # crafted shapes, so start from a clean slate; the default-
    # creation path has its own describe block that exercises the
    # auto-bootstrap directly.
    Tuist.Repo.delete_all(from(p in Profile, where: p.account_id == ^account.id))

    %{account: account}
  end

  describe "create/2" do
    test "persists a valid profile and normalises the name", %{account: account} do
      assert {:ok, %Profile{name: "default", vcpus: 4, memory_gb: 16}} =
               Profiles.create(account, %{"name" => "  Default ", "vcpus" => 4, "memory_gb" => 16})
    end

    test "rejects a shape not in the catalog", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Profiles.create(account, %{"name" => "weird", "vcpus" => 7, "memory_gb" => 13})

      assert {"must match one of the available resource configurations", _} = errors[:vcpus]
    end

    test "rejects a reserved name", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Profiles.create(account, %{"name" => "tuist", "vcpus" => 4, "memory_gb" => 16})

      assert errors[:name]
    end

    test "rejects a duplicate name for the same account", %{account: account} do
      {:ok, _} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Profiles.create(account, %{"name" => "default", "vcpus" => 1, "memory_gb" => 2})

      assert errors[:account_id] || errors[:name]
    end

    test "two accounts can both have a default profile", %{account: account_a} do
      %{account: account_b} =
        AccountsFixtures.organization_fixture(
          name: "profiles-org-b-#{System.unique_integer([:positive])}",
          preload: [:account]
        )

      assert {:ok, _} = Profiles.create(account_a, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})
      assert {:ok, _} = Profiles.create(account_b, %{"name" => "default", "vcpus" => 1, "memory_gb" => 2})
    end

    test "enforces the per-account cap", %{account: account} do
      for i <- 1..Profiles.max_per_account() do
        {:ok, _} = Profiles.create(account, %{"name" => "p#{i}", "vcpus" => 4, "memory_gb" => 16})
      end

      assert {:error, :max_profiles_reached} =
               Profiles.create(account, %{"name" => "extra", "vcpus" => 4, "memory_gb" => 16})
    end
  end

  describe "update/2" do
    test "ignores attempts to change the name", %{account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      assert {:ok, updated} =
               Profiles.update(profile, %{"name" => "renamed", "vcpus" => 1, "memory_gb" => 2})

      assert updated.name == "default"
      assert updated.vcpus == 1
      assert updated.memory_gb == 2
    end
  end

  describe "match_for_dispatch/2" do
    test "returns the profile whose tuist-<name> label is requested", %{account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "large", "vcpus" => 8, "memory_gb" => 32})

      assert {:ok, ^profile} =
               Profiles.match_for_dispatch(account, ["self-hosted", "tuist-large"])
    end

    test "is case-insensitive on label comparison", %{account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      assert {:ok, ^profile} =
               Profiles.match_for_dispatch(account, ["Self-Hosted", "TUIST-default"])
    end

    test "returns :no_matching_profile when nothing matches", %{account: account} do
      {:ok, _} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      assert {:error, :no_matching_profile} =
               Profiles.match_for_dispatch(account, ["self-hosted", "tuist-large"])
    end

    test "returns :no_matching_profile when the account has no profiles", %{account: account} do
      assert {:error, :no_matching_profile} =
               Profiles.match_for_dispatch(account, ["self-hosted", "tuist-default"])
    end

    test "on staging, matches under the tuist-staging- prefix and ignores plain tuist-",
         %{account: account} do
      # The shared GitHub App fans `workflow_job` events out to every
      # env's server, so each env's profiles must occupy a disjoint
      # label namespace — otherwise a production `tuist-foo` job
      # would also match staging's `foo` profile and double-dispatch.
      stub(Environment, :env, fn -> :stag end)
      {:ok, profile} = Profiles.create(account, %{"name" => "foo", "vcpus" => 4, "memory_gb" => 16})

      assert {:ok, ^profile} =
               Profiles.match_for_dispatch(account, ["self-hosted", "tuist-staging-foo"])

      assert {:error, :no_matching_profile} =
               Profiles.match_for_dispatch(account, ["self-hosted", "tuist-foo"])
    end

    test "on canary, matches under the tuist-canary- prefix", %{account: account} do
      stub(Environment, :env, fn -> :can end)
      {:ok, profile} = Profiles.create(account, %{"name" => "foo", "vcpus" => 4, "memory_gb" => 16})

      assert {:ok, ^profile} =
               Profiles.match_for_dispatch(account, ["self-hosted", "tuist-canary-foo"])
    end
  end

  describe "create_default_for_account/1" do
    test "inserts the protected `linux` profile at the catalog default shape",
         %{account: account} do
      assert {:ok, profile} = Profiles.create_default_for_account(account)
      assert profile.name == "linux"
      assert profile.protected
      assert profile.vcpus == 4
      assert profile.memory_gb == 16
    end

    test "is idempotent — second call is a no-op on `(account_id, name)` conflict",
         %{account: account} do
      {:ok, first} = Profiles.create_default_for_account(account)
      assert {:ok, _} = Profiles.create_default_for_account(account)

      assert [%Profile{id: id}] = Profiles.list_for_account(account)
      assert id == first.id
    end

    test "bypasses the per-account cap", %{account: account} do
      # Fill the cap with user-created profiles.
      for i <- 1..Profiles.max_per_account() do
        {:ok, _} = Profiles.create(account, %{"name" => "u#{i}", "vcpus" => 4, "memory_gb" => 16})
      end

      # The default still slots in.
      assert {:ok, profile} = Profiles.create_default_for_account(account)
      assert profile.protected
    end
  end

  describe "delete/1 — protected guard" do
    test "refuses to delete a protected profile", %{account: account} do
      {:ok, default} = Profiles.create_default_for_account(account)

      assert {:error, :protected} = Profiles.delete(default)
      assert Profiles.get_by_name(account, default.name)
    end
  end

  describe "Profile.prefix/0" do
    test "is plain tuist- on production" do
      stub(Environment, :env, fn -> :prod end)
      assert "tuist-" == Profile.prefix()
    end

    test "is tuist-staging- on staging" do
      stub(Environment, :env, fn -> :stag end)
      assert "tuist-staging-" == Profile.prefix()
    end

    test "is tuist-canary- on canary" do
      stub(Environment, :env, fn -> :can end)
      assert "tuist-canary-" == Profile.prefix()
    end
  end

  describe "delete/1" do
    test "removes the profile", %{account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      assert {:ok, _} = Profiles.delete(profile)
      assert Profiles.list_for_account(account) == []
    end
  end
end
