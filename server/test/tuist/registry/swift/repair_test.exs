defmodule Tuist.Registry.Swift.RepairTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Tuist.Repo
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Registry
  alias Tuist.Registry.S3
  alias Tuist.Registry.Swift.Lock
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.Repair
  alias Tuist.Registry.Swift.SyncWorker

  setup :set_mimic_from_context
  setup :verify_on_exit!

  setup do
    Sandbox.checkout(Tuist.Repo)

    stub(Lock, :try_acquire, fn _key, _ttl -> {:ok, :acquired} end)
    stub(Lock, :release, fn _key -> :ok end)

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

    # Normalization is lossy, so the handle cannot be derived back from scope and
    # name, and it is the field the rebuild is actually executed against. Left
    # unsigned, editing only it kept the approval valid while pointing the
    # rebuild at a different package than the one that was backed up.
    test "refuses a plan whose repository handle was edited after it was approved" do
      stub(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      stub(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      repointed = %{
        plan
        | targets: Enum.map(plan.targets, &Map.put(&1, :repository_full_handle, "attacker/parser"))
      }

      reject(&S3.copy_object/2)

      assert {:error, :approval_required} = Repair.apply_plan(repointed, approval: plan.approval)
      refute_enqueued(worker: SyncWorker)
    end

    # `:counts` is a convenience for a human reading the plan and is not covered
    # by the digest, so the gates must not trust it.
    test "counts checksum-changing targets from the signed targets, not the plan's summary" do
      versions = Enum.map(1..3, &{"apple/parser", "1.0.#{&1}"})

      stub(Metadata, :get_package, fn _scope, _name ->
        {:ok, %{"releases" => Map.new(1..3, &{"1.0.#{&1}", %{"checksum" => "abc"}})}}
      end)

      stub(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan(versions, max_checksum_changes: 2)

      understated = %{plan | counts: %{plan.counts | unresolvable: 0}}

      reject(&S3.copy_object/2)

      assert {:error, {:too_many_checksum_changes, 3, 2}} =
               Repair.apply_plan(understated, approval: plan.approval)

      refute_enqueued(worker: SyncWorker)
    end

    test "counts uninspectable targets from the signed targets, not the plan's summary" do
      expect(Metadata, :get_package, fn _scope, _name -> {:error, {:s3_error, 500}} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      understated = %{plan | counts: %{plan.counts | uninspectable: 0}}

      reject(&S3.copy_object/2)

      assert {:error, {:uninspectable_targets, 1}} = Repair.apply_plan(understated, approval: plan.approval)
      refute_enqueued(worker: SyncWorker)
    end

    # The release worker replaces the archive before it writes the catalog entry,
    # so a rebuild that fails in between leaves new bytes under an unchanged
    # catalog checksum. The obvious re-plan must not copy those over the only
    # remaining copy of the pre-repair bytes.
    test "keeps the first backup when one already exists for the published checksum" do
      stub(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)

      stub(S3, :head_object, fn
        "registry/swift/apple/parser/1.0.0/source_archive.zip" -> {:ok, %{"x-amz-meta-sha256" => "rebuilt-bytes"}}
        "registry/backups/swift/apple/parser/1.0.0/abc/source_archive.zip" -> {:ok, %{}}
      end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      reject(&S3.copy_object/2)
      reject(&S3.upload_content/3)

      assert {:ok, %{applied: [%{status: :enqueued}]}} = Repair.apply_plan(plan, approval: plan.approval)
    end

    # The plan's classification has two halves. Re-reading only the catalog half
    # left the dangerous case open: an archive restored to the published
    # checksum in between makes the version healthy again while the catalog
    # checksum is unchanged, and a stale `:unresolvable` would have carried the
    # override into replacing it.
    test "skips a target that became healthy between planning and applying" do
      stub(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)

      Agent.start_link(fn -> ["def", "abc"] end, name: :stored_checksums)

      stub(S3, :head_object, fn "registry/swift/apple/parser/1.0.0/source_archive.zip" ->
        stored =
          Agent.get_and_update(:stored_checksums, fn
            [only] -> {only, [only]}
            [head | rest] -> {head, rest}
          end)

        {:ok, %{"x-amz-meta-sha256" => stored}}
      end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])
      assert [%{status: :unresolvable}] = plan.targets

      reject(&S3.copy_object/2)

      assert {:ok, %{applied: [], failed: [%{status: :skipped, reason: :already_consistent}]}} =
               Repair.apply_plan(plan, approval: plan.approval)

      refute_enqueued(worker: SyncWorker)
    end

    # Without the fence the re-read above would just be a narrower race: a
    # release could land between reading and enqueuing.
    test "does not repair a version while a release for it is in flight" do
      stub(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      stub(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}])

      expect(Lock, :try_acquire, fn {:release, "apple", "parser", "1.0.0"}, _ttl ->
        {:error, :already_locked}
      end)

      reject(&S3.copy_object/2)

      assert {:ok, %{applied: [], failed: [%{status: :failed, reason: :release_in_flight}]}} =
               Repair.apply_plan(plan, approval: plan.approval)

      refute_enqueued(worker: SyncWorker)
    end

    test "rejects a threshold that is not a non-negative integer" do
      assert {:error, {:invalid_max_checksum_changes, "10"}} =
               Repair.plan([{"apple/parser", "1.0.0"}], max_checksum_changes: "10")

      assert {:error, {:invalid_max_checksum_changes, nil}} =
               Repair.plan([{"apple/parser", "1.0.0"}], max_checksum_changes: nil)
    end

    # The digest is not sufficient on its own here. It interpolates the threshold
    # into a string, so `0` and `"0"` hash identically and a string threshold
    # sails through approval. Elixir then orders every number below every
    # binary, making `1 > "0"` false, so the abort gate would pass a batch it
    # was configured to refuse. The validation at apply time is what catches it.
    test "fails closed when an applied plan carries a non-integer threshold" do
      stub(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)
      stub(S3, :head_object, fn _key -> {:error, :not_found} end)

      {:ok, plan} = Repair.plan([{"apple/parser", "1.0.0"}], max_checksum_changes: 0)

      # Sanity: as configured, this plan is refused for exceeding its threshold.
      assert {:error, {:too_many_checksum_changes, 1, 0}} = Repair.apply_plan(plan, approval: plan.approval)

      tampered = %{plan | max_checksum_changes: "0"}

      # The approval still matches, which is the point.
      reject(&S3.copy_object/2)

      assert {:error, {:invalid_max_checksum_changes, "0"}} =
               Repair.apply_plan(tampered, approval: plan.approval)

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
      stub(Metadata, :get_package, fn _scope, _name -> {:ok, catalog("1.0.0", "abc")} end)

      # Still unresolvable at apply time, and no backup exists yet.
      stub(S3, :head_object, fn
        "registry/swift/apple/parser/1.0.0/source_archive.zip" -> {:ok, %{"x-amz-meta-sha256" => "def"}}
        "registry/backups/swift/apple/parser/1.0.0/abc/source_archive.zip" -> {:error, :not_found}
      end)

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
      stub(S3, :head_object, fn _key -> {:error, :not_found} end)

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
      expect(Metadata, :get_package, 2, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
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

    # The catalog entry is one document per package, so the restore's write is a
    # read-modify-write shared with release publication. Re-reading inside the
    # lock is what keeps a version published during the archive copy from being
    # dropped by writing back the older document.
    test "re-reads the catalog inside the package lock rather than writing back the pre-flight copy" do
      before_copy = catalog("1.0.0", "rebuilt")

      published_during_copy =
        put_in(before_copy["releases"]["2.0.0"], %{"checksum" => "published-while-copying", "manifests" => []})

      Agent.start_link(fn -> [before_copy, published_during_copy] end, name: :restore_catalog_reads)

      stub(Metadata, :get_package, fn "apple", "parser" ->
        Agent.get_and_update(:restore_catalog_reads, fn
          [only] -> {{:ok, only}, [only]}
          [head | rest] -> {{:ok, head}, rest}
        end)
      end)

      # The whole restore is fenced against release execution for this version,
      # and the catalog write additionally takes the package lock.
      expect(Lock, :try_acquire, 2, fn
        {:release, "apple", "parser", "1.0.0"}, _ttl -> {:ok, :acquired}
        {:package, "apple", "parser"}, _ttl -> {:ok, :acquired}
      end)

      expect(Lock, :release, 2, fn
        {:release, "apple", "parser", "1.0.0"} -> :ok
        {:package, "apple", "parser"} -> :ok
      end)

      stub(S3, :head_object, fn _key -> {:ok, %{}} end)
      stub(S3, :copy_object, fn _source, _destination -> :ok end)

      expect(Metadata, :put_package, fn "apple", "parser", metadata ->
        assert metadata["releases"]["1.0.0"]["checksum"] == "abc"
        # Published while the archive was being copied. Writing back the
        # pre-flight document would have silently dropped it.
        assert metadata["releases"]["2.0.0"]["checksum"] == "published-while-copying"
        :ok
      end)

      assert {:ok, %{checksum: "abc"}} = Repair.restore("apple/parser", "1.0.0", "abc")
    end

    test "reports the partial state when the package lock cannot be taken" do
      stub(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      stub(S3, :head_object, fn _key -> {:ok, %{}} end)
      stub(S3, :copy_object, fn _source, _destination -> :ok end)

      stub(Lock, :try_acquire, fn
        {:release, _scope, _name, _version}, _ttl -> {:ok, :acquired}
        {:package, _scope, _name}, _ttl -> {:error, :already_locked}
      end)

      reject(&Metadata.put_package/3)

      assert {:error, {:restore_incomplete, :catalog_not_updated, :package_lock_contended}} =
               Repair.restore("apple/parser", "1.0.0", "abc")
    end

    # A release worker uploads the archive and writes the catalog under this
    # same key, so a restore that ran alongside one could return success with
    # rebuilt bytes, or be undone by it.
    test "refuses to restore while a release for the version is in flight" do
      stub(Lock, :try_acquire, fn {:release, "apple", "parser", "1.0.0"}, _ttl ->
        {:error, :already_locked}
      end)

      reject(&S3.copy_object/2)
      reject(&Metadata.put_package/3)

      assert {:error, :release_in_flight} = Repair.restore("apple/parser", "1.0.0", "abc")
    end

    # The first cancellation is a point-in-time snapshot; an executing SyncWorker
    # can insert a ReleaseWorker after it, and an Oban insert is not blocked by
    # the fence. Sweeping again before releasing catches those.
    test "sweeps for repair jobs again before releasing the fence" do
      stub(Metadata, :get_package, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      stub(S3, :head_object, fn _key -> {:ok, %{}} end)
      stub(S3, :copy_object, fn _source, _destination -> :ok end)
      stub(Metadata, :put_package, fn _scope, _name, _metadata -> :ok end)

      # Enqueued after the restore began, standing in for a SyncWorker that was
      # already executing when the first sweep ran.
      {:ok, job} =
        Registry.force_resync_swift_package_version("apple/parser", "1.0.0", allow_checksum_change: true)

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
      expect(Metadata, :get_package, 2, fn "apple", "parser" -> {:ok, catalog("1.0.0", "rebuilt")} end)
      expect(S3, :head_object, fn _key -> {:ok, %{}} end)
      expect(S3, :copy_object, fn _source, _destination -> :ok end)
      expect(Metadata, :put_package, fn _scope, _name, _metadata -> {:error, :timeout} end)

      assert {:error, {:restore_incomplete, :catalog_not_updated, :timeout}} =
               Repair.restore("apple/parser", "1.0.0", "abc")
    end
  end
end
