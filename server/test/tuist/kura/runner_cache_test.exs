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
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

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
    :ok
  end

  # Account bootstrap auto-creates default runner profiles for every
  # platform, so the account's claimed jobs are what decide which
  # platforms it uses runners on.
  defp account_running_jobs(platforms) do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    for platform <- platforms do
      insert_job(account, platform, claimed_at: DateTime.utc_now())
    end

    account
  end

  defp insert_job(account, platform, attrs) do
    Repo.insert!(
      struct!(
        %WorkflowJob{
          workflow_job_id: System.unique_integer([:positive]),
          account_id: account.id,
          fleet_name: "test",
          status: "completed",
          platform: Atom.to_string(platform),
          enqueued_at: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  defp age_jobs(account, platform, days) do
    Repo.update_all(
      from(j in WorkflowJob, where: j.account_id == ^account.id and j.platform == ^Atom.to_string(platform)),
      set: [claimed_at: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)]
    )
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
    linux_only = account_running_jobs([:linux])
    macos_too = account_running_jobs([:linux, :macos])
    set_runner_availability([linux_only.id, macos_too.id])

    assert :ok = RunnerCache.reconcile()

    # A region's cache only serves the fleet it sits next to. macOS
    # jobs get the Scaleway fr-par node; there is no Linux-serving
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
    account = account_running_jobs([:linux, :macos])
    set_runner_availability([])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == []
  end

  test "does not modify nodes when runner availability cannot be evaluated" do
    existing = account_running_jobs([:macos])
    set_runner_availability([existing.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(existing) == ["scw-fr-par-runners"]

    candidate = account_running_jobs([:macos])
    stub(FunWithFlags, :get_flag, fn :runners -> {:error, :unavailable} end)
    reject(FeatureFlags, :runners_enabled?, 2)

    assert_raise RuntimeError, "could not load runner availability: :unavailable", fn ->
      RunnerCache.reconcile()
    end

    assert server_regions(existing) == ["scw-fr-par-runners"]
    assert server_regions(candidate) == []
  end

  test "tears down an account's node when runner access is removed" do
    account = account_running_jobs([:macos])
    set_runner_availability([account.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["scw-fr-par-runners"]

    set_runner_availability([])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == []
  end

  test "tears down a region's node once the account stops running jobs on its served platforms" do
    account = account_running_jobs([:linux, :macos])
    set_runner_availability([account.id])

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["scw-fr-par-runners"]

    age_jobs(account, :macos, 29)

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == ["scw-fr-par-runners"]

    # Once the last macOS job leaves the window, nothing the region serves
    # is in use, so its node is torn down. The recent Linux jobs have no
    # region of their own to keep a node in.
    age_jobs(account, :macos, 31)

    assert :ok = RunnerCache.reconcile()
    assert server_regions(account) == []
  end

  test "accounts with runner access but no claimed job get no node" do
    never_ran = account_running_jobs([])
    unclaimed = account_running_jobs([])
    insert_job(unclaimed, :macos, claimed_at: nil)
    set_runner_availability([never_ran.id, unclaimed.id])

    assert :ok = RunnerCache.reconcile()

    # Both accounts carry the default macOS profile. A job GitHub delivered
    # that no Tuist runner claimed does not count as using runners either.
    assert server_regions(never_ran) == []
    assert server_regions(unclaimed) == []
  end

  test "uses runner availability rather than job history as the entitlement" do
    unavailable = account_running_jobs([:macos])
    enabled = account_running_jobs([:macos])
    set_runner_availability([enabled.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(unavailable) == []
    assert server_regions(enabled) == ["scw-fr-par-runners"]
  end

  test "narrows actor-only production availability before evaluating accounts" do
    unavailable = account_running_jobs([:macos])
    enabled = account_running_jobs([:macos])
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
    account = account_running_jobs([:macos])
    set_runner_availability([account.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(account) == ["scw-fr-par-runners"]
  end

  test "is inert without a runtime image tag except for tear-downs" do
    account = account_running_jobs([:linux, :macos])
    set_runner_availability([account.id])
    assert :ok = RunnerCache.reconcile()

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)
    age_jobs(account, :linux, 31)
    age_jobs(account, :macos, 31)
    fresh = account_running_jobs([:macos])
    set_runner_availability([account.id, fresh.id])

    assert :ok = RunnerCache.reconcile()

    # No new node for the fresh account (no image tag to provision
    # with), but the idle account's nodes are still freed.
    assert server_regions(fresh) == []
    assert server_regions(account) == []
  end

  test "provisions every eligible account outside production and canary" do
    first = account_running_jobs([:macos])
    second = account_running_jobs([:macos])
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
    enabled = account_running_jobs([:macos])
    other = account_running_jobs([:macos])
    stub(Tuist.Environment, :env, fn -> :can end)
    set_runner_availability([enabled.id])

    assert :ok = RunnerCache.reconcile()

    assert server_regions(enabled) == ["scw-fr-par-runners"]
    assert server_regions(other) == []
  end

  test "bounds unsettled servers per region and refills slots as servers become active" do
    accounts = Enum.map(1..12, fn _index -> account_running_jobs([:macos]) end)
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
    accounts = Enum.map(1..11, fn _index -> account_running_jobs([:macos]) end)
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
    accounts = Enum.map(1..12, fn _index -> account_running_jobs([:macos]) end)

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
        account = account_running_jobs([:macos])
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
    enabled = account_running_jobs([:macos])
    other = account_running_jobs([:macos])
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
    account = account_running_jobs([:macos])
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
    account = account_running_jobs([:macos])
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
    account = account_running_jobs([:macos])
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
