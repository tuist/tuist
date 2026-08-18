defmodule Tuist.Registry.Swift.RepairTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Tuist.Repo
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Registry
  alias Tuist.Registry.S3
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.Repair
  alias Tuist.Registry.Swift.SyncWorker

  setup :set_mimic_from_context
  setup :verify_on_exit!

  setup do
    Sandbox.checkout(Tuist.Repo)
    :ok
  end

  defp catalog(version, checksum) do
    %{"releases" => %{version => %{"checksum" => checksum, "manifests" => []}}}
  end

  describe "plan/2" do
    test "classifies a version whose catalog and stored archive agree as published" do
      expect(Metadata, :get_package, fn "apple", "swift_argument_parser" -> {:ok, catalog("1.0.0", "abc")} end)

      expect(S3, :head_object, fn "registry/swift/apple/swift_argument_parser/1.0.0/source_archive.zip" ->
        {:ok, %{"x-amz-meta-sha256" => "abc"}}
      end)

      assert {:ok, plan} = Repair.plan([{"Apple/swift.argument.parser", "1.0.0"}])
      assert plan.counts == %{absent: 0, unresolvable: 0, published: 1, uninspectable: 0}
      assert [%{status: :published, published_checksum: "abc"}] = plan.targets
    end

    test "classifies a version whose archive object storage cannot produce as unresolvable" do
      expect(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "abc")} end)
      expect(S3, :head_object, fn _key -> {:error, :not_found} end)

      assert {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])
      assert plan.counts.unresolvable == 1
    end

    test "classifies a version whose stored digest disagrees with the catalog as unresolvable" do
      expect(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "abc")} end)
      expect(S3, :head_object, fn _key -> {:ok, %{"x-amz-meta-sha256" => "def"}} end)

      assert {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])
      assert [%{status: :unresolvable, published_checksum: "abc", stored_checksum: "def"}] = plan.targets
    end

    test "classifies a version the catalog does not carry as absent, without heading object storage" do
      expect(Metadata, :get_package, fn "apple", "parser" -> {:error, :not_found} end)
      reject(&S3.head_object/1)

      assert {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])
      assert plan.counts.absent == 1
    end

    test "writes nothing" do
      expect(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      expect(S3, :head_object, fn _key -> {:ok, %{"x-amz-meta-sha256" => "abc"}} end)
      reject(&S3.copy_object/2)
      reject(&S3.upload_content/3)
      reject(&Metadata.put_package/3)

      assert {:ok, _plan} = Repair.plan([{"apple/parser", "1.0.0"}])
      refute_enqueued(worker: SyncWorker)
    end

    test "rejects a target whose version is not a storable one" do
      assert {:error, {:invalid_version, "not-a-version"}} = Repair.plan([{"apple/parser", "not-a-version"}])
    end

    test "rejects an empty plan" do
      assert {:error, :empty_plan} = Repair.plan([])
    end
  end

  describe "apply_plan/2" do
    test "refuses without the plan's approval digest" do
      expect(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      expect(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      reject(&S3.copy_object/2)

      assert {:error, :approval_required} = Repair.apply_plan(plan, [])
      assert {:error, :approval_required} = Repair.apply_plan(plan, approval: "not-the-digest")
      refute_enqueued(worker: SyncWorker)
    end

    test "refuses a plan whose threshold was widened after it was approved" do
      stub(Metadata, :get_package, fn _scope, _name ->
        {:ok, %{"releases" => Map.new(1..3, &{"1.0.#{&1}", %{"checksum" => "abc"}})}}
      end)

      stub(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan(Enum.map(1..3, &{"apple/parser", "1.0.#{&1}"}), max_checksum_changes: 2)

      # The digest has to cover the threshold, not just the targets. Otherwise
      # raising it on the returned map keeps the approval valid and the abort
      # gate is decoration.
      widened = %{plan | max_checksum_changes: 99}

      reject(&S3.copy_object/2)

      assert {:error, :approval_required} = Repair.apply_plan(widened, approval: plan.approval)
      refute_enqueued(worker: SyncWorker)
    end

    test "refuses a plan whose targets were edited after it was approved" do
      stub(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      stub(S3, :head_object, fn _key -> {:ok, %{"x-amz-meta-sha256" => "abc"}} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      edited = %{plan | targets: Enum.map(plan.targets, &Map.put(&1, :status, :unresolvable))}

      reject(&S3.copy_object/2)

      assert {:error, :approval_required} = Repair.apply_plan(edited, approval: plan.approval)
      refute_enqueued(worker: SyncWorker)
    end

    test "refuses a plan whose checksum-changing targets exceed the threshold" do
      versions = Enum.map(1..3, &{"apple/parser", "1.0.#{&1}"})

      stub(Metadata, :get_package, fn _scope, _name ->
        {:ok, %{"releases" => Map.new(1..3, &{"1.0.#{&1}", %{"checksum" => "abc"}})}}
      end)

      stub(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan(versions, max_checksum_changes: 2)

      reject(&S3.copy_object/2)

      assert {:error, {:too_many_checksum_changes, 3, 2}} = Repair.apply_plan(plan, approval: plan.approval)
      refute_enqueued(worker: SyncWorker)
    end

    test "refuses a plan larger than the batch bound" do
      targets = Enum.map(1..(Repair.max_batch() + 1), &{"apple/parser", "1.0.#{&1}"})

      stub(Metadata, :get_package, fn _scope, _name -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan(targets)

      assert {:error, {:batch_too_large, _size, _max}} = Repair.apply_plan(plan, approval: plan.approval)
      refute_enqueued(worker: SyncWorker)
    end

    test "refuses a plan containing a target whose state could not be read" do
      expect(Metadata, :get_package, fn _scope, _name -> {:error, {:s3_error, 500}} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      reject(&S3.copy_object/2)

      assert {:error, {:uninspectable_targets, 1}} = Repair.apply_plan(plan, approval: plan.approval)
      refute_enqueued(worker: SyncWorker)
    end

    test "backs the archive up before enqueuing a rebuild that may replace it" do
      expect(Metadata, :get_package, 2, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      expect(S3, :head_object, fn _key -> {:ok, %{"x-amz-meta-sha256" => "def"}} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      expect(S3, :copy_object, fn source, destination ->
        assert source == "registry/swift/apple/parser/1.0.0/source_archive.zip"
        assert destination == "registry/backups/swift/apple/parser/1.0.0/abc/source_archive.zip"
        :ok
      end)

      expect(S3, :upload_content, fn key, body, _opts ->
        assert key == "registry/backups/swift/apple/parser/1.0.0/abc/backup.json"
        assert JSON.decode!(body)["published_checksum"] == "abc"
        :ok
      end)

      assert {:ok, %{applied: [%{status: :enqueued}], failed: []}} =
               Repair.apply_plan(plan, approval: plan.approval)

      assert_enqueued(
        worker: SyncWorker,
        args: %{
          "force" => true,
          "allow_checksum_change" => true,
          "repository_full_handle" => "apple/parser",
          "version" => "1.0.0"
        }
      )
    end

    test "leaves a version whose catalog and stored archive already agree alone" do
      expect(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      expect(S3, :head_object, fn _key -> {:ok, %{"x-amz-meta-sha256" => "abc"}} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      reject(&S3.copy_object/2)

      assert {:ok, %{applied: [], failed: [%{status: :skipped, reason: :already_consistent}]}} =
               Repair.apply_plan(plan, approval: plan.approval)

      refute_enqueued(worker: SyncWorker)
    end

    test "stops a target whose published checksum moved between the plan and the apply" do
      expect(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      expect(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      expect(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "moved")} end)
      reject(&S3.copy_object/2)

      assert {:ok, %{applied: [], failed: [%{status: :failed, reason: {:published_checksum_moved, "abc", "moved"}}]}} =
               Repair.apply_plan(plan, approval: plan.approval)

      refute_enqueued(worker: SyncWorker)
    end

    test "does not allow a checksum change for a version the catalog does not carry" do
      expect(Metadata, :get_package, 2, fn _scope, _name -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      reject(&S3.copy_object/2)

      assert {:ok, %{applied: [%{status: :enqueued}]}} = Repair.apply_plan(plan, approval: plan.approval)

      assert_enqueued(worker: SyncWorker, args: %{"force" => true, "version" => "1.0.0"})
      refute_enqueued(worker: SyncWorker, args: %{"allow_checksum_change" => true})
    end
  end

  describe "restore/4" do
    test "copies the backup back and rewrites the catalog entry to its checksum" do
      expect(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      expect(S3, :head_object, fn "registry/backups/swift/apple/parser/1.0.0/abc/source_archive.zip" -> {:ok, %{}} end)

      expect(S3, :copy_object, fn source, destination ->
        assert source == "registry/backups/swift/apple/parser/1.0.0/abc/source_archive.zip"
        assert destination == "registry/swift/apple/parser/1.0.0/source_archive.zip"
        :ok
      end)

      expect(Metadata, :put_package, fn "apple", "parser", metadata ->
        assert metadata["releases"]["1.0.0"]["checksum"] == "abc"
        :ok
      end)

      assert {:ok, %{version: "1.0.0", checksum: "abc", cancelled_jobs: 0}} =
               Repair.restore("apple/parser", "1.0.0", "abc")
    end

    # A repair job that snoozed on a rate limit carries allow_checksum_change
    # and would republish the rebuilt bytes over the restore once the quota
    # resets, hours later. A rollback that a queued job can silently undo is not
    # a rollback.
    test "cancels the outstanding repair job before touching the archive" do
      {:ok, job} =
        Registry.force_resync_swift_package_version("apple/parser", "1.0.0", allow_checksum_change: true)

      assert_enqueued(worker: SyncWorker, args: %{"version" => "1.0.0"})

      stub(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      stub(S3, :head_object, fn _key -> {:ok, %{}} end)
      stub(S3, :copy_object, fn _source, _destination -> :ok end)
      stub(Metadata, :put_package, fn _scope, _name, _metadata -> :ok end)

      assert {:ok, %{cancelled_jobs: 1}} = Repair.restore("apple/parser", "1.0.0", "abc")

      assert %{state: "cancelled"} = Tuist.Repo.reload!(job)
    end

    test "leaves a repair job for a different version alone" do
      {:ok, _job} = Registry.force_resync_swift_package_version("apple/parser", "2.0.0", [])

      stub(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      stub(S3, :head_object, fn _key -> {:ok, %{}} end)
      stub(S3, :copy_object, fn _source, _destination -> :ok end)
      stub(Metadata, :put_package, fn _scope, _name, _metadata -> :ok end)

      assert {:ok, %{cancelled_jobs: 0}} = Repair.restore("apple/parser", "1.0.0", "abc")
    end

    # Everything the restore needs is read before any byte moves, so a missing
    # backup cannot leave the archive half-replaced.
    test "replaces nothing when the named backup does not exist" do
      expect(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      expect(S3, :head_object, fn _key -> {:error, :not_found} end)

      reject(&S3.copy_object/2)
      reject(&Metadata.put_package/3)

      assert {:error, {:backup_not_found, "1.0.0", "abc"}} = Repair.restore("apple/parser", "1.0.0", "abc")
    end

    test "replaces nothing when the version is not in the catalog" do
      expect(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("9.9.9", "rebuilt")} end)

      reject(&S3.head_object/1)
      reject(&S3.copy_object/2)

      assert {:error, {:release_not_in_catalog, "1.0.0"}} = Repair.restore("apple/parser", "1.0.0", "abc")
    end

    # The archive is back but the catalog still advertises the repaired
    # checksum, so the version resolves to a mismatch until this is re-run.
    # Naming that state is what tells the operator to retry.
    test "reports the partial state when the catalog write fails after the archive is replaced" do
      expect(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      expect(S3, :head_object, fn _key -> {:ok, %{}} end)
      expect(S3, :copy_object, fn _source, _destination -> :ok end)
      expect(Metadata, :put_package, fn _scope, _name, _metadata -> {:error, :timeout} end)

      assert {:error, {:restore_incomplete, :catalog_not_updated, :timeout}} =
               Repair.restore("apple/parser", "1.0.0", "abc")
    end
  end
end
