defmodule Tuist.Kura.RunnerCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Builds
  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.RunnerCache
  alias Tuist.Kura.Server
  alias Tuist.Kura.StorageRollup
  alias Tuist.Repo
  alias Tuist.Runners.Profile
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @rented_macos_pool "tuist-tuist-runner-pool-macos-26-5"
  @site_macos_pool "tuist-tuist-runner-pool-macos-ber1-26-5"

  setup :set_mimic_from_context

  # Drive Regions.available/0 to the real private-region catalog:
  # `scw-fr-par-runners` serves [:macos] and is the only private region
  # (Linux runners have none). It provisions through KubernetesController
  # whose `provision/3` is pure (builds the instance name), and
  # `destroy_server/1` only flips DB state — so reconcile runs for real
  # against the sandbox.
  setup do
    stub(Tuist.Environment, :env, fn -> :prod end)
    stub(Tuist.Environment, :dev?, fn -> false end)
    stub(Tuist.Environment, :test?, fn -> false end)

    stub(Tuist.Environment, :kura_available_region_ids, fn ->
      ["scw-fr-par-runners"]
    end)

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.2" end)

    stub(Tuist.Environment, :runners_site_pools, fn ->
      %{@site_macos_pool => %{site: "ber1", platform: :macos}}
    end)

    :ok
  end

  # A macOS account also gets a job claimed on the rented fleet now, which is
  # what the region without a site needs to hold its node, unless a test
  # passes `rented_job: false` to control the account's jobs itself.
  defp account_with_profiles(platforms, opts \\ []) do
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

    if :macos in platforms and Keyword.get(opts, :rented_job, true) do
      claimed_job(account, @rented_macos_pool)
    end

    account
  end

  defp claimed_job(account, fleet_name, opts \\ []) do
    claimed_at =
      Keyword.get_lazy(opts, :claimed_at, fn ->
        DateTime.add(DateTime.utc_now(), -Keyword.get(opts, :days_ago, 0) * 86_400, :second)
      end)

    Repo.insert!(%WorkflowJob{
      workflow_job_id: System.unique_integer([:positive]),
      workflow_run_id: Keyword.get(opts, :workflow_run_id, 0),
      account_id: account.id,
      fleet_name: fleet_name,
      status: Keyword.get(opts, :status, "completed"),
      site: Keyword.get(opts, :site),
      platform: Keyword.get(opts, :platform, "macos"),
      enqueued_at: claimed_at,
      claimed_at: claimed_at,
      updated_at: DateTime.truncate(claimed_at, :second)
    })
  end

  # A job of the account on `fleet_name` whose CI run uploaded a build that
  # served `remote_hits` cacheable tasks from the remote cache.
  defp build_in_job(account, fleet_name, opts \\ []) do
    workflow_run_id = System.unique_integer([:positive])

    claimed_job(account, fleet_name,
      workflow_run_id: workflow_run_id,
      days_ago: Keyword.get(opts, :days_ago, 0),
      site: Keyword.get(opts, :site)
    )

    RunsFixtures.build_fixture(
      project_id: ProjectsFixtures.project_fixture(account_id: account.id).id,
      ci_run_id: Integer.to_string(workflow_run_id),
      cacheable_tasks_count: 10,
      cacheable_task_remote_hits_count: Keyword.get(opts, :remote_hits, 1)
    )
  end

  defp served_hits(account, region, date) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(%StorageRollup{
      account_id: account.id,
      region: region,
      date: date,
      hit_count: 100,
      inserted_at: now,
      updated_at: now
    })
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

  test "a site's region holds nodes only for accounts on the site cache flag" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["scw-fr-par-runners", "ber1-runners"] end)
    on_site = account_with_profiles([:macos])
    build_in_job(on_site, @site_macos_pool)
    off_site = account_with_profiles([:macos])
    build_in_job(off_site, @site_macos_pool)
    set_runner_availability([on_site.id, off_site.id])
    stub(FeatureFlags, :runner_site_cache_enabled?, fn account -> account.id == on_site.id end)
    stub(FeatureFlags, :runner_site_enabled?, fn _ -> false end)

    assert :ok = RunnerCache.reconcile()

    assert server_regions(on_site) == ["ber1-runners", "scw-fr-par-runners"]
    assert server_regions(off_site) == ["scw-fr-par-runners"]
  end

  test "tears down a site's node when the account leaves the site cache flag" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["ber1-runners"] end)
    account = account_with_profiles([:macos])
    build_in_job(account, @site_macos_pool)
    set_runner_availability([account.id])
    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> true end)
    stub(FeatureFlags, :runner_site_enabled?, fn _ -> false end)
    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["ber1-runners"]

    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> false end)
    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == []
  end

  test "a site's region holds nodes for accounts whose jobs run at the site" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["ber1-runners"] end)
    on_site = account_with_profiles([:macos])
    build_in_job(on_site, @site_macos_pool)
    off_site = account_with_profiles([:macos])
    build_in_job(off_site, @site_macos_pool)
    set_runner_availability([on_site.id, off_site.id])
    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> false end)
    stub(FeatureFlags, :runner_site_enabled?, fn account -> account.id == on_site.id end)

    assert :ok = RunnerCache.reconcile()

    assert server_regions(on_site) == ["ber1-runners"]
    assert server_regions(off_site) == []
  end

  test "a site's region counts the jobs of its pool claimed at the site, not those claimed at another" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["ber1-runners"] end)
    at_site = account_with_profiles([:macos])
    build_in_job(at_site, @site_macos_pool, site: "ber1")
    elsewhere = account_with_profiles([:macos])
    build_in_job(elsewhere, @site_macos_pool, site: "larch")
    before_sites = account_with_profiles([:macos])
    build_in_job(before_sites, @site_macos_pool)
    set_runner_availability([at_site.id, elsewhere.id, before_sites.id])
    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> false end)
    stub(FeatureFlags, :runner_site_enabled?, fn _ -> true end)

    assert :ok = RunnerCache.reconcile()

    assert server_regions(at_site) == ["ber1-runners"]
    assert server_regions(elsewhere) == []
    assert server_regions(before_sites) == ["ber1-runners"]
  end

  test "a site's region holds nodes only for flagged accounts whose site jobs hit the remote cache" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["ber1-runners"] end)
    remote_hits = account_with_profiles([:macos])
    build_in_job(remote_hits, @site_macos_pool)
    local_only = account_with_profiles([:macos])
    build_in_job(local_only, @site_macos_pool, remote_hits: 0)
    hits_off_site = account_with_profiles([:macos])
    claimed_job(hits_off_site, @site_macos_pool, workflow_run_id: System.unique_integer([:positive]))
    build_in_job(hits_off_site, @rented_macos_pool)
    stale = account_with_profiles([:macos])
    build_in_job(stale, @site_macos_pool, days_ago: 8)
    no_jobs = account_with_profiles([:macos], rented_job: false)
    set_runner_availability([remote_hits.id, local_only.id, hits_off_site.id, stale.id, no_jobs.id])
    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> true end)
    stub(FeatureFlags, :runner_site_enabled?, fn _ -> false end)

    assert :ok = RunnerCache.reconcile()

    assert server_regions(remote_hits) == ["ber1-runners"]
    assert server_regions(local_only) == []
    assert server_regions(hits_off_site) == []
    assert server_regions(stale) == []
    assert server_regions(no_jobs) == []
  end

  test "keeps a site's node while it serves hits and tears it down once they stop" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["ber1-runners"] end)
    account = account_with_profiles([:macos], rented_job: false)
    set_runner_availability([account.id])
    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> true end)
    stub(FeatureFlags, :runner_site_enabled?, fn _ -> false end)
    rollup = served_hits(account, "ber1-runners", Date.utc_today())

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["ber1-runners"]

    Repo.update!(Ecto.Changeset.change(rollup, date: Date.add(Date.utc_today(), -8)))
    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == []
  end

  test "keeps a site's nodes when its traffic cannot be read" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["ber1-runners"] end)
    account = account_with_profiles([:macos], rented_job: false)
    build_in_job(account, @site_macos_pool)
    set_runner_availability([account.id])
    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> true end)
    stub(FeatureFlags, :runner_site_enabled?, fn _ -> false end)
    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["ber1-runners"]

    stub(Builds, :ci_runs_with_remote_cache_hits, fn _project_ids, _ci_run_ids, _since -> {:error, :timeout} end)
    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == ["ber1-runners"]
  end

  test "the rented fleet's region holds nodes only for accounts with recent jobs there" do
    rented = account_with_profiles([:macos], rented_job: false)
    claimed_job(rented, @rented_macos_pool, days_ago: 6)
    at_site = account_with_profiles([:macos], rented_job: false)
    claimed_job(at_site, @site_macos_pool)
    stale = account_with_profiles([:macos], rented_job: false)
    claimed_job(stale, @rented_macos_pool, days_ago: 8)
    linux_jobs = account_with_profiles([:macos], rented_job: false)
    claimed_job(linux_jobs, "tuist-tuist-runner-pool-linux-2vcpu-8gb", platform: "linux")
    idle = account_with_profiles([:macos], rented_job: false)
    set_runner_availability([rented.id, at_site.id, stale.id, linux_jobs.id, idle.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(rented) == ["scw-fr-par-runners"]
    assert server_regions(at_site) == []
    assert server_regions(stale) == []
    assert server_regions(linux_jobs) == []
    assert server_regions(idle) == []
  end

  test "tears down the rented fleet's node once the account's jobs there age out" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["scw-fr-par-runners"]

    eight_days_ago = DateTime.add(DateTime.utc_now(), -8 * 86_400, :second)

    Repo.update_all(from(j in WorkflowJob, where: j.account_id == ^account.id),
      set: [claimed_at: eight_days_ago, updated_at: DateTime.truncate(eight_days_ago, :second)]
    )

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == []

    Repo.update_all(from(s in Server, where: s.account_id == ^account.id), set: [status: :destroyed])
    claimed_job(account, @rented_macos_pool)

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["scw-fr-par-runners"]
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

  test "drains an active node the region no longer serves instead of tearing it down" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()
    server = activate(account)
    assert Kura.runner_cache_endpoint_url(account, :macos) == server.url

    set_runner_availability([])
    assert :ok = RunnerCache.reconcile()

    assert %Server{status: :drain_pending, drain_started_at: %DateTime{}} = Repo.get!(Server, server.id)
    assert Kura.runner_cache_endpoint_url(account, :macos) == nil

    assert :ok = RunnerCache.reconcile()

    assert Repo.get!(Server, server.id).status == :drain_pending
  end

  test "tears down a drained node once no job claimed on the region's pools before the drain is in flight" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()
    server = activate(account)
    an_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)
    in_flight = claimed_job(account, @rented_macos_pool, status: "running", claimed_at: an_hour_ago)
    claimed_job(account, @site_macos_pool, status: "running", claimed_at: an_hour_ago)
    set_runner_availability([])
    assert :ok = RunnerCache.reconcile()
    drained_for(server, 20 * 60)
    claimed_job(account, @rented_macos_pool, status: "claimed")

    assert :ok = RunnerCache.reconcile()
    assert Repo.get!(Server, server.id).status == :drain_pending

    Repo.update!(Ecto.Changeset.change(in_flight, status: "completed"))
    assert :ok = RunnerCache.reconcile()

    assert Repo.get!(Server, server.id).status == :destroying
  end

  test "a drained site node waits only for the jobs claimed at its site" do
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["ber1-runners"] end)
    stub(FeatureFlags, :runner_site_cache_enabled?, fn _ -> false end)
    stub(FeatureFlags, :runner_site_enabled?, fn _ -> true end)
    account = account_with_profiles([:macos])
    build_in_job(account, @site_macos_pool, site: "ber1")
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()
    server = activate(account, "ber1-runners")
    an_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)
    at_site = claimed_job(account, @site_macos_pool, status: "running", claimed_at: an_hour_ago, site: "ber1")
    claimed_job(account, @site_macos_pool, status: "running", claimed_at: an_hour_ago, site: "larch")
    set_runner_availability([])
    assert :ok = RunnerCache.reconcile()
    drained_for(server, 20 * 60)

    assert :ok = RunnerCache.reconcile()
    assert Repo.get!(Server, server.id).status == :drain_pending

    Repo.update!(Ecto.Changeset.change(at_site, status: "completed"))
    assert :ok = RunnerCache.reconcile()

    assert Repo.get!(Server, server.id).status == :destroying
  end

  test "tears down a drained node after six hours whatever is in flight" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()
    server = activate(account)
    claimed_job(account, @rented_macos_pool, status: "running", claimed_at: DateTime.add(DateTime.utc_now(), -7, :hour))
    set_runner_availability([])
    assert :ok = RunnerCache.reconcile()

    drained_for(server, 5 * 3600)
    assert :ok = RunnerCache.reconcile()
    assert Repo.get!(Server, server.id).status == :drain_pending

    drained_for(server, 6 * 3600)
    assert :ok = RunnerCache.reconcile()

    assert Repo.get!(Server, server.id).status == :destroying
  end

  test "returns a draining node to service when the region serves the account again" do
    account = account_with_profiles([:macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()
    server = activate(account)
    set_runner_availability([])
    assert :ok = RunnerCache.reconcile()
    assert Repo.get!(Server, server.id).status == :drain_pending

    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()

    assert %Server{status: :active, drain_started_at: nil} = Repo.get!(Server, server.id)
    assert Repo.aggregate(from(s in Server, where: s.account_id == ^account.id), :count) == 1
    assert Kura.runner_cache_endpoint_url(account, :macos) == server.url
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

  test "provisions every eligible account outside production and canary" do
    first = account_with_profiles([:macos])
    second = account_with_profiles([:macos])
    stub(Tuist.Environment, :env, fn -> :dev end)
    reject(FunWithFlags, :get_flag, 1)
    reject(FunWithFlags, :enabled?, 2)
    reject(FeatureFlags, :runners_enabled?, 2)
    reject(Sentry, :capture_message, 2)

    assert :ok = RunnerCache.reconcile()

    assert server_regions(first) == ["scw-fr-par-runners"]
    assert server_regions(second) == ["scw-fr-par-runners"]
  end

  test "provisions only the account enabled by the runner flag in canary" do
    enabled = account_with_profiles([:macos])
    other = account_with_profiles([:macos])
    stub(Tuist.Environment, :env, fn -> :can end)
    set_runner_availability([enabled.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(enabled) == ["scw-fr-par-runners"]
    assert server_regions(other) == []
  end

  test "bounds unsettled servers per region and refills slots as servers become active" do
    accounts = Enum.map(1..12, fn _index -> account_with_profiles([:macos]) end)
    set_runner_availability(Enum.map(accounts, & &1.id))

    assert :ok = RunnerCache.reconcile()
    assert Repo.aggregate(Server, :count) == 10

    assert :ok = RunnerCache.reconcile()
    assert Repo.aggregate(Server, :count) == 10

    Server
    |> order_by([s], asc: s.id)
    |> limit(3)
    |> Repo.all()
    |> Enum.each(fn server ->
      server
      |> Server.observation_changeset(%{
        status: :active,
        url: "https://#{server.id}.example.com",
        current_image_tag: "0.5.2"
      })
      |> Repo.update!()
    end)

    assert :ok = RunnerCache.reconcile()
    assert Repo.aggregate(Server, :count) == 12
    assert Repo.aggregate(from(s in Server, where: s.status == :active), :count) == 3
    assert Repo.aggregate(from(s in Server, where: s.status == :provisioning), :count) == 9
  end

  test "retries failed servers without admitting more accounts while teardown is pending" do
    accounts = Enum.map(1..11, fn _index -> account_with_profiles([:macos]) end)
    set_runner_availability(Enum.map(accounts, & &1.id))

    assert :ok = RunnerCache.reconcile()

    servers =
      Server
      |> order_by([s], asc: s.id)
      |> Repo.all()

    servers
    |> Enum.take(5)
    |> Enum.each(fn server ->
      assert {:ok, _server} = Kura.destroy_server(server)
    end)

    servers
    |> Enum.drop(5)
    |> Enum.each(fn server ->
      deployment = Repo.get_by!(Deployment, kura_server_id: server.id)
      assert {:ok, deployment} = Kura.mark_running(deployment)
      assert {:ok, deployment} = Kura.mark_failed(deployment, "temporary failure")
      deployment |> Ecto.Changeset.change(finished_at: minutes_ago(2)) |> Repo.update!()
      assert {:ok, _server} = Kura.fail_server(server)
    end)

    assert :ok = RunnerCache.reconcile()
    assert Repo.aggregate(Server, :count) == 10
    assert Repo.aggregate(from(s in Server, where: s.status == :destroying), :count) == 5
    assert Repo.aggregate(from(s in Server, where: s.status == :provisioning), :count) == 5
  end

  test "retries at most ten failed servers in deterministic order" do
    accounts = Enum.map(1..12, fn _index -> account_with_profiles([:macos]) end)

    Enum.each(accounts, fn account ->
      {:ok, server} = Kura.create_server(%{account_id: account.id, region: "scw-fr-par-runners", image_tag: "0.5.2"})
      deployment = Repo.get_by!(Deployment, kura_server_id: server.id)
      assert {:ok, deployment} = Kura.mark_running(deployment)
      assert {:ok, deployment} = Kura.mark_failed(deployment, "temporary failure")
      deployment |> Ecto.Changeset.change(finished_at: minutes_ago(2)) |> Repo.update!()
      assert {:ok, _server} = Kura.fail_server(server)
    end)

    ordered_server_ids =
      Repo.all(
        from(s in Server,
          order_by: [asc: s.updated_at, asc: s.id],
          select: s.id
        )
      )

    set_runner_availability(Enum.map(accounts, & &1.id))

    assert :ok = RunnerCache.reconcile()
    assert Repo.aggregate(from(s in Server, where: s.status == :provisioning), :count) == 10
    assert Repo.aggregate(from(s in Server, where: s.status == :failed), :count) == 2

    retried_server_ids =
      Repo.all(
        from(s in Server,
          where: s.status == :provisioning,
          select: s.id
        )
      )

    assert MapSet.new(retried_server_ids) == MapSet.new(Enum.take(ordered_server_ids, 10))
  end

  test "does not retry a disabled failed server outside the teardown batch" do
    servers =
      Enum.map(1..101, fn _index ->
        account = account_with_profiles([:macos])
        {:ok, server} = Kura.create_server(%{account_id: account.id, region: "scw-fr-par-runners", image_tag: "0.5.2"})
        server
      end)

    failed_server = List.last(servers)
    deployment = Repo.get_by!(Deployment, kura_server_id: failed_server.id)
    assert {:ok, deployment} = Kura.mark_running(deployment)
    assert {:ok, deployment} = Kura.mark_failed(deployment, "temporary failure")
    deployment |> Ecto.Changeset.change(finished_at: minutes_ago(2)) |> Repo.update!()
    assert {:ok, _server} = Kura.fail_server(failed_server)

    set_runner_availability([])

    assert :ok = RunnerCache.reconcile()
    assert Repo.aggregate(from(s in Server, where: s.status == :destroying), :count) == 100
    assert Repo.get!(Server, failed_server.id).status == :failed
    assert open_deployment_count(failed_server) == 0
  end

  test "tears down nodes for accounts disabled by the runner flag in canary" do
    enabled = account_with_profiles([:macos])
    other = account_with_profiles([:macos])
    set_runner_availability([enabled.id, other.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(enabled) == ["scw-fr-par-runners"]
    assert server_regions(other) == ["scw-fr-par-runners"]

    stub(Tuist.Environment, :env, fn -> :can end)
    set_runner_availability([enabled.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(enabled) == ["scw-fr-par-runners"]
    assert server_regions(other) == []
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

  defp activate(account, region \\ "scw-fr-par-runners") do
    Server
    |> Repo.get_by!(account_id: account.id, region: region)
    |> Server.observation_changeset(%{
      status: :active,
      url: "https://#{account.id}.runners.example.com",
      current_image_tag: "0.5.2",
      last_ready_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
    |> Repo.update!()
  end

  defp drained_for(server, seconds) do
    drain_started_at = DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(s in Server, where: s.id == ^server.id), set: [drain_started_at: drain_started_at])
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
