defmodule Tuist.Bundles.Workers.BundleThresholdWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Bundles.Workers.BundleThresholdWorker
  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(DateTime, :utc_now, fn -> ~U[2024-08-10 02:00:00Z] end)
    :ok
  end

  describe "perform/1" do
    test "skips when bundle has no git_commit_sha" do
      project = ProjectsFixtures.project_fixture()

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_commit_sha: nil,
          git_ref: nil
        )

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => nil
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "skips when bundle git_ref is not a PR ref" do
      project = ProjectsFixtures.project_fixture()

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_commit_sha: "abc123",
          git_ref: "refs/heads/main"
        )

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "skips when project has no VCS connection" do
      project = ProjectsFixtures.project_fixture()

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_commit_sha: "abc123",
          git_ref: "refs/pull/1/merge"
        )

      stub(Environment, :github_app_configured?, fn -> true end)
      reject(&Client.create_check_run/1)

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "skips when no thresholds configured" do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          git_commit_sha: "abc123",
          git_ref: "refs/pull/1/merge"
        )

      stub(Environment, :github_app_configured?, fn -> true end)
      reject(&Client.create_check_run/1)

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "creates success check run when within threshold" do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      BundlesFixtures.bundle_threshold_fixture(
        project: project,
        deviation_percentage: 50.0
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        install_size: 1000,
        git_branch: "main",
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1100,
          git_branch: "feature",
          git_commit_sha: "abc123",
          git_ref: "refs/pull/1/merge",
          inserted_at: ~U[2024-01-02 00:00:00Z]
        )

      stub(Environment, :github_app_configured?, fn -> true end)
      stub(Environment, :app_url, fn -> "https://tuist.dev" end)

      expect(Client, :get_pull_request, fn params ->
        assert params.pr_number == 1
        {:ok, %{"head" => %{"sha" => "real-head-sha"}}}
      end)

      expect(Client, :create_check_run, fn params ->
        assert params.head_sha == "real-head-sha"
        assert params.conclusion == "success"
        assert params.output.title == "Bundle size check passed"
        {:ok, %{"id" => 1}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "creates action_required check run when threshold violated" do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      BundlesFixtures.bundle_threshold_fixture(
        project: project,
        name: "Strict",
        deviation_percentage: 5.0
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        install_size: 1000,
        git_branch: "main",
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1200,
          git_branch: "feature",
          git_commit_sha: "abc123",
          git_ref: "refs/pull/1/merge",
          inserted_at: ~U[2024-01-02 00:00:00Z]
        )

      stub(Environment, :github_app_configured?, fn -> true end)
      stub(Environment, :app_url, fn -> "https://tuist.dev" end)

      expect(Client, :get_pull_request, fn _params ->
        {:ok, %{"head" => %{"sha" => "real-head-sha"}}}
      end)

      expect(Client, :create_check_run, fn params ->
        assert params.head_sha == "real-head-sha"
        assert params.conclusion == "action_required"
        assert params.output.title == "Bundle size threshold exceeded"
        assert params.output.summary =~ "Strict"
        assert length(params.actions) == 1
        assert hd(params.actions).identifier == "accept_bundle_size"
        assert params.external_id == bundle.id
        {:ok, %{"id" => 1}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "reports the configured threshold and the deviation without losing sub-decimal precision" do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      BundlesFixtures.bundle_threshold_fixture(
        project: project,
        name: "Download size PR check",
        metric: :download_size,
        deviation_percentage: 0.15
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        download_size: 100_000,
        git_branch: "main",
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          download_size: 100_170,
          git_branch: "feature",
          git_commit_sha: "abc123",
          git_ref: "refs/pull/1/merge",
          inserted_at: ~U[2024-01-02 00:00:00Z]
        )

      stub(Environment, :github_app_configured?, fn -> true end)
      stub(Environment, :app_url, fn -> "https://tuist.dev" end)

      expect(Client, :get_pull_request, fn _params ->
        {:ok, %{"head" => %{"sha" => "real-head-sha"}}}
      end)

      expect(Client, :create_check_run, fn params ->
        assert params.conclusion == "action_required"
        assert params.output.summary =~ "**Threshold:** 0.15%"
        assert params.output.summary =~ "+0.17%"
        {:ok, %{"id" => 1}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "reports violation when first threshold passes but second violates" do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      BundlesFixtures.bundle_threshold_fixture(
        project: project,
        name: "Lenient",
        deviation_percentage: 50.0
      )

      BundlesFixtures.bundle_threshold_fixture(
        project: project,
        name: "Strict",
        deviation_percentage: 5.0
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        install_size: 1000,
        git_branch: "main",
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1200,
          git_branch: "feature",
          git_commit_sha: "abc123",
          git_ref: "refs/pull/1/merge",
          inserted_at: ~U[2024-01-02 00:00:00Z]
        )

      stub(Environment, :github_app_configured?, fn -> true end)
      stub(Environment, :app_url, fn -> "https://tuist.dev" end)

      expect(Client, :get_pull_request, fn _params ->
        {:ok, %{"head" => %{"sha" => "real-head-sha"}}}
      end)

      expect(Client, :create_check_run, fn params ->
        assert params.conclusion == "action_required"
        assert params.output.summary =~ "Strict"
        {:ok, %{"id" => 1}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "bundle_id" => bundle.id,
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "evaluates the bundle carried in the job args without reading it back" do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      BundlesFixtures.bundle_threshold_fixture(
        project: project,
        name: "Strict",
        deviation_percentage: 5.0
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        name: "App",
        install_size: 1000,
        git_branch: "main",
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )

      stub(Environment, :github_app_configured?, fn -> true end)
      stub(Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Client, :get_pull_request, fn _params ->
        {:ok, %{"head" => %{"sha" => "real-head-sha"}}}
      end)

      expect(Client, :create_check_run, fn params ->
        assert params.conclusion == "action_required"
        assert params.output.summary =~ "Strict"
        {:ok, %{"id" => 1}}
      end)

      job = %Oban.Job{
        id: 1,
        attempt: 1,
        args: %{
          "bundle_id" => UUIDv7.generate(),
          "project_id" => project.id,
          "git_commit_sha" => "abc123",
          "bundle_name" => "App",
          "git_ref" => "refs/pull/1/merge",
          "install_size" => 1200,
          "download_size" => nil
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "skips when the bundle carried in the job args is not on a PR ref" do
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "org/repo",
            provider: :github
          ]
        )

      stub(Environment, :github_app_configured?, fn -> true end)
      reject(&Client.create_check_run/1)

      job = %Oban.Job{
        id: 1,
        attempt: 1,
        args: %{
          "bundle_id" => UUIDv7.generate(),
          "project_id" => project.id,
          "git_commit_sha" => "abc123",
          "bundle_name" => "App",
          "git_ref" => "refs/heads/main",
          "install_size" => 1200,
          "download_size" => nil
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end

    test "snoozes when the bundle is not visible yet" do
      project = ProjectsFixtures.project_fixture()

      stub(Environment, :github_app_configured?, fn -> true end)
      reject(&Client.create_check_run/1)

      job = %Oban.Job{
        id: 1,
        attempt: 1,
        args: %{
          "bundle_id" => UUIDv7.generate(),
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert {:snooze, _} = BundleThresholdWorker.perform(job)
    end

    test "stops snoozing when the bundle is still not visible on the last attempt" do
      project = ProjectsFixtures.project_fixture()

      stub(Environment, :github_app_configured?, fn -> true end)
      reject(&Client.create_check_run/1)

      job = %Oban.Job{
        id: 1,
        attempt: 5,
        args: %{
          "bundle_id" => UUIDv7.generate(),
          "project_id" => project.id,
          "git_commit_sha" => "abc123"
        }
      }

      assert :ok == BundleThresholdWorker.perform(job)
    end
  end
end
