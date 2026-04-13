defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.RunnersFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  describe "create_runner_configuration/1" do
    test "creates a runner configuration" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, config} =
        Runners.create_runner_configuration(%{
          account_id: user.account.id,
          default_tart_image: "ghcr.io/tuist/runner-macos-15:latest"
        })

      assert config.account_id == user.account.id
      assert config.enabled == false
      assert config.provisioning_mode == :managed
      assert config.default_tart_image == "ghcr.io/tuist/runner-macos-15:latest"
      assert config.max_concurrent_jobs == 5
      assert config.label_prefix == "tuist-runner"
    end

    test "enforces unique account_id" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      {:ok, _} =
        Runners.create_runner_configuration(%{
          account_id: user.account.id,
          default_tart_image: "ghcr.io/tuist/runner-macos-15:latest"
        })

      {:error, changeset} =
        Runners.create_runner_configuration(%{
          account_id: user.account.id,
          default_tart_image: "ghcr.io/tuist/runner-macos-15:latest"
        })

      assert "has already been taken" in errors_on(changeset).account_id
    end
  end

  describe "get_runner_configuration_for_account/1" do
    test "returns configuration when it exists" do
      config = RunnersFixtures.runner_configuration_fixture()
      {:ok, found} = Runners.get_runner_configuration_for_account(config.account_id)
      assert found.id == config.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Runners.get_runner_configuration_for_account(0)
    end
  end

  describe "get_runner_configuration_by_installation_id/1" do
    test "returns configuration linked via GitHub App installation" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      installation = VCSFixtures.github_app_installation_fixture(account_id: user.account.id)
      config = RunnersFixtures.runner_configuration_fixture(account_id: user.account.id)

      {:ok, found} = Runners.get_runner_configuration_by_installation_id(installation.installation_id)
      assert found.id == config.id
    end

    test "returns error when configuration is disabled" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      installation = VCSFixtures.github_app_installation_fixture(account_id: user.account.id)
      RunnersFixtures.runner_configuration_fixture(account_id: user.account.id, enabled: false)

      assert {:error, :not_found} =
               Runners.get_runner_configuration_by_installation_id(installation.installation_id)
    end

    test "returns error when no installation exists" do
      assert {:error, :not_found} = Runners.get_runner_configuration_by_installation_id("nonexistent")
    end
  end

  describe "create_runner_job/1" do
    test "creates a runner job" do
      config = RunnersFixtures.runner_configuration_fixture()

      {:ok, job} =
        Runners.create_runner_job(%{
          runner_configuration_id: config.id,
          account_id: config.account_id,
          github_workflow_job_id: 12_345,
          github_run_id: 67_890,
          github_repository_full_name: "tuist/tuist",
          labels: ["tuist-runner", "macos"]
        })

      assert job.status == :queued
      assert job.github_workflow_job_id == 12_345
      assert job.github_repository_full_name == "tuist/tuist"
      assert job.labels == ["tuist-runner", "macos"]
    end

    test "enforces unique github_workflow_job_id" do
      config = RunnersFixtures.runner_configuration_fixture()

      {:ok, _} =
        Runners.create_runner_job(%{
          runner_configuration_id: config.id,
          account_id: config.account_id,
          github_workflow_job_id: 12_345,
          github_repository_full_name: "tuist/tuist"
        })

      {:error, changeset} =
        Runners.create_runner_job(%{
          runner_configuration_id: config.id,
          account_id: config.account_id,
          github_workflow_job_id: 12_345,
          github_repository_full_name: "tuist/tuist"
        })

      assert "has already been taken" in errors_on(changeset).github_workflow_job_id
    end
  end

  describe "update_runner_job/2" do
    test "allows valid status transitions" do
      job = RunnersFixtures.runner_job_fixture()
      assert job.status == :queued

      {:ok, job} = Runners.update_runner_job(job, %{status: :provisioning})
      assert job.status == :provisioning

      {:ok, job} = Runners.update_runner_job(job, %{status: :in_progress})
      assert job.status == :in_progress

      {:ok, job} = Runners.update_runner_job(job, %{status: :completed, conclusion: "success"})
      assert job.status == :completed
      assert job.conclusion == "success"
    end

    test "rejects invalid status transitions" do
      job = RunnersFixtures.runner_job_fixture()

      {:ok, completed_job} =
        Runners.update_runner_job(job, %{status: :provisioning})

      {:ok, completed_job} =
        Runners.update_runner_job(completed_job, %{status: :completed})

      {:error, changeset} = Runners.update_runner_job(completed_job, %{status: :queued})
      assert "cannot transition from completed to queued" in errors_on(changeset).status
    end
  end

  describe "get_runner_job_by_github_id/1" do
    test "returns job when found" do
      job = RunnersFixtures.runner_job_fixture()
      {:ok, found} = Runners.get_runner_job_by_github_id(job.github_workflow_job_id)
      assert found.id == job.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Runners.get_runner_job_by_github_id(999_999)
    end
  end

  describe "labels_match?/2" do
    test "returns true when a label matches the prefix" do
      assert Runners.labels_match?(["tuist-runner", "macos"], "tuist-runner")
      assert Runners.labels_match?(["tuist-runner-macos-15"], "tuist-runner")
    end

    test "returns false when no label matches" do
      refute Runners.labels_match?(["self-hosted", "macos"], "tuist-runner")
      refute Runners.labels_match?([], "tuist-runner")
    end
  end

  describe "count_active_jobs/1" do
    test "counts jobs in active statuses" do
      config = RunnersFixtures.runner_configuration_fixture()

      RunnersFixtures.runner_job_fixture(runner_configuration: config)
      RunnersFixtures.runner_job_fixture(runner_configuration: config)

      assert Runners.count_active_jobs(config.id) == 2
    end
  end
end
