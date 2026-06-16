defmodule Tuist.Kura.RunnerCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Kura.RunnerCache
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Runners.Profile
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  # Drive Regions.available/0 to the real private-region catalog
  # entries: `scw-fr-par-runners` serves [:macos] only,
  # `hetzner-staging-runners` serves [:linux] only. Both provision
  # through KubernetesController whose `provision/3` is pure (builds
  # the instance name), and `destroy_server/1` only flips DB state —
  # so reconcile runs for real against the sandbox.
  setup do
    stub(Tuist.Environment, :dev?, fn -> false end)
    stub(Tuist.Environment, :test?, fn -> false end)

    stub(Tuist.Environment, :kura_available_region_ids, fn ->
      ["scw-fr-par-runners", "hetzner-staging-runners"]
    end)

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.2" end)
    :ok
  end

  defp account_with_profiles(platforms) do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    # Account bootstrap auto-creates protected default profiles; drop
    # them so each test controls exactly which platforms the account
    # uses runners on.
    Repo.delete_all(from(p in Profile, where: p.account_id == ^account.id))

    for platform <- platforms do
      Repo.insert!(%Profile{
        account_id: account.id,
        name: Atom.to_string(platform),
        platform: platform,
        vcpus: 4,
        memory_gb: 16,
        xcode_version: if(platform == :macos, do: "26.5")
      })
    end

    account
  end

  defp enable_runners_for(account_ids) do
    stub(FunWithFlags, :enabled?, fn :runners, [for: %{id: account_id}] ->
      account_id in account_ids
    end)
  end

  defp server_regions(account) do
    Repo.all(
      from(s in Server,
        where: s.account_id == ^account.id and s.status not in [:destroying, :destroyed],
        select: s.region,
        order_by: s.region
      )
    )
  end

  test "provisions per region by served platform" do
    linux_only = account_with_profiles([:linux])
    macos_too = account_with_profiles([:linux, :macos])
    enable_runners_for([linux_only.id, macos_too.id])

    assert :ok = RunnerCache.reconcile()

    # Each fleet's cache lives next to it: Linux profiles get the
    # Hetzner node, macOS profiles the Scaleway fr-par one. A
    # Linux-only account never gets a node in the macOS-serving
    # region — its URL would route cache traffic across the WAN.
    assert server_regions(linux_only) == ["hetzner-staging-runners"]
    assert server_regions(macos_too) == ["hetzner-staging-runners", "scw-fr-par-runners"]
  end

  test "accounts without the runners flag get no nodes" do
    account = account_with_profiles([:linux, :macos])
    enable_runners_for([])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == []
  end

  test "tears down a region's node when its served platforms lose their profiles" do
    account = account_with_profiles([:linux, :macos])
    enable_runners_for([account.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["hetzner-staging-runners", "scw-fr-par-runners"]

    # Dropping the macOS profile frees the macOS-serving node but
    # keeps the node in the region that still serves the remaining
    # Linux profile.
    Repo.delete_all(from(p in Profile, where: p.account_id == ^account.id and p.platform == :macos))

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["hetzner-staging-runners"]
  end

  test "an enabled account beyond the first candidate page still gets a node" do
    # Default profiles are auto-created for every account, so
    # non-enabled accounts dominate the candidate set and never leave
    # it. The enabled account is created LAST (highest id): a single
    # capped page ordered by id would return only non-enabled rows
    # forever and starve it.
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    now_utc = DateTime.truncate(DateTime.utc_now(), :second)

    filler_rows =
      for i <- 1..110 do
        %{
          name: "starved-filler-#{i}-#{System.unique_integer([:positive])}",
          billing_email: "starved-filler-#{i}@tuist.dev",
          created_at: now,
          updated_at: now
        }
      end

    {110, filler_accounts} = Repo.insert_all(Tuist.Accounts.Account, filler_rows, returning: [:id])

    profile_rows =
      for %{id: account_id} <- filler_accounts do
        %{
          account_id: account_id,
          name: "linux",
          platform: :linux,
          vcpus: 4,
          memory_gb: 16,
          inserted_at: now_utc,
          updated_at: now_utc
        }
      end

    Repo.insert_all(Profile, profile_rows)

    enabled = account_with_profiles([:linux])
    enable_runners_for([enabled.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(enabled) == ["hetzner-staging-runners"]
  end

  test "macOS-only accounts get no node in the linux-serving region" do
    account = account_with_profiles([:macos])
    enable_runners_for([account.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == ["scw-fr-par-runners"]
  end

  test "is inert without a runtime image tag except for tear-downs" do
    account = account_with_profiles([:linux, :macos])
    enable_runners_for([account.id])
    assert :ok = RunnerCache.reconcile()

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)
    Repo.delete_all(from(p in Profile, where: p.account_id == ^account.id))
    fresh = account_with_profiles([:linux])
    enable_runners_for([account.id, fresh.id])

    assert :ok = RunnerCache.reconcile()

    # No new node for the fresh account (no image tag to provision
    # with), but the profile-less account's nodes are still freed.
    assert server_regions(fresh) == []
    assert server_regions(account) == []
  end
end
