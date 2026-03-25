defmodule Tuist.Tests.ExpireStaleTestRunsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "expire_stale_in_progress_test_runs/0" do
    test "marks stale in_progress test runs as failure" do
      project = ProjectsFixtures.project_fixture()
      seven_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7, :hour)

      stale_id = UUIDv7.generate()

      IngestRepo.insert_all(Test, [
        %{
          id: stale_id,
          project_id: project.id,
          account_id: project.account.id,
          duration: 0,
          status: "in_progress",
          model_identifier: "",
          macos_version: "",
          xcode_version: "",
          git_branch: "main",
          git_commit_sha: "",
          git_ref: "",
          ran_at: seven_hours_ago,
          is_ci: true,
          is_flaky: false,
          shard_plan_id: Ecto.UUID.generate(),
          inserted_at: seven_hours_ago
        }
      ])

      {:ok, count} = Tests.expire_stale_in_progress_test_runs()

      assert count >= 1
    end

    test "does not affect recent in_progress test runs" do
      project = ProjectsFixtures.project_fixture()
      one_hour_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :hour)

      recent_id = UUIDv7.generate()

      IngestRepo.insert_all(Test, [
        %{
          id: recent_id,
          project_id: project.id,
          account_id: project.account.id,
          duration: 0,
          status: "in_progress",
          model_identifier: "",
          macos_version: "",
          xcode_version: "",
          git_branch: "main",
          git_commit_sha: "",
          git_ref: "",
          ran_at: one_hour_ago,
          is_ci: true,
          is_flaky: false,
          shard_plan_id: Ecto.UUID.generate(),
          inserted_at: one_hour_ago
        }
      ])

      {:ok, _} = Tests.expire_stale_in_progress_test_runs()

      [run] =
        IngestRepo.all(from(t in Test, hints: ["FINAL"], where: t.id == ^recent_id))

      assert run.status == "in_progress"
    end

    test "does not affect completed test runs" do
      project = ProjectsFixtures.project_fixture()
      seven_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7, :hour)

      completed_id = UUIDv7.generate()

      IngestRepo.insert_all(Test, [
        %{
          id: completed_id,
          project_id: project.id,
          account_id: project.account.id,
          duration: 5000,
          status: "success",
          model_identifier: "",
          macos_version: "",
          xcode_version: "",
          git_branch: "main",
          git_commit_sha: "",
          git_ref: "",
          ran_at: seven_hours_ago,
          is_ci: true,
          is_flaky: false,
          inserted_at: seven_hours_ago
        }
      ])

      {:ok, _} = Tests.expire_stale_in_progress_test_runs()

      [run] =
        IngestRepo.all(from(t in Test, hints: ["FINAL"], where: t.id == ^completed_id))

      assert run.status == "success"
    end
  end
end
