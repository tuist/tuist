defmodule Tuist.Atlas.ArtifactsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Atlas.Artifacts
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    project = ProjectsFixtures.project_fixture(name: "acme-app")

    stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 1024} end)
    stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://storage.test/signed" end)

    %{project: project, handle: project.account.name}
  end

  describe "presign/3" do
    test "resolves a remote-processed test run's result bundle", %{project: project, handle: handle} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      assert {:ok, artifact} = Artifacts.presign("test_run_result_bundle", test_run.id)

      assert artifact.object_key == "#{handle}/acme-app/runs/#{test_run.id}/result_bundle.zip"
      assert artifact.account_handle == handle
      assert artifact.project_handle == "acme-app"
      assert artifact.byte_size == 1024
      assert artifact.download_url == "https://storage.test/signed"
    end

    test "resolves a test run's session archive", %{project: project, handle: handle} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      assert {:ok, artifact} = Artifacts.presign("test_run_session", test_run.id)

      assert artifact.object_key == "#{handle}/acme-app/runs/#{test_run.id}/session.zip"
    end

    # Older `tuist test` runs have no row in `test_runs`; their bundle is stored
    # under the command event id instead.
    test "falls back to a command event when the id is not a test run", %{project: project, handle: handle} do
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test")

      assert {:ok, artifact} = Artifacts.presign("test_run_result_bundle", command_event.id)

      assert artifact.object_key == "#{handle}/acme-app/runs/#{command_event.id}/result_bundle.zip"
    end

    test "resolves a test case run attachment", %{project: project, handle: handle} do
      test_case_run = RunsFixtures.test_case_run_fixture(project_id: project.id)

      attachment =
        RunsFixtures.test_case_run_attachment_fixture(
          test_case_run_id: test_case_run.id,
          test_run_id: test_case_run.test_run_id,
          file_name: "crash-report.ips"
        )

      assert {:ok, artifact} = Artifacts.presign("test_case_run_attachment", attachment.id)

      assert artifact.object_key ==
               "#{handle}/acme-app/tests/runs/#{test_case_run.test_run_id}/attachments/#{attachment.id}/crash-report.ips"
    end

    test "resolves a legacy attachment stored without a test run id", %{project: project, handle: handle} do
      test_case_run = RunsFixtures.test_case_run_fixture(project_id: project.id)

      attachment =
        RunsFixtures.test_case_run_attachment_fixture(
          test_case_run_id: test_case_run.id,
          test_run_id: nil,
          file_name: "screenshot.png"
        )

      assert {:ok, artifact} = Artifacts.presign("test_case_run_attachment", attachment.id)

      assert artifact.object_key ==
               "#{handle}/acme-app/tests/test-case-runs/#{test_case_run.id}/attachments/#{attachment.id}/screenshot.png"
    end

    test "resolves a build run's archive", %{project: project, handle: handle} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)

      assert {:ok, artifact} = Artifacts.presign("build_archive", build.id)

      assert artifact.object_key == "#{handle}/acme-app/builds/#{String.downcase(build.id)}/build.zip"
    end

    test "resolves a preview app build", %{project: project, handle: handle} do
      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      assert {:ok, artifact} = Artifacts.presign("preview_app_build", app_build.id)

      assert artifact.object_key == "#{handle}/acme-app/previews/#{app_build.id}.zip"
    end

    test "signs the URL for the configured lifetime, clamped to an hour", %{project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      expect(Storage, :generate_download_url, fn _object_key, _actor, opts ->
        assert Keyword.fetch!(opts, :expires_in) == 3600
        "https://storage.test/signed"
      end)

      assert {:ok, artifact} = Artifacts.presign("test_run_result_bundle", test_run.id, expires_in: 86_400)

      assert DateTime.diff(artifact.expires_at, DateTime.utc_now()) in 3595..3600
    end

    test "reports an unknown kind" do
      assert {:error, :unknown_kind} = Artifacts.presign("crash_dump", UUIDv7.generate())
    end

    test "reports a record that does not exist" do
      assert {:error, :not_found} = Artifacts.presign("test_run_result_bundle", UUIDv7.generate())
      assert {:error, :not_found} = Artifacts.presign("build_archive", UUIDv7.generate())
      assert {:error, :not_found} = Artifacts.presign("preview_app_build", UUIDv7.generate())
    end

    test "reports a malformed attachment id without raising" do
      assert {:error, :not_found} = Artifacts.presign("test_case_run_attachment", "not-a-uuid")
    end

    # The row outliving its artifact is the common escalation shape: the run is
    # in the dashboard but the bundle was never uploaded or has been pruned.
    test "distinguishes a stored record from a missing object", %{project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :not_found} end)

      assert {:error, :object_not_found} = Artifacts.presign("test_run_result_bundle", test_run.id)
    end

    test "reports storage failures separately from a missing object", %{project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :timeout} end)

      assert {:error, :storage_unavailable} = Artifacts.presign("test_run_result_bundle", test_run.id)
    end
  end
end
