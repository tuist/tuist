defmodule Tuist.Storage.Workers.DeleteExpiredArtifactWorkersTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AppBuildsFixtures
  import TuistTestSupport.Fixtures.BillingFixtures
  import TuistTestSupport.Fixtures.ProjectsFixtures
  import TuistTestSupport.Fixtures.RunsFixtures
  import TuistTestSupport.Fixtures.ShardsFixtures

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.Builds
  alias Tuist.Repo
  alias Tuist.Shards
  alias Tuist.Storage
  alias Tuist.Storage.ArtifactRetentionCursor
  alias Tuist.Storage.Workers.DeleteExpiredBuildArchivesWorker
  alias Tuist.Storage.Workers.DeleteExpiredPreviewArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredShardBundlesWorker
  alias Tuist.Storage.Workers.DeleteExpiredTestAttachmentsWorker
  alias Tuist.Tests

  describe "perform/1" do
    test "the preview worker deletes expired previews according to the account plan" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      expired_app_build =
        app_build_fixture(
          preview: preview_fixture(project: project),
          inserted_at: DateTime.add(DateTime.utc_now(), -61, :day)
        )

      app_build_fixture(
        preview: preview_fixture(project: project),
        inserted_at: DateTime.add(DateTime.utc_now(), -59, :day)
      )

      expired_app_build_key =
        AppBuilds.storage_key(%{account_handle: account.name, project_handle: project.name, app_build: expired_app_build})

      expired_icon_key =
        AppBuilds.icon_storage_key(%{
          account_handle: account.name,
          project_handle: project.name,
          preview_id: expired_app_build.preview_id
        })

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredPreviewArtifactsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, object_keys}
      assert expired_app_build_key in object_keys
      assert expired_icon_key in object_keys
    end

    test "the preview worker persists progress across scheduled runs" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      expired_app_build =
        app_build_fixture(
          preview: preview_fixture(project: project),
          inserted_at: DateTime.add(DateTime.utc_now(), -61, :day)
        )

      expired_app_build_key =
        AppBuilds.storage_key(%{account_handle: account.name, project_handle: project.name, app_build: expired_app_build})

      expired_app_build_id = expired_app_build.id

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredPreviewArtifactsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, first_keys}
      assert expired_app_build_key in first_keys

      assert %ArtifactRetentionCursor{
               artifact_type: :preview_app_build,
               after_id: ^expired_app_build_id
             } = Repo.get_by(ArtifactRetentionCursor, account_id: account.id, artifact_type: :preview_app_build)

      assert :ok =
               perform_job(DeleteExpiredPreviewArtifactsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, second_keys}
      assert second_keys == []
    end

    test "a full batch self-enqueues the next page and the cursor advances past the oldest rows" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      older =
        app_build_fixture(
          preview: preview_fixture(project: project),
          inserted_at: DateTime.add(DateTime.utc_now(), -63, :day)
        )

      newer =
        app_build_fixture(
          preview: preview_fixture(project: project),
          inserted_at: DateTime.add(DateTime.utc_now(), -62, :day)
        )

      older_key =
        AppBuilds.storage_key(%{account_handle: account.name, project_handle: project.name, app_build: older})

      newer_key =
        AppBuilds.storage_key(%{account_handle: account.name, project_handle: project.name, app_build: newer})

      stub(Storage, :delete_objects, fn object_keys, _account ->
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredPreviewArtifactsWorker, %{"account_id" => account.id, "batch_size" => 1})

      assert_received {:deleted, first_keys}
      assert older_key in first_keys
      refute newer_key in first_keys

      assert_enqueued(
        worker: DeleteExpiredPreviewArtifactsWorker,
        args: %{"account_id" => account.id, "batch_size" => 1, "after_id" => older.id}
      )

      cursor_inserted_at = Repo.get(AppBuild, older.id).inserted_at

      assert :ok =
               perform_job(DeleteExpiredPreviewArtifactsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 1,
                 "after_inserted_at" => DateTime.to_iso8601(cursor_inserted_at),
                 "after_id" => older.id
               })

      assert_received {:deleted, second_keys}
      assert newer_key in second_keys
      refute older_key in second_keys
    end

    test "a stale worker page does not move the persisted cursor backwards" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      older =
        app_build_fixture(
          preview: preview_fixture(project: project),
          inserted_at: DateTime.add(DateTime.utc_now(), -63, :day)
        )

      newer =
        app_build_fixture(
          preview: preview_fixture(project: project),
          inserted_at: DateTime.add(DateTime.utc_now(), -62, :day)
        )

      older_inserted_at = Repo.get(AppBuild, older.id).inserted_at
      newer_inserted_at = Repo.get(AppBuild, newer.id).inserted_at

      %ArtifactRetentionCursor{}
      |> ArtifactRetentionCursor.changeset(%{
        account_id: account.id,
        artifact_type: :preview_app_build,
        after_inserted_at: newer_inserted_at,
        after_id: newer.id
      })
      |> Repo.insert!()

      stub(Storage, :delete_objects, fn object_keys, _account ->
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredPreviewArtifactsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 1,
                 "after_inserted_at" => older_inserted_at |> DateTime.add(-1, :second) |> DateTime.to_iso8601(),
                 "after_id" => "00000000-0000-0000-0000-000000000000"
               })

      assert_received {:deleted, _object_keys}

      assert %ArtifactRetentionCursor{
               after_id: after_id,
               after_inserted_at: after_inserted_at
             } = Repo.get_by(ArtifactRetentionCursor, account_id: account.id, artifact_type: :preview_app_build)

      assert after_id == newer.id
      assert DateTime.compare(after_inserted_at, newer_inserted_at) == :eq
    end

    test "the build archive worker deletes expired build archives according to the account plan" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      {:ok, expired_build} =
        build_fixture(
          project_id: project.id,
          account_id: account.id,
          inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)
        )

      {:ok, _recent_build} =
        build_fixture(
          project_id: project.id,
          account_id: account.id,
          inserted_at: DateTime.add(DateTime.utc_now(), -29, :day)
        )

      expired_build_key = Builds.build_storage_key(account.name, project.name, expired_build.id)

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredBuildArchivesWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, object_keys}
      assert expired_build_key in object_keys
    end

    test "the build archive worker uses persisted progress for ClickHouse rows" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      {:ok, expired_build} =
        build_fixture(
          project_id: project.id,
          inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)
        )

      expired_build_key = Builds.build_storage_key(account.name, project.name, expired_build.id)
      expired_build_id = expired_build.id

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredBuildArchivesWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, first_keys}
      assert expired_build_key in first_keys

      assert %ArtifactRetentionCursor{
               artifact_type: :build_archive,
               after_id: ^expired_build_id
             } = Repo.get_by(ArtifactRetentionCursor, account_id: account.id, artifact_type: :build_archive)

      assert :ok =
               perform_job(DeleteExpiredBuildArchivesWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, second_keys}
      assert second_keys == []
    end

    test "the test attachment worker deletes expired test attachments according to the account plan" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      test_run_id = UUIDv7.generate()

      {:ok, expired_test} =
        test_fixture(
          id: test_run_id,
          project_id: project.id,
          account_id: account.id,
          ran_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      expired_test_case_run = List.first(expired_test.test_case_runs)

      expired_attachment =
        test_case_run_attachment_fixture(
          test_case_run_id: expired_test_case_run.id,
          test_run_id: test_run_id,
          file_name: "failure.log",
          inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      test_fixture(
        project_id: project.id,
        account_id: account.id,
        ran_at: DateTime.utc_now() |> DateTime.add(-29, :day) |> DateTime.to_naive()
      )

      expired_attachment_key =
        Tests.attachment_storage_key(%{
          account_handle: account.name,
          project_handle: project.name,
          attachment_id: expired_attachment.id,
          test_case_run_id: expired_test_case_run.id,
          test_run_id: test_run_id,
          file_name: expired_attachment.file_name
        })

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredTestAttachmentsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, object_keys}
      assert expired_attachment_key in object_keys
    end

    test "the test attachment worker deletes legacy attachments without test run ids" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      expired_test_case_run =
        test_case_run_fixture(
          project_id: project.id,
          account_id: account.id,
          inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      expired_attachment =
        test_case_run_attachment_fixture(
          test_case_run_id: expired_test_case_run.id,
          test_run_id: nil,
          file_name: "failure.log",
          inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      expired_attachment_key =
        Tests.attachment_storage_key(%{
          account_handle: account.name,
          project_handle: project.name,
          attachment_id: expired_attachment.id,
          test_case_run_id: expired_test_case_run.id,
          test_run_id: nil,
          file_name: expired_attachment.file_name
        })

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredTestAttachmentsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, object_keys}
      assert expired_attachment_key in object_keys
    end

    test "the shard bundle worker deletes expired shard bundles according to the account plan" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      expired_shard_plan =
        shard_plan_fixture(
          project_id: project.id,
          inserted_at: DateTime.utc_now() |> DateTime.add(-8, :day) |> DateTime.to_naive()
        )

      shard_plan_fixture(
        project_id: project.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-6, :day) |> DateTime.to_naive()
      )

      expired_shard_key = Shards.bundle_object_key(account, project, expired_shard_plan.id)

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredShardBundlesWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, object_keys}
      assert expired_shard_key in object_keys
    end
  end
end
