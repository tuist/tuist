defmodule Tuist.Storage.Workers.DeleteExpiredArtifactWorkersTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AppBuildsFixtures
  import TuistTestSupport.Fixtures.BillingFixtures
  import TuistTestSupport.Fixtures.CommandEventsFixtures
  import TuistTestSupport.Fixtures.ProjectsFixtures
  import TuistTestSupport.Fixtures.RunsFixtures
  import TuistTestSupport.Fixtures.ShardsFixtures

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.Builds
  alias Tuist.CommandEvents
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Shards
  alias Tuist.Storage
  alias Tuist.Storage.ArtifactRetentionCursor
  alias Tuist.Storage.ExpiredArtifacts
  alias Tuist.Storage.LegacyTestAttachmentRetentionCursor
  alias Tuist.Storage.Workers.DeleteExpiredBuildArchivesWorker
  alias Tuist.Storage.Workers.DeleteExpiredLegacyTestAttachmentsWorker
  alias Tuist.Storage.Workers.DeleteExpiredPreviewArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredRunSessionsWorker
  alias Tuist.Storage.Workers.DeleteExpiredShardBundlesWorker
  alias Tuist.Storage.Workers.DeleteExpiredTestAttachmentsWorker
  alias Tuist.Tests

  describe "perform/1" do
    test "the preview worker uses an explicit retention window" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)
      stub(Environment, :artifact_retention_days, fn -> %{app_previews: 60} end)

      expired_app_build =
        app_build_fixture(
          preview: preview_fixture(project: project),
          inserted_at: DateTime.add(DateTime.utc_now(), -61, :day)
        )

      retained_app_build =
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

      retained_app_build_key =
        AppBuilds.storage_key(%{
          account_handle: account.name,
          project_handle: project.name,
          app_build: retained_app_build
        })

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredPreviewArtifactsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20,
                 "retention_days" => 30,
                 "self_hosted" => true
               })

      assert_received {:deleted, object_keys}
      assert expired_app_build_key in object_keys
      assert expired_icon_key in object_keys
      refute retained_app_build_key in object_keys
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

    test "a full batch reschedules the next page and the cursor advances past the oldest rows" do
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

      job =
        insert_job(DeleteExpiredPreviewArtifactsWorker, %{
          "account_id" => account.id,
          "batch_size" => 1,
          "retention_days" => 60
        })

      assert {:snooze, 0} = DeleteExpiredPreviewArtifactsWorker.perform(job)

      assert_received {:deleted, first_keys}
      assert older_key in first_keys
      refute newer_key in first_keys

      assert [continuation_job] = all_enqueued(worker: DeleteExpiredPreviewArtifactsWorker)

      assert continuation_job.args == %{
               "account_id" => account.id,
               "batch_size" => 1,
               "after_id" => older.id,
               "after_inserted_at" => DateTime.to_iso8601(Repo.get(AppBuild, older.id).inserted_at),
               "retention_days" => 60
             }

      cursor_inserted_at = Repo.get(AppBuild, older.id).inserted_at

      assert continuation_job.args["after_inserted_at"] == DateTime.to_iso8601(cursor_inserted_at)
      assert {:snooze, 0} = DeleteExpiredPreviewArtifactsWorker.perform(continuation_job)

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

      job =
        insert_job(DeleteExpiredPreviewArtifactsWorker, %{
          "account_id" => account.id,
          "batch_size" => 1,
          "after_inserted_at" => older_inserted_at |> DateTime.add(-1, :second) |> DateTime.to_iso8601(),
          "after_id" => "00000000-0000-0000-0000-000000000000"
        })

      assert {:snooze, 0} = DeleteExpiredPreviewArtifactsWorker.perform(job)

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

    test "the run session worker deletes every expired run artifact by prefix according to the account plan" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      expired_run =
        command_event_fixture(
          project_id: project.id,
          ran_at: DateTime.add(DateTime.utc_now(), -31, :day)
        )

      recent_run =
        command_event_fixture(
          project_id: project.id,
          ran_at: DateTime.add(DateTime.utc_now(), -29, :day)
        )

      project = %{project | account: account}
      expired_run_artifact_prefix = "#{CommandEvents.get_command_event_artifact_base_path_key(expired_run.id, project)}/"
      recent_run_artifact_prefix = "#{CommandEvents.get_command_event_artifact_base_path_key(recent_run.id, project)}/"

      stub(Storage, :delete_all_objects, fn prefix, %{id: account_id} ->
        assert account_id == account.id
        send(self(), {:deleted, prefix})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredRunSessionsWorker, %{
                 "account_id" => account.id,
                 "batch_size" => 20
               })

      assert_received {:deleted, ^expired_run_artifact_prefix}
      refute_received {:deleted, ^recent_run_artifact_prefix}
    end

    test "the run session worker paginates by command event run time" do
      project = project_fixture()
      account = project.account
      subscription_fixture(account_id: account.id, plan: :air)

      older_run =
        command_event_fixture(
          project_id: project.id,
          ran_at: DateTime.add(DateTime.utc_now(), -33, :day)
        )

      newer_run =
        command_event_fixture(
          project_id: project.id,
          ran_at: DateTime.add(DateTime.utc_now(), -32, :day)
        )

      project = %{project | account: account}
      older_run_artifact_prefix = "#{CommandEvents.get_command_event_artifact_base_path_key(older_run.id, project)}/"
      newer_run_artifact_prefix = "#{CommandEvents.get_command_event_artifact_base_path_key(newer_run.id, project)}/"

      stub(Storage, :delete_all_objects, fn prefix, _account ->
        send(self(), {:deleted, prefix})
        :ok
      end)

      job = insert_job(DeleteExpiredRunSessionsWorker, %{"account_id" => account.id, "batch_size" => 1})

      assert {:snooze, 0} = DeleteExpiredRunSessionsWorker.perform(job)

      assert_received {:deleted, ^older_run_artifact_prefix}
      refute_received {:deleted, ^newer_run_artifact_prefix}

      assert [continuation_job] = all_enqueued(worker: DeleteExpiredRunSessionsWorker)

      assert continuation_job.args == %{
               "account_id" => account.id,
               "batch_size" => 1,
               "after_inserted_at" => NaiveDateTime.to_iso8601(older_run.ran_at),
               "after_id" => older_run.id
             }

      assert {:snooze, 0} = DeleteExpiredRunSessionsWorker.perform(continuation_job)

      assert_received {:deleted, ^newer_run_artifact_prefix}
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

      retained_attachment =
        test_case_run_attachment_fixture(
          test_case_run_id: expired_test_case_run.id,
          test_run_id: test_run_id,
          file_name: "recent.log",
          inserted_at: DateTime.utc_now() |> DateTime.add(-29, :day) |> DateTime.to_naive()
        )

      legacy_attachment =
        test_case_run_attachment_fixture(
          test_case_run_id: expired_test_case_run.id,
          test_run_id: nil,
          file_name: "legacy.log",
          inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      other_project = project_fixture()

      {:ok, other_expired_test} =
        test_fixture(
          project_id: other_project.id,
          account_id: other_project.account.id,
          ran_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      other_test_case_run = List.first(other_expired_test.test_case_runs)

      other_attachment =
        test_case_run_attachment_fixture(
          test_case_run_id: other_test_case_run.id,
          test_run_id: other_expired_test.id,
          file_name: "other.log",
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

      retained_attachment_key =
        Tests.attachment_storage_key(%{
          account_handle: account.name,
          project_handle: project.name,
          attachment_id: retained_attachment.id,
          test_case_run_id: expired_test_case_run.id,
          test_run_id: test_run_id,
          file_name: retained_attachment.file_name
        })

      legacy_attachment_key =
        Tests.attachment_storage_key(%{
          account_handle: account.name,
          project_handle: project.name,
          attachment_id: legacy_attachment.id,
          test_case_run_id: expired_test_case_run.id,
          test_run_id: nil,
          file_name: legacy_attachment.file_name
        })

      other_attachment_key =
        Tests.attachment_storage_key(%{
          account_handle: other_project.account.name,
          project_handle: other_project.name,
          attachment_id: other_attachment.id,
          test_case_run_id: other_test_case_run.id,
          test_run_id: other_expired_test.id,
          file_name: other_attachment.file_name
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
      refute retained_attachment_key in object_keys
      refute legacy_attachment_key in object_keys
      refute other_attachment_key in object_keys
    end

    test "the legacy test attachment worker deletes attachments without test run ids" do
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
               perform_job(DeleteExpiredLegacyTestAttachmentsWorker, %{
                 "batch_size" => 20,
                 "retention_days" => 30,
                 "dry_run" => false
               })

      assert_received {:deleted, object_keys}
      assert expired_attachment_key in object_keys

      assert %LegacyTestAttachmentRetentionCursor{
               completed_before: completed_before,
               sweep_before: sweep_before,
               after_test_case_run_id: nil,
               after_id: nil
             } = Repo.one(LegacyTestAttachmentRetentionCursor)

      assert completed_before == sweep_before

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 retention_days: 30,
                 dry_run: false
               )

      assert %LegacyTestAttachmentRetentionCursor{
               after_test_case_run_id: nil,
               after_id: nil
             } = Repo.one(LegacyTestAttachmentRetentionCursor)
    end

    test "the legacy test attachment worker preserves retained attachments while completing an expired time band" do
      project = project_fixture()
      cutoff = DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()

      expired_test_case_run =
        test_case_run_fixture(
          project_id: project.id,
          account_id: project.account.id,
          inserted_at: cutoff
        )

      expired_attachment =
        test_case_run_attachment_fixture(
          test_case_run_id: expired_test_case_run.id,
          test_run_id: nil,
          file_name: "expired.log",
          inserted_at: cutoff
        )

      retained_test_case_run =
        test_case_run_fixture(
          project_id: project.id,
          account_id: project.account.id,
          inserted_at: NaiveDateTime.utc_now()
        )

      retained_attachment =
        test_case_run_attachment_fixture(
          test_case_run_id: retained_test_case_run.id,
          test_run_id: nil,
          file_name: "retained.log",
          inserted_at: NaiveDateTime.utc_now()
        )

      expired_attachment_key =
        Tests.attachment_storage_key(%{
          account_handle: project.account.name,
          project_handle: project.name,
          attachment_id: expired_attachment.id,
          test_case_run_id: expired_test_case_run.id,
          test_run_id: nil,
          file_name: expired_attachment.file_name
        })

      retained_attachment_key =
        Tests.attachment_storage_key(%{
          account_handle: project.account.name,
          project_handle: project.name,
          attachment_id: retained_attachment.id,
          test_case_run_id: retained_test_case_run.id,
          test_run_id: nil,
          file_name: retained_attachment.file_name
        })

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        assert account_id == project.account.id
        send(self(), {:deleted, object_keys})
        :ok
      end)

      assert :ok =
               perform_job(DeleteExpiredLegacyTestAttachmentsWorker, %{
                 "batch_size" => 20,
                 "retention_days" => 30,
                 "dry_run" => false
               })

      assert_received {:deleted, object_keys}
      assert expired_attachment_key in object_keys
      refute retained_attachment_key in object_keys

      assert %LegacyTestAttachmentRetentionCursor{
               completed_before: completed_before,
               sweep_before: sweep_before,
               after_test_case_run_id: nil,
               after_id: nil
             } = Repo.one(LegacyTestAttachmentRetentionCursor)

      assert completed_before == sweep_before

      next_sweep_before =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(1, :day)
        |> NaiveDateTime.to_iso8601()

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 completed_before: completed_before |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
                 sweep_before: next_sweep_before,
                 retention_days: 30,
                 dry_run: false
               )

      assert_received {:deleted, next_object_keys}
      assert retained_attachment_key in next_object_keys
      refute expired_attachment_key in next_object_keys
    end

    test "legacy time bands meet at an exclusive upper and inclusive lower boundary" do
      project = project_fixture()
      completed_before = ~N[2026-01-01 00:00:00.000000]
      boundary = ~N[2026-02-01 00:00:00.000000]
      after_boundary = ~N[2026-02-01 00:00:00.000001]
      next_boundary = ~N[2026-02-02 00:00:00.000000]

      object_keys_by_time =
        Map.new(
          [
            ~N[2026-01-31 23:59:59.999999],
            boundary,
            after_boundary
          ],
          fn inserted_at ->
            test_case_run =
              test_case_run_fixture(
                project_id: project.id,
                account_id: project.account.id,
                inserted_at: inserted_at
              )

            attachment =
              test_case_run_attachment_fixture(
                test_case_run_id: test_case_run.id,
                test_run_id: nil,
                file_name: "#{NaiveDateTime.to_iso8601(inserted_at)}.log",
                inserted_at: inserted_at
              )

            object_key =
              Tests.attachment_storage_key(%{
                account_handle: project.account.name,
                project_handle: project.name,
                attachment_id: attachment.id,
                test_case_run_id: test_case_run.id,
                test_run_id: nil,
                file_name: attachment.file_name
              })

            {inserted_at, object_key}
          end
        )

      stub(Storage, :delete_objects, fn object_keys, _account ->
        send(self(), {:deleted_time_band, object_keys})
        :ok
      end)

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 completed_before: NaiveDateTime.to_iso8601(completed_before),
                 sweep_before: NaiveDateTime.to_iso8601(boundary),
                 dry_run: false
               )

      assert_received {:deleted_time_band, first_band_object_keys}
      assert first_band_object_keys == [Map.fetch!(object_keys_by_time, ~N[2026-01-31 23:59:59.999999])]

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 completed_before: NaiveDateTime.to_iso8601(boundary),
                 sweep_before: NaiveDateTime.to_iso8601(next_boundary),
                 dry_run: false
               )

      assert_received {:deleted_time_band, second_band_object_keys}

      assert MapSet.new(second_band_object_keys) ==
               MapSet.new([
                 Map.fetch!(object_keys_by_time, boundary),
                 Map.fetch!(object_keys_by_time, after_boundary)
               ])
    end

    test "the legacy test attachment worker does not delete or persist during dry runs" do
      project = project_fixture()
      account = project.account

      expired_test_case_run =
        test_case_run_fixture(
          project_id: project.id,
          account_id: account.id,
          inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      test_case_run_attachment_fixture(
        test_case_run_id: expired_test_case_run.id,
        test_run_id: nil,
        file_name: "failure.log",
        inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
      )

      reject(&Storage.delete_objects/2)

      assert :ok =
               perform_job(DeleteExpiredLegacyTestAttachmentsWorker, %{
                 "batch_size" => 20,
                 "retention_days" => 30,
                 "dry_run" => true
               })

      assert Repo.aggregate(LegacyTestAttachmentRetentionCursor, :count) == 0
    end

    test "the legacy test attachment worker stops when self-hosted retention is disabled" do
      stub(Environment, :artifact_retention_days, fn -> %{} end)
      reject(&Storage.delete_objects/2)

      assert :ok =
               perform_job(DeleteExpiredLegacyTestAttachmentsWorker, %{
                 "batch_size" => 20,
                 "dry_run" => false,
                 "self_hosted" => true
               })

      assert Repo.aggregate(LegacyTestAttachmentRetentionCursor, :count) == 0
    end

    test "the legacy test attachment worker does not advance after object deletion fails" do
      project = project_fixture()

      test_case_run =
        test_case_run_fixture(
          project_id: project.id,
          account_id: project.account.id,
          inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        test_run_id: nil,
        inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
      )

      stub(Storage, :delete_objects, fn _object_keys, _account -> {:error, :unavailable} end)

      assert {:error, :unavailable} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 retention_days: 30,
                 dry_run: false
               )

      assert Repo.aggregate(LegacyTestAttachmentRetentionCursor, :count) == 0
    end

    test "a failed legacy page leaves an existing cursor unchanged" do
      project = project_fixture()
      cutoff = DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()

      for _index <- 1..2 do
        test_case_run =
          test_case_run_fixture(
            project_id: project.id,
            account_id: project.account.id,
            inserted_at: cutoff
          )

        test_case_run_attachment_fixture(
          test_case_run_id: test_case_run.id,
          test_run_id: nil,
          inserted_at: cutoff
        )
      end

      deletion_attempts = start_supervised!({Agent, fn -> 0 end})

      stub(Storage, :delete_objects, fn _object_keys, _account ->
        case Agent.get_and_update(deletion_attempts, &{&1, &1 + 1}) do
          0 -> :ok
          _attempt -> {:error, :unavailable}
        end
      end)

      assert {:ok, %{} = _cursor} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 retention_days: 30,
                 dry_run: false
               )

      persisted_cursor = Repo.one!(LegacyTestAttachmentRetentionCursor)

      assert {:error, :unavailable} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 retention_days: 30,
                 dry_run: false
               )

      assert Repo.one!(LegacyTestAttachmentRetentionCursor) == persisted_cursor
    end

    test "the legacy test attachment worker does not advance past unresolved ownership" do
      test_case_run_attachment_fixture(
        test_case_run_id: UUIDv7.generate(),
        test_run_id: nil,
        inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
      )

      reject(&Storage.delete_objects/2)

      assert {:error, {:unresolved_legacy_test_attachments, 1}} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 retention_days: 30,
                 dry_run: false
               )

      assert Repo.aggregate(LegacyTestAttachmentRetentionCursor, :count) == 0
    end

    test "the legacy test attachment worker skips rows for deleted projects without blocking progress" do
      deleted_project_id = System.unique_integer([:positive, :monotonic])

      test_case_run =
        test_case_run_fixture(
          project_id: deleted_project_id,
          inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
        )

      test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        test_run_id: nil,
        inserted_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()
      )

      reject(&Storage.delete_objects/2)

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 retention_days: 30,
                 dry_run: false
               )

      assert %LegacyTestAttachmentRetentionCursor{
               completed_before: completed_before,
               sweep_before: completed_before,
               after_test_case_run_id: nil,
               after_id: nil
             } = Repo.one(LegacyTestAttachmentRetentionCursor)
    end

    test "the legacy test attachment worker deletes each account's objects with that account" do
      projects = [project_fixture(), project_fixture()]
      cutoff = DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()

      attachments_by_account_id =
        Map.new(projects, fn project ->
          test_case_run =
            test_case_run_fixture(
              project_id: project.id,
              account_id: project.account.id,
              inserted_at: cutoff
            )

          attachment =
            test_case_run_attachment_fixture(
              test_case_run_id: test_case_run.id,
              test_run_id: nil,
              file_name: "#{project.id}.log",
              inserted_at: cutoff
            )

          object_key =
            Tests.attachment_storage_key(%{
              account_handle: project.account.name,
              project_handle: project.name,
              attachment_id: attachment.id,
              test_case_run_id: test_case_run.id,
              test_run_id: nil,
              file_name: attachment.file_name
            })

          {project.account.id, object_key}
        end)

      stub(Storage, :delete_objects, fn object_keys, %{id: account_id} ->
        send(self(), {:deleted_for_account, account_id, object_keys})
        :ok
      end)

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 20,
                 retention_days: 30,
                 dry_run: false
               )

      Enum.each(attachments_by_account_id, fn {account_id, object_key} ->
        assert_received {:deleted_for_account, ^account_id, object_keys}
        assert object_key in object_keys
      end)
    end

    test "the legacy test attachment worker continues with its primary-key cursor" do
      project = project_fixture()
      cutoff = DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()

      attachments =
        for _index <- 1..2 do
          test_case_run =
            test_case_run_fixture(
              project_id: project.id,
              account_id: project.account.id,
              inserted_at: cutoff
            )

          test_case_run_attachment_fixture(
            test_case_run_id: test_case_run.id,
            test_run_id: nil,
            inserted_at: cutoff
          )
        end

      reject(&Storage.delete_objects/2)

      job =
        insert_job(DeleteExpiredLegacyTestAttachmentsWorker, %{
          "batch_size" => 1,
          "retention_days" => 30,
          "dry_run" => true
        })

      assert {:snooze, 0} = DeleteExpiredLegacyTestAttachmentsWorker.perform(job)

      assert [continuation_job] =
               all_enqueued(worker: DeleteExpiredLegacyTestAttachmentsWorker)

      assert continuation_job.id == job.id

      assert %{
               "batch_size" => 1,
               "retention_days" => 30,
               "dry_run" => true,
               "sweep_before" => sweep_before,
               "after_test_case_run_id" => first_test_case_run_id,
               "after_id" => first_attachment_id
             } = continuation_job.args

      assert {:ok,
              %{
                "after_test_case_run_id" => second_test_case_run_id,
                "after_id" => second_attachment_id
              }} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 after_test_case_run_id: first_test_case_run_id,
                 after_id: first_attachment_id,
                 sweep_before: sweep_before,
                 retention_days: 30,
                 dry_run: true
               )

      expected_cursors =
        MapSet.new(attachments, &{&1.test_case_run_id, &1.id})

      assert MapSet.new([
               {first_test_case_run_id, first_attachment_id},
               {second_test_case_run_id, second_attachment_id}
             ]) == expected_cursors

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 after_test_case_run_id: second_test_case_run_id,
                 after_id: second_attachment_id,
                 sweep_before: sweep_before,
                 retention_days: 30,
                 dry_run: true
               )
    end

    test "the legacy test attachment cursor follows ClickHouse ordering across pages" do
      project = project_fixture()
      cutoff = DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_naive()

      attachments =
        for _index <- 1..2 do
          test_case_run =
            test_case_run_fixture(
              project_id: project.id,
              account_id: project.account.id,
              inserted_at: cutoff
            )

          test_case_run_attachment_fixture(
            test_case_run_id: test_case_run.id,
            test_run_id: nil,
            inserted_at: cutoff
          )
        end

      stub(Storage, :delete_objects, fn _object_keys, %{id: account_id} ->
        assert account_id == project.account.id
        :ok
      end)

      assert {:ok,
              %{
                "after_test_case_run_id" => first_test_case_run_id,
                "after_id" => first_attachment_id,
                "sweep_before" => sweep_before
              }} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 retention_days: 30,
                 dry_run: false
               )

      assert %LegacyTestAttachmentRetentionCursor{
               after_test_case_run_id: ^first_test_case_run_id,
               after_id: ^first_attachment_id
             } = Repo.one(LegacyTestAttachmentRetentionCursor)

      assert {:ok,
              %{
                "after_test_case_run_id" => second_test_case_run_id,
                "after_id" => second_attachment_id,
                "sweep_before" => ^sweep_before
              }} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 retention_days: 30,
                 dry_run: false
               )

      assert %LegacyTestAttachmentRetentionCursor{
               after_test_case_run_id: ^second_test_case_run_id,
               after_id: ^second_attachment_id
             } = Repo.one(LegacyTestAttachmentRetentionCursor)

      assert {:error, :stale_legacy_test_attachment_cursor} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 after_test_case_run_id: first_test_case_run_id,
                 after_id: first_attachment_id,
                 sweep_before: sweep_before,
                 retention_days: 30,
                 dry_run: false
               )

      assert %LegacyTestAttachmentRetentionCursor{
               after_test_case_run_id: ^second_test_case_run_id,
               after_id: ^second_attachment_id
             } = Repo.one(LegacyTestAttachmentRetentionCursor)

      assert MapSet.new([
               {first_test_case_run_id, first_attachment_id},
               {second_test_case_run_id, second_attachment_id}
             ]) == MapSet.new(attachments, &{&1.test_case_run_id, &1.id})

      assert {:ok, nil} =
               ExpiredArtifacts.delete_legacy_test_attachments(
                 1,
                 retention_days: 30,
                 dry_run: false
               )

      assert %LegacyTestAttachmentRetentionCursor{
               completed_before: completed_before,
               sweep_before: completed_before,
               after_test_case_run_id: nil,
               after_id: nil
             } = Repo.one(LegacyTestAttachmentRetentionCursor)
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

  defp insert_job(worker, args) do
    assert {:ok, job} = args |> worker.new() |> Oban.insert()
    job
  end
end
