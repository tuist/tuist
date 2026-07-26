defmodule Tuist.Kura.RunnerCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.RunnerCache
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Runners.Profile
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  # Drive Regions.available/0 to the real private-region catalog:
  # `scw-fr-par-runners` serves [:macos] and is the only private region
  # (Linux runners have none). It provisions through KubernetesController
  # whose `provision/3` is pure (builds the instance name), and
  # `destroy_server/1` only flips DB state — so reconcile runs for real
  # against the sandbox.
  setup do
    stub(Tuist.Environment, :dev?, fn -> false end)
    stub(Tuist.Environment, :test?, fn -> false end)
    stub(Tuist.Environment, :prod?, fn -> true end)

    stub(Tuist.Environment, :kura_available_region_ids, fn ->
      ["scw-fr-par-runners"]
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

  defp set_runner_availability(account_ids) do
    gates =
      Enum.map(account_ids, fn account_id ->
        %FunWithFlags.Gate{type: :actor, for: "account:#{account_id}", enabled: true}
      end)

    stub(FunWithFlags, :get_flag, fn :runners ->
      %FunWithFlags.Flag{name: :runners, gates: gates}
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
    set_runner_availability([linux_only.id, macos_too.id])

    assert :ok = RunnerCache.reconcile()

    # A region's cache only serves the fleet it sits next to. macOS
    # profiles get the Scaleway fr-par node; there is no Linux-serving
    # region, so a Linux-only account gets nothing rather than a node in
    # the macOS region, whose URL would route cache traffic across the WAN.
    assert server_regions(linux_only) == []
    assert server_regions(macos_too) == ["scw-fr-par-runners"]
  end

  test "is inert without a private runner-cache region" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> [] end)
    reject(FunWithFlags, :get_flag, 1)

    assert :ok = RunnerCache.reconcile()
  end

  test "accounts without runner access get no nodes" do
    account = account_with_profiles([:linux, :macos])
    set_runner_availability([])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == []
  end

  test "does not modify nodes when runner availability cannot be evaluated" do
    existing = account_with_profiles([:macos])
    set_runner_availability([existing.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(existing) == ["scw-fr-par-runners"]

    candidate = account_with_profiles([:macos])
    stub(FunWithFlags, :get_flag, fn :runners -> {:error, :unavailable} end)
    reject(FeatureFlags, :runners_enabled?, 2)

    assert_raise RuntimeError, "could not load runner availability: :unavailable", fn ->
      RunnerCache.reconcile()
    end

    assert server_regions(existing) == ["scw-fr-par-runners"]
    assert server_regions(candidate) == []
  end

  test "tears down an account's node when runner access is removed" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["scw-fr-par-runners"]

    set_runner_availability([])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == []
  end

  test "tears down a region's node when its served platforms lose their profiles" do
    account = account_with_profiles([:linux, :macos])
    set_runner_availability([account.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["scw-fr-par-runners"]

    # Dropping the macOS profile leaves nothing the region serves, so its
    # node is torn down. The remaining Linux profile has no region of its
    # own to keep a node in.
    Repo.delete_all(from(p in Profile, where: p.account_id == ^account.id and p.platform == :macos))

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == []
  end

  test "uses runner availability rather than profile existence as the entitlement" do
    unavailable = account_with_profiles([:macos])
    enabled = account_with_profiles([:macos])
    set_runner_availability([enabled.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(unavailable) == []
    assert server_regions(enabled) == ["scw-fr-par-runners"]
  end

  test "narrows actor-only production availability before evaluating accounts" do
    unavailable = account_with_profiles([:macos])
    enabled = account_with_profiles([:macos])
    stub(Tuist.Environment, :prod?, fn -> true end)

    stub(FunWithFlags, :get_flag, fn :runners ->
      %FunWithFlags.Flag{
        name: :runners,
        gates: [%FunWithFlags.Gate{type: :actor, for: "account:#{enabled.id}", enabled: true}]
      }
    end)

    expect(FeatureFlags, :runners_enabled?, fn account, _flag ->
      assert account.id == enabled.id
      true
    end)

    assert :ok = RunnerCache.reconcile()

    assert server_regions(unavailable) == []
    assert server_regions(enabled) == ["scw-fr-par-runners"]
  end

  test "macOS-only accounts get a node in the macOS-serving region" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == ["scw-fr-par-runners"]
  end

  test "is inert without a runtime image tag except for tear-downs" do
    account = account_with_profiles([:linux, :macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)
    Repo.delete_all(from(p in Profile, where: p.account_id == ^account.id))
    fresh = account_with_profiles([:linux])
    set_runner_availability([account.id, fresh.id])

    assert :ok = RunnerCache.reconcile()

    # No new node for the fresh account (no image tag to provision
    # with), but the profile-less account's nodes are still freed.
    assert server_regions(fresh) == []
    assert server_regions(account) == []
  end

  test "provisions every eligible account when runners are available outside production" do
    first = account_with_profiles([:macos])
    second = account_with_profiles([:macos])
    stub(Tuist.Environment, :prod?, fn -> false end)
    reject(FunWithFlags, :get_flag, 1)
    reject(FunWithFlags, :enabled?, 2)
    reject(FeatureFlags, :runners_enabled?, 2)
    reject(Sentry, :capture_message, 2)

    assert :ok = RunnerCache.reconcile()

    assert server_regions(first) == ["scw-fr-par-runners"]
    assert server_regions(second) == ["scw-fr-par-runners"]
  end

  test "waits for the retry backoff before retrying the same image" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()

    server = Repo.get_by!(Server, account_id: account.id, region: "scw-fr-par-runners")
    deployment = Repo.get_by!(Deployment, kura_server_id: server.id)
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, deployment} = Kura.mark_failed(deployment, "temporary failure")
    {:ok, _server} = Kura.fail_server(server)

    assert :ok = RunnerCache.reconcile()
    assert open_deployment_count(server) == 0

    old_failure = minutes_ago(2)
    deployment |> Ecto.Changeset.change(finished_at: old_failure) |> Repo.update!()

    assert :ok = RunnerCache.reconcile()
    assert open_deployment_count(server) == 1
  end

  test "caps repeated same-image retries at one hour" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()

    server = Repo.get_by!(Server, account_id: account.id, region: "scw-fr-par-runners")
    initial = Repo.get_by!(Deployment, kura_server_id: server.id)
    {:ok, initial} = Kura.mark_running(initial)
    {:ok, initial} = Kura.mark_failed(initial, "temporary failure")

    initial
    |> Ecto.Changeset.change(finished_at: minutes_ago(240))
    |> Repo.update!()

    {:ok, _server} = Kura.fail_server(server)

    for minutes <- [180, 120, 50] do
      Repo.insert!(%Deployment{
        cluster_id: "scw-fr-par",
        image_tag: "0.5.2",
        kura_server_id: server.id,
        status: :failed,
        error_message: "temporary failure",
        finished_at: minutes_ago(minutes)
      })
    end

    assert :ok = RunnerCache.reconcile()
    assert open_deployment_count(server) == 0

    latest =
      Deployment
      |> where([d], d.kura_server_id == ^server.id and d.status == :failed)
      |> order_by([d], desc: d.finished_at)
      |> limit(1)
      |> Repo.one!()

    latest
    |> Ecto.Changeset.change(finished_at: minutes_ago(61))
    |> Repo.update!()

    assert :ok = RunnerCache.reconcile()
    assert open_deployment_count(server) == 1
  end

  test "retries immediately when the configured image changes" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()

    server = Repo.get_by!(Server, account_id: account.id, region: "scw-fr-par-runners")
    deployment = Repo.get_by!(Deployment, kura_server_id: server.id)
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, _deployment} = Kura.mark_failed(deployment, "broken image")
    {:ok, _server} = Kura.fail_server(server)

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.3" end)

    assert :ok = RunnerCache.reconcile()

    assert %Deployment{image_tag: "0.5.3", status: :pending} =
             Repo.get_by!(Deployment, kura_server_id: server.id, status: :pending)
  end

  defp open_deployment_count(server) do
    Repo.aggregate(
      from(d in Deployment,
        where: d.kura_server_id == ^server.id and d.status in [:pending, :running]
      ),
      :count
    )
  end

  defp minutes_ago(minutes) do
    DateTime.utc_now()
    |> DateTime.add(-minutes, :minute)
    |> DateTime.truncate(:second)
  end
end
