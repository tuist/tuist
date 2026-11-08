Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261106180000_reshape_macos_runner_shapes_to_rack_guests.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.ReshapeMacosRunnerShapesToRackGuestsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Repo.Migrations.ReshapeMacosRunnerShapesToRackGuests, as: Migration
  alias Tuist.Runners.Claim
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.Profile
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @prefix "tuist-tuist-runner-pool-macos"

  test "moves macOS profiles to the new shapes and leaves others alone" do
    account = AccountsFixtures.account_fixture()

    default = profile(account, vcpus: 6, memory_gb: 14)
    large = profile(account, vcpus: 12, memory_gb: 28)
    linux = profile(account, platform: :linux, xcode_version: nil, os_version: "ubuntu-24.04", vcpus: 6, memory_gb: 14)
    moved = profile(account, vcpus: 8, memory_gb: 24)

    assert %{num_rows: 2} = run(Migration.profile_statement())
    assert %{num_rows: 0} = run(Migration.profile_statement())

    assert {8, 24} == shape(default)
    assert {16, 48} == shape(large)
    assert {6, 14} == shape(linux)
    assert {8, 24} == shape(moved)
  end

  test "scales macOS concurrency limits to admit as many jobs as before" do
    account = AccountsFixtures.account_fixture()
    other = AccountsFixtures.account_fixture()
    set_limit(account, :macos, 12, 28)
    set_limit(other, :macos, 30, 70)
    set_limit(other, :linux, 12, 28)

    run(Migration.limits_statement())

    assert {16, 48} == limit_of(account, "macos")
    assert {40, 120} == limit_of(other, "macos")
    assert {12, 28} == limit_of(other, "linux")
  end

  test "new accounts get the new default macOS limit from the database trigger" do
    account = AccountsFixtures.account_fixture()

    assert {16, 48} == limit_of(account, "macos")
  end

  test "renames queued jobs on the larger shape's pools and strips the old replicas' default-shape suffix" do
    account = AccountsFixtures.account_fixture()

    large = job(account, "#{@prefix}-ber1-27-0-12vcpu-28gb")
    stray = job(account, "#{@prefix}-ber1-27-0-8vcpu-24gb")
    default = job(account, "#{@prefix}-ber1-27-0")
    running = job(account, "#{@prefix}-ber1-27-1-12vcpu-28gb", status: "in_progress")
    claimed = job(account, "#{@prefix}-ber1-27-2-12vcpu-28gb")
    claim(account, claimed)
    linux = job(account, "tuist-tuist-runner-pool-linux-12vcpu-28gb", platform: "linux")

    assert %{num_rows: 2} = run(Migration.queued_jobs_statement())

    assert "#{@prefix}-ber1-27-0-16vcpu-48gb" == fleet(large)
    assert "#{@prefix}-ber1-27-0" == fleet(stray)
    assert "#{@prefix}-ber1-27-0" == fleet(default)
    assert "#{@prefix}-ber1-27-1-12vcpu-28gb" == fleet(running)
    assert "#{@prefix}-ber1-27-2-12vcpu-28gb" == fleet(claimed)
    assert "tuist-tuist-runner-pool-linux-12vcpu-28gb" == fleet(linux)
  end

  defp profile(account, attrs) do
    attrs =
      Map.merge(
        %{
          account_id: account.id,
          name: "reshape-#{System.unique_integer([:positive])}",
          platform: :macos,
          xcode_version: "27.0"
        },
        Map.new(attrs)
      )

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(struct!(Profile, attrs))
  end

  # excellent_migrations:safety-assured-for-next-line operation_query
  defp run(statement), do: Repo.query!(statement)

  defp set_limit(account, platform, vcpus, memory_gb) do
    ConcurrencyLimit
    |> where([l], l.account_id == ^account.id and l.platform == ^to_string(platform))
    # excellent_migrations:safety-assured-for-next-line operation_update
    |> Repo.update_all(set: [vcpus: vcpus, memory_gb: memory_gb])
  end

  defp limit_of(account, platform) do
    ConcurrencyLimit
    |> where([l], l.account_id == ^account.id and l.platform == ^platform)
    |> select([l], {l.vcpus, l.memory_gb})
    # excellent_migrations:safety-assured-for-next-line operation_one
    |> Repo.one!()
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
          enqueued_at: DateTime.utc_now()
        },
        Map.new(attrs)
      )

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(struct!(WorkflowJob, attrs))
  end

  defp claim(account, job) do
    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(%Claim{
      pod_name: "reshape-#{job.workflow_job_id}",
      account_id: account.id,
      workflow_job_id: job.workflow_job_id,
      fleet_name: job.fleet_name,
      claimed_at: DateTime.utc_now(),
      platform: :macos,
      vcpus: 16,
      memory_gb: 48
    })
  end

  defp shape(profile) do
    # excellent_migrations:safety-assured-for-next-line operation_get
    reloaded = Repo.get!(Profile, profile.id)
    {reloaded.vcpus, reloaded.memory_gb}
  end

  # excellent_migrations:safety-assured-for-next-line operation_get_by
  defp fleet(job), do: Repo.get_by!(WorkflowJob, workflow_job_id: job.workflow_job_id).fleet_name
end
