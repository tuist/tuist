Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20261016090000_move_xcode_27_1_rc_runner_profiles_to_stable.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.MoveXcode271RcRunnerProfilesToStableTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo.Migrations.MoveXcode271RcRunnerProfilesToStable

  setup do
    Repo.query!("""
    CREATE TEMP TABLE runner_profiles (
      id bigint PRIMARY KEY, account_id bigint, name text, platform text,
      xcode_version text, protected boolean, vcpus integer, updated_at timestamp
    ) ON COMMIT DROP
    """)

    Repo.query!("""
    CREATE TEMP TABLE runner_workflow_jobs (
      workflow_job_id bigint PRIMARY KEY, fleet_name text, status text, updated_at timestamp
    ) ON COMMIT DROP
    """)

    Repo.query!("CREATE TEMP TABLE runner_claims (workflow_job_id bigint) ON COMMIT DROP")
    :ok
  end

  test "moves protected and custom RC profiles across accounts without changing other settings" do
    Repo.query!("""
    INSERT INTO runner_profiles VALUES
      (1, 10, 'macos', 'macos', '27.1-rc', true, 6, '2026-10-01'),
      (2, 20, 'custom', 'macos', '27.1-rc', false, 12, '2026-10-01'),
      (3, 10, 'stable', 'macos', '27.1', false, 6, '2026-10-01'),
      (4, 10, 'default', 'macos', '26.6', true, 6, '2026-10-01'),
      (5, 20, 'beta', 'macos', '27.2-beta', false, 6, '2026-10-01'),
      (6, 20, 'linux', 'linux', NULL, true, 2, '2026-10-01')
    """)

    assert %{num_rows: 2} = Repo.query!(MoveXcode271RcRunnerProfilesToStable.profile_statement())
    assert %{num_rows: 0} = Repo.query!(MoveXcode271RcRunnerProfilesToStable.profile_statement())

    assert Repo.query!(
             "SELECT id, account_id, name, xcode_version, protected, vcpus FROM runner_profiles ORDER BY id"
           ).rows ==
             [
               [1, 10, "macos", "27.1", true, 6],
               [2, 20, "custom", "27.1", false, 12],
               [3, 10, "stable", "27.1", false, 6],
               [4, 10, "default", "26.6", true, 6],
               [5, 20, "beta", "27.2-beta", false, 6],
               [6, 20, "linux", nil, true, 2]
             ]

    assert Repo.query!(
             "SELECT id FROM runner_profiles WHERE updated_at > '2026-10-01' ORDER BY id"
           ).rows == [[1], [2]]
  end

  test "moves unclaimed queued jobs while retaining their site and shape" do
    Repo.query!("""
    INSERT INTO runner_workflow_jobs VALUES
      (1, 'tuist-runner-pool-macos-27-1-rc', 'queued', '2026-10-01'),
      (2, 'tuist-runner-pool-macos-27-1-rc-12vcpu-28gb', 'queued', '2026-10-01'),
      (3, 'tuist-runner-pool-macos-ber1-27-1-rc-12vcpu-28gb', 'queued', '2026-10-01'),
      (4, 'tuist-runner-pool-macos-26-6', 'queued', '2026-10-01'),
      (5, 'tuist-runner-pool-macos-27-1-rc-2', 'queued', '2026-10-01')
    """)

    assert %{num_rows: 3} =
             Repo.query!(MoveXcode271RcRunnerProfilesToStable.queued_jobs_statement())

    assert %{num_rows: 0} =
             Repo.query!(MoveXcode271RcRunnerProfilesToStable.queued_jobs_statement())

    assert Repo.query!(
             "SELECT workflow_job_id, fleet_name FROM runner_workflow_jobs ORDER BY workflow_job_id"
           ).rows ==
             [
               [1, "tuist-runner-pool-macos-27-1"],
               [2, "tuist-runner-pool-macos-27-1-12vcpu-28gb"],
               [3, "tuist-runner-pool-macos-ber1-27-1-12vcpu-28gb"],
               [4, "tuist-runner-pool-macos-26-6"],
               [5, "tuist-runner-pool-macos-27-1-rc-2"]
             ]
  end

  test "does not rewrite claimed, running, or historical job attribution" do
    Repo.query!("""
    INSERT INTO runner_workflow_jobs VALUES
      (1, 'tuist-runner-pool-macos-27-1-rc', 'queued', '2026-10-01'),
      (2, 'tuist-runner-pool-macos-27-1-rc', 'claimed', '2026-10-01'),
      (3, 'tuist-runner-pool-macos-27-1-rc', 'running', '2026-10-01'),
      (4, 'tuist-runner-pool-macos-27-1-rc', 'completed', '2026-10-01')
    """)

    Repo.query!("INSERT INTO runner_claims VALUES (1)")

    assert %{num_rows: 0} =
             Repo.query!(MoveXcode271RcRunnerProfilesToStable.queued_jobs_statement())

    assert Repo.query!("SELECT DISTINCT fleet_name FROM runner_workflow_jobs").rows == [
             ["tuist-runner-pool-macos-27-1-rc"]
           ]
  end

  test "rollback does not restore a retired RC pin" do
    assert :ok = MoveXcode271RcRunnerProfilesToStable.down()
  end
end
