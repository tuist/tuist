Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261016130000_move_xcode_27_1_rc_runner_profiles_to_stable.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.MoveXcode271RcRunnerProfilesToStableTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Repo.Migrations.MoveXcode271RcRunnerProfilesToStable
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Profile
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @prefix "tuist-tuist-runner-pool-macos"

  setup do
    account = AccountsFixtures.account_fixture()

    stub(Environment, :runners_macos_pool_name_prefix, fn -> @prefix end)

    stub(Environment, :runners_site_pools, fn ->
      Map.new(
        for version <- ["27-1-rc", "27-1"], suffix <- ["", "-12vcpu-28gb"] do
          {"#{@prefix}-ber1-#{version}#{suffix}", %{site: "ber1", platform: :macos}}
        end
      )
    end)

    %{account: account}
  end

  test "preserves protected and custom profiles' identity, shape and cache writer policy", %{
    account: account
  } do
    other_account = AccountsFixtures.account_fixture()

    profiles = [
      profile(account,
        protected: true,
        cache_writer_default_branch: false,
        cache_writer_branches: ["release/*"]
      ),
      profile(other_account, vcpus: 12, memory_gb: 28)
    ]

    untouched =
      for attrs <- [
            [xcode_version: "27.1"],
            [xcode_version: "26.6", protected: true],
            [xcode_version: "27.2-beta"],
            [xcode_version: "27.1-rc-2"],
            [platform: :linux]
          ],
          do: profile(account, attrs)

    assert %{num_rows: 2} = migrate_profiles()
    assert %{num_rows: 0} = migrate_profiles()

    for original <- profiles do
      migrated = reload(original)
      assert migrated.xcode_version == "27.1"
      assert DateTime.after?(migrated.updated_at, original.updated_at)
      assert_only_changed(original, migrated, [:xcode_version, :updated_at])
    end

    for original <- untouched, do: assert(reload(original) == original)
  end

  test "rewritten rented and rack fleets match the migrated profile's catalog names", %{
    account: account
  } do
    pairs =
      for {shape, suffix} <- [{[vcpus: 6, memory_gb: 14], ""}, {[vcpus: 12, memory_gb: 28], "-12vcpu-28gb"}],
          placement <- [:rented, :rack] do
        original = profile(account, shape)
        job = job(account, pool_name(original, placement))
        site = if placement == :rack, do: "-ber1", else: ""
        assert job.fleet_name == "#{@prefix}#{site}-27-1-rc#{suffix}"
        {original, job, placement}
      end

    assert %{num_rows: 4} = migrate_profiles()
    assert %{num_rows: 4} = migrate_jobs()
    assert %{num_rows: 0} = migrate_jobs()

    for {original, job, placement} <- pairs do
      migrated = reload(job)
      assert migrated.fleet_name == pool_name(reload(original), placement)
      assert_only_changed(job, migrated, [:fleet_name, :updated_at])
    end
  end

  test "leaves non-RC fleets, other platforms and other RC channels alone", %{account: account} do
    jobs =
      for fleet <- ["#{@prefix}-26-6", "#{@prefix}-27-1", "#{@prefix}-27-1-rc-2", "linux-27-1-rc"],
          do: job(account, fleet)

    assert %{num_rows: 0} = migrate_jobs()
    for original <- jobs, do: assert(reload(original) == original)
  end

  test "does not rewrite claimed, running, completed or executing-elsewhere jobs", %{
    account: account
  } do
    fleet = "#{@prefix}-27-1-rc"
    reserved = job(account, fleet)
    executing = job(account, fleet)
    claim(account, reserved, executed_workflow_job_id: executing.workflow_job_id)
    displaced = job(account, fleet)
    claim(account, displaced, workflow_job_id: nil, executed_workflow_job_id: displaced.workflow_job_id)

    historical =
      for status <- ["claimed", "running", "completed", "cancelled"],
          do: job(account, fleet, status: status)

    assert %{num_rows: 0} = migrate_jobs()
    for original <- [reserved, executing, displaced | historical], do: assert(reload(original) == original)
  end

  test "reconciliation catches late RC saves and work requeued after claims release", %{
    account: account
  } do
    original = profile(account)
    queued = job(account, "#{@prefix}-ber1-27-1-rc-12vcpu-28gb", status: "claimed")
    held = claim(account, queued)

    assert %{num_rows: 1} = migrate_profiles()
    assert %{num_rows: 0} = migrate_jobs()

    late = profile(account)
    # excellent_migrations:safety-assured-for-next-line operation_delete
    Repo.delete!(held)
    assert :ok = WorkflowJobs.requeue(queued.workflow_job_id)

    assert %{num_rows: 1} = migrate_profiles()
    assert %{num_rows: 1} = migrate_jobs()
    assert reload(original).xcode_version == "27.1"
    assert reload(late).xcode_version == "27.1"
    assert reload(queued).fleet_name == "#{@prefix}-ber1-27-1-12vcpu-28gb"
    assert %{num_rows: 0} = migrate_profiles()
    assert %{num_rows: 0} = migrate_jobs()
  end

  test "rollback does not restore a retired RC pin" do
    assert :ok = MoveXcode271RcRunnerProfilesToStable.down()
  end

  defp profile(account, attrs \\ []) do
    attrs =
      Map.merge(
        %{
          account_id: account.id,
          name: "retire-#{System.unique_integer([:positive])}",
          platform: :macos,
          xcode_version: "27.1-rc",
          vcpus: 6,
          memory_gb: 14,
          updated_at: ~U[2026-10-01 00:00:00Z]
        },
        Map.new(attrs)
      )

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(struct!(Profile, attrs))
  end

  defp job(account, fleet, attrs \\ []) do
    attrs =
      Map.merge(
        %{
          workflow_job_id: System.unique_integer([:positive]),
          account_id: account.id,
          fleet_name: fleet,
          status: "queued",
          platform: "macos",
          enqueued_at: DateTime.utc_now(),
          updated_at: ~U[2026-10-01 00:00:00Z]
        },
        Map.new(attrs)
      )

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(struct!(WorkflowJob, attrs))
  end

  defp claim(account, job, attrs \\ []) do
    attrs =
      Map.merge(
        %{
          pod_name: "retire-#{job.workflow_job_id}",
          account_id: account.id,
          workflow_job_id: job.workflow_job_id,
          fleet_name: job.fleet_name,
          claimed_at: DateTime.utc_now(),
          platform: :macos,
          vcpus: 6,
          memory_gb: 14
        },
        Map.new(attrs)
      )

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(struct!(Claim, attrs))
  end

  # excellent_migrations:safety-assured-for-next-line operation_query
  defp migrate_profiles, do: Repo.query!(MoveXcode271RcRunnerProfilesToStable.profile_statement())

  # excellent_migrations:safety-assured-for-next-line operation_query
  defp migrate_jobs, do: Repo.query!(MoveXcode271RcRunnerProfilesToStable.queued_jobs_statement())

  # excellent_migrations:safety-assured-for-next-line operation_get
  defp reload(%module{} = row), do: Repo.get!(module, row |> Ecto.primary_key!() |> Keyword.values() |> hd())

  defp pool_name(profile, :rented), do: Catalog.pool_name(profile)
  defp pool_name(profile, :rack), do: Catalog.site_pool_name(profile)

  defp assert_only_changed(original, migrated, keys) do
    assert Map.drop(Map.from_struct(original), keys) == Map.drop(Map.from_struct(migrated), keys)
  end
end
