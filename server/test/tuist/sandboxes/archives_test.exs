defmodule Tuist.Sandboxes.ArchivesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpOrbs
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxNode
  alias Tuist.Sandboxes.Workers.ArchiveDiskSnapshotWorker
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker
  alias Tuist.Sandboxes.Workers.DeleteArchiveCopyWorker
  alias Tuist.Sandboxes.Workers.OffloadArchivesWorker
  alias Tuist.Sandboxes.Workers.RecoverArchiveUploadWorker
  alias Tuist.Storage
  alias Tuist.Storage.S3Target

  @gib 1024 * 1024 * 1024
  @node %{name: "node-a", templates: [%{name: "default", ready: true, rootfs_bytes: 4 * @gib}]}

  setup do
    account = account_fixture()
    stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)
    stub(Environment, :sandbox_archive_disk_high_water_percent, fn -> 85 end)
    stub(Nodes, :connected_nodes, fn -> [@node] end)
    stub(Storage, :supports_signed_upload_headers?, fn _account -> true end)

    stub(Storage, :multipart_generate_url, fn key, "upload-1", part, _account, _opts ->
      "https://s3/#{key}?part=#{part}"
    end)

    stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)
    stub(Sites, :node_site, fn _node -> nil end)
    stub(Kura, :runner_cache_endpoint_url, fn _account, _platform, _site -> nil end)
    %{account: account}
  end

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(), -hours, :hour)

  defp paused_orb(account, opts \\ []) do
    sandbox_fixture(
      Keyword.merge(
        [account: account, amp_orb_id: "orb-#{System.unique_integer([:positive])}", state: :paused],
        Keyword.merge([node_name: "node-a", paused_at: hours_ago(25)], opts)
      )
    )
  end

  defp archived_orb(account, opts \\ []) do
    sandbox_fixture(
      Keyword.merge(
        [
          account: account,
          amp_orb_id: "amp-thread",
          state: :archived,
          node_name: nil,
          paused_at: hours_ago(30),
          archive_key: "sandbox-archives/#{account.id}/x/y.sbxa",
          archive_bytes: 3 * @gib,
          archive_sha256: "abc123",
          archived_at: hours_ago(5)
        ],
        opts
      )
    )
  end

  defp archive_result do
    {:ok,
     %{
       "parts" => [%{"part_number" => 1, "etag" => ~s("e1")}, %{"part_number" => 2, "etag" => ~s("e2")}],
       "bytes" => 2 * @gib,
       "sha256" => "deadbeef",
       "stored_bytes" => 5 * @gib,
       "disks_synced" => true,
       "duration_ms" => 1000
     }}
  end

  describe "making room on nodes without disk" do
    setup do
      # Room for two default Orbs (18 GiB and 64 MiB each on @node), not three.
      stub(Nodes, :connected_nodes, fn -> [Map.put(@node, :disk, %{budget_bytes: 40 * @gib})] end)
      :ok
    end

    test "a create queues the archive of the least recently paused idle Orb there, any account's",
         %{account: account} do
      paused_orb(account, paused_at: hours_ago(1))
      paused_orb(account_fixture(), paused_at: hours_ago(3))
      other_account = account_fixture()
      archived_orb(other_account, archive_store: "gra-v1", archive_bytes: 500 * @gib)
      oldest = paused_orb(other_account, paused_at: hours_ago(5))

      assert {:error, :no_capacity} = Sandboxes.create_sandbox(account, %{})
      assert [%{args: %{"node_names" => ["node-a"]}}] = all_enqueued(worker: ArchiveSandboxesWorker)

      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", %{sandbox_id: id}, _opts ->
        assert id == oldest.id
        {:error, "upload failed"}
      end)

      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      assert {:error, "upload failed"} = Archives.archive_oldest_on(["node-a"])
    end

    test "a held Managed Agents work item makes room too, unless an archive already uploads there",
         %{account: account} do
      uploading = paused_orb(account, archive_upload_id: "upload-in-flight")
      paused_orb(account_fixture())
      environment = agent_environment_fixture(account: account)

      assert {:error, :no_room} = Capacity.admission(environment, "new-session")
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)

      Repo.update!(Ecto.Changeset.change(uploading, archive_upload_id: nil))
      assert {:error, :no_room} = Capacity.admission(environment, "new-session")
      assert [%{args: %{"node_names" => ["node-a"]}}] = all_enqueued(worker: ArchiveSandboxesWorker)
    end
  end

  describe "offloading paused sandboxes off a node CI takes" do
    setup do
      Repo.insert!(%SandboxNode{
        name: "node-a",
        pod_name: "sandboxd-a",
        memory_limit_bytes: @gib,
        allocation_reclaim: true
      })

      :ok
    end

    defp paused(account, opts), do: sandbox_fixture([account: account, state: :paused, node_name: "node-a"] ++ opts)

    defp expect_failed_upload(expected_id) do
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", %{sandbox_id: id}, _opts ->
        assert id == expected_id
        {:error, "upload failed"}
      end)

      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
    end

    test "moves every source's paused sandboxes, oldest first and one at a time, however recent",
         %{account: account} do
      # Paused an hour ago: the age threshold (24 h) would leave them all on the node.
      plain = paused(account, paused_at: hours_ago(1))
      orb = paused(account, amp_orb_id: "orb-1", paused_at: hours_ago(2))
      paused(account, purpose: :remote_execution, paused_at: hours_ago(3))
      paused(account, residency_work_id: "turn", paused_at: hours_ago(4))
      sandbox_fixture(account: account, state: :running, node_name: "node-a")

      assert :ok = Archives.move_off_node("node-a")
      assert [%{args: %{"node_names" => ["node-a"], "ci" => true}}] = all_enqueued(worker: ArchiveSandboxesWorker)

      expect_failed_upload(orb.id)
      assert {:error, "upload failed"} = Archives.archive_oldest_on(["node-a"], ci: true)

      # The failed one backs off, and the next observation moves the next one.
      expect_failed_upload(plain.id)
      assert {:error, "upload failed"} = Archives.archive_oldest_on(["node-a"], ci: true)
      assert {:ok, :skipped} = Archives.archive_oldest_on(["node-a"], ci: true)
    end

    test "leaves the sandboxes where they are once the reservation is gone, or with the tier off",
         %{account: account} do
      paused(account, paused_at: hours_ago(1))
      reject(&Nodes.call/4)

      Repo.update_all(from(n in SandboxNode, where: n.name == "node-a"), set: [allocation_reclaim: false])
      assert {:ok, :skipped} = Archives.archive_oldest_on(["node-a"], ci: true)

      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      assert :ok = Archives.move_off_node("node-a")
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)
    end

    test "a resume its node refuses for room queues that sandbox's archive", %{account: account} do
      sandbox = paused(account, paused_at: hours_ago(1))
      stub(Capacity, :admit, fn _sandbox -> {:error, :no_capacity} end)

      assert {:error, :no_capacity} = Sandboxes.resume(sandbox)
      assert [%{args: %{"sandbox_id" => id}}] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert id == sandbox.id

      # The account's quota is no reason to move it.
      other = paused(account, paused_at: hours_ago(1))
      stub(Capacity, :admit, fn _sandbox -> {:error, :sandbox_concurrency_limit} end)
      assert {:error, :sandbox_concurrency_limit} = Sandboxes.resume(other)
      assert [_only_the_first] = all_enqueued(worker: ArchiveSandboxesWorker)
    end
  end

  describe "proactive node disk pressure" do
    setup do
      stub(Nodes, :connected_nodes, fn ->
        for name <- ["node-a", "node-b"], do: Map.merge(@node, %{name: name, disk: %{budget_bytes: 40 * @gib}})
      end)

      :ok
    end

    test "archives the longest-paused idle Orb on each pressured node before demand", %{account: account} do
      oldest = paused_orb(account, paused_at: hours_ago(3))
      recent = paused_orb(account_fixture(), paused_at: hours_ago(1))
      other_node = paused_orb(account, node_name: "node-b", paused_at: hours_ago(4))
      paused_orb(account, node_name: "node-b", state: :running, paused_at: nil)

      Archives.run()
      Archives.run()
      jobs = all_enqueued(worker: ArchiveSandboxesWorker)

      assert Enum.sort(Enum.map(jobs, & &1.args)) == [
               %{"disk_pressure" => true, "node_names" => ["node-a"]},
               %{"disk_pressure" => true, "node_names" => ["node-b"]}
             ]

      for sandbox <- [oldest, other_node] do
        expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
        expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _account -> :ok end)
        expect(Storage, :object_exists?, fn _key, _account -> true end)

        expect(Nodes, :call, fn node, "archive", %{sandbox_id: id}, _opts ->
          assert node == sandbox.node_name
          assert id == sandbox.id
          archive_result()
        end)

        expect(Nodes, :call, fn node, "delete", %{sandbox_id: id}, _opts ->
          assert node == sandbox.node_name
          assert id == sandbox.id
          {:ok, %{}}
        end)

        job = Enum.find(jobs, &(&1.args["node_names"] == [sandbox.node_name]))
        assert :ok = perform_job(ArchiveSandboxesWorker, job.args)
        assert Repo.reload!(sandbox).state == :archived
        # Replaying a stale queued job must not archive the next Orb.
        assert :ok = perform_job(ArchiveSandboxesWorker, job.args)
      end

      assert Repo.reload!(recent).state == :paused
      Archives.run()
      # No further uploads: both nodes are now below the mark.
      reject(&Storage.multipart_start/2)
      for job <- jobs, do: assert(:ok = perform_job(ArchiveSandboxesWorker, job.args))
    end

    test "counts node snapshot copies and skips busy, uploading and backed-off Orbs", %{account: account} do
      paused_orb(account, paused_at: hours_ago(1), residency_work_id: "amp:busy", workspace_gb: 1, memory_mb: 2048)

      paused_orb(account,
        paused_at: hours_ago(2),
        archive_attempted_at: DateTime.utc_now(),
        workspace_gb: 1,
        memory_mb: 2048
      )

      disk_snapshot_fixture(account: account, node_name: "node-a", workspace_gb: 20, archived_at: hours_ago(1))
      eligible = paused_orb(account, paused_at: hours_ago(0), workspace_gb: 1, memory_mb: 2048)
      paused_orb(account, node_name: "node-b", paused_at: hours_ago(1), archive_upload_id: "in-flight")
      paused_orb(account, node_name: "node-b", paused_at: hours_ago(2))

      Archives.run()
      assert [job] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert job.args == %{"disk_pressure" => true, "node_names" => ["node-a"]}
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", %{sandbox_id: id}, _opts ->
        assert id == eligible.id
        {:error, "upload failed"}
      end)

      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      assert :ok = perform_job(ArchiveSandboxesWorker, job.args)
    end

    test "uses the configured mark, strictly above the boundary, and ignores unbudgeted nodes", %{account: account} do
      sandbox = paused_orb(account, paused_at: hours_ago(1))
      # Default Orb: 4 GiB rootfs + 10 GiB workspace + 4 GiB memory + 64 MiB.
      ceiling = 18 * @gib + 64 * 1024 * 1024
      stub(Environment, :sandbox_archive_disk_high_water_percent, fn -> 80 end)

      stub(Nodes, :connected_nodes, fn ->
        [Map.put(@node, :disk, %{budget_bytes: div(ceiling * 100, 80)})]
      end)

      Archives.run()
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)

      stub(Nodes, :connected_nodes, fn -> [Map.put(@node, :disk, %{budget_bytes: div(ceiling * 100, 80) - 1})] end)
      Archives.run()
      assert [job] = all_enqueued(worker: ArchiveSandboxesWorker)

      # An upload can start after enqueueing, including on another replica.
      uploading = paused_orb(account, paused_at: hours_ago(0), archive_upload_id: "started-after-sweep")
      reject(&Storage.multipart_start/2)
      assert :ok = perform_job(ArchiveSandboxesWorker, job.args)
      Repo.delete!(uploading)

      stub(Nodes, :connected_nodes, fn -> [@node] end)
      assert :ok = perform_job(ArchiveSandboxesWorker, job.args)
      assert Repo.reload!(sandbox).state == :paused
    end

    test "disabling pressure or the archive tier leaves recent Orbs alone", %{account: account} do
      for _ <- 1..3, do: paused_orb(account, paused_at: hours_ago(1))
      stub(Environment, :sandbox_archive_disk_high_water_percent, fn -> nil end)
      Archives.run()
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)
      reject(&Storage.multipart_start/2)
      assert :ok = perform_job(ArchiveSandboxesWorker, %{"node_names" => ["node-a"], "disk_pressure" => true})

      stub(Environment, :sandbox_archive_disk_high_water_percent, fn -> 85 end)
      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      Archives.run()
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert :ok = perform_job(ArchiveSandboxesWorker, %{"node_names" => ["node-a"], "disk_pressure" => true})
    end
  end

  describe "request/1" do
    test "queues the archive of a sandbox the hourly run would leave alone", %{account: account} do
      # Not an Amp Orb and paused for minutes, far below the threshold.
      sandbox = sandbox_fixture(account: account, state: :paused, node_name: "node-a", paused_at: hours_ago(0))

      assert :ok = Archives.request(sandbox)
      assert [job] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert job.args == %{"sandbox_id" => sandbox.id}

      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
      expect(Nodes, :call, fn "node-a", "archive", %{sandbox_id: id}, _opts when id == sandbox.id -> archive_result() end)
      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _account -> :ok end)
      expect(Storage, :object_exists?, fn _key, _account -> true end)
      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: id}, _opts when id == sandbox.id -> {:ok, %{}} end)

      assert :ok = perform_job(ArchiveSandboxesWorker, job.args)
      assert %Sandbox{state: :archived, node_name: nil} = Repo.reload!(sandbox)
    end

    test "refuses sandboxes that are not paused on a node, or already uploading", %{account: account} do
      running = sandbox_fixture(account: account, node_name: "node-a")
      uploading = paused_orb(account, archive_upload_id: "upload-in-flight")
      held = paused_orb(account, residency_work_id: "amp:held")
      archived = archived_orb(account)

      assert {:error, {:invalid_state, :running}} = Archives.request(running)
      assert {:error, {:invalid_state, :paused}} = Archives.request(uploading)
      assert {:error, {:invalid_state, :paused}} = Archives.request(held)
      reject(&Storage.multipart_start/2)
      assert {:ok, :skipped} = Archives.archive(held)
      assert {:error, {:invalid_state, :archived}} = Archives.request(archived)
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)
    end

    test "queues archives even when the in-rack budget is exhausted", %{account: account} do
      sandbox = paused_orb(account)
      archived_orb(account, archive_store: "gra-v1", archive_bytes: 500 * @gib)

      assert :ok = Archives.request(sandbox)
      assert [%{args: %{"sandbox_id" => id}}] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert id == sandbox.id
    end
  end

  describe "run/0" do
    test "archives Orbs paused past the threshold and removes them from their node", %{account: account} do
      archived_orb(account, archive_store: "gra-v1", archive_bytes: 500 * @gib)
      sandbox = paused_orb(account)
      recent = paused_orb(account, paused_at: hours_ago(2))
      parent = self()

      expect(Storage, :multipart_start, fn key, _account ->
        assert String.starts_with?(key, Archives.object_prefix(account.id) <> sandbox.id <> "/")
        {:ok, "upload-1"}
      end)

      expect(Nodes, :call, fn "node-a", "archive", args, opts ->
        assert args.sandbox_id == sandbox.id
        assert opts[:timeout] > to_timeout(minute: 30)
        # 10 GiB workspace, 4 GiB rootfs, kernel and slack in parts of at least 32 MiB.
        assert args.part_size >= 32 * 1024 * 1024
        assert length(args.part_urls) * args.part_size > 14 * @gib
        assert length(args.part_urls) <= 2000
        # The upload runs without the sandbox's lock, so a resume never waits for it.
        assert {:ok, :free} =
                 fn -> Sandboxes.with_sandbox_lock(sandbox.id, fn -> {:ok, :free} end, wait: false) end
                 |> Task.async()
                 |> Task.await()

        assert Repo.reload!(sandbox).archive_upload_id == "upload-1"
        archive_result()
      end)

      expect(Storage, :multipart_complete_upload, fn key, "upload-1", [{1, ~s("e1")}, {2, ~s("e2")}], _account ->
        send(parent, {:completed, key})
        :ok
      end)

      expect(Storage, :object_exists?, fn _key, _account -> true end)
      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: id}, _opts when id == sandbox.id -> {:ok, %{}} end)

      Archives.run()

      assert_receive {:completed, key}

      assert %Sandbox{
               state: :archived,
               node_name: nil,
               archive_key: ^key,
               archive_upload_id: nil,
               archive_attempted_at: nil,
               archive_sha256: "deadbeef",
               archived_at: %DateTime{}
             } = archived = Repo.reload!(sandbox)

      assert archived.archive_bytes == 2 * @gib
      assert Repo.reload!(recent).state == :paused
      assert Archives.archived_bytes(account.id) == 502 * @gib
    end

    test "asks the node for the memory image too and records where the disks start", %{account: account} do
      sandbox = paused_orb(account, memory_mb: 8192)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", args, _opts ->
        assert args.memory
        # The disks' 14 GiB and the 8 GiB memory image.
        assert length(args.part_urls) * args.part_size > 22 * @gib

        {:ok, data} = archive_result()

        {:ok,
         Map.merge(data, %{"tail_offset" => 700, "tail_sha256" => "tail", "compat" => "zen5", "memory_bytes" => 3 * @gib})}
      end)

      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _account -> :ok end)
      expect(Storage, :object_exists?, fn _key, _account -> true end)
      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)

      Archives.run()

      assert %Sandbox{
               state: :archived,
               archive_memory: %{"tail_offset" => 700, "tail_sha256" => "tail", "compat" => "zen5"}
             } =
               Repo.reload!(sandbox)
    end

    test "asks a node that restores lazy disks to chunk them and records it", %{account: account} do
      sandbox = paused_orb(account)
      stub(Nodes, :lookup, fn "node-a" -> {:ok, self(), %{lazy_disks: true}} end)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", args, _opts ->
        assert args.memory and args.lazy_disks
        {:ok, data} = archive_result()
        {:ok, Map.merge(data, %{"tail_offset" => 700, "tail_sha256" => "tail", "compat" => "zen5", "lazy_disks" => true})}
      end)

      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _account -> :ok end)
      expect(Storage, :object_exists?, fn _key, _account -> true end)
      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)

      Archives.run()

      assert %Sandbox{state: :archived, archive_memory: %{"lazy_disks" => true, "node" => "node-a"}} =
               Repo.reload!(sandbox)
    end

    test "does nothing but clean up while no threshold is configured", %{account: account} do
      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      sandbox = paused_orb(account)
      reject(&Storage.multipart_start/2)
      reject(&Nodes.call/4)
      Archives.run()
      assert Repo.reload!(sandbox).state == :paused
    end

    test "keeps recently paused Orbs on their nodes however many an account has", %{account: account} do
      for _ <- 1..15, do: paused_orb(account, paused_at: hours_ago(1))
      reject(&Storage.multipart_start/2)
      reject(&Nodes.call/4)
      Archives.run()
    end

    test "leaves non-Amp sandboxes and busy Orbs alone", %{account: account} do
      sandbox_fixture(account: account, state: :paused, node_name: "node-a", paused_at: hours_ago(48))
      paused_orb(account, residency_work_id: "amp:busy")
      reject(&Storage.multipart_start/2)
      reject(&Nodes.call/4)
      Archives.run()
    end

    test "a failed upload aborts the multipart upload, keeps the Orb on its node and backs off", %{account: account} do
      sandbox = paused_orb(account)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> {:error, "object storage answered 503"} end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)

      Archives.run()

      assert %Sandbox{state: :paused, node_name: "node-a", archive_key: nil, archive_upload_id: nil} =
               failed = Repo.reload!(sandbox)

      assert failed.archive_attempted_at
      stub(Nodes, :call, fn _, _, _, _ -> flunk("must respect retry backoff") end)
      Archives.run()
      refute Archives.make_node_room(["node-a"])
      assert {:ok, :skipped} = Archives.archive_oldest_on(["node-a"])

      # Both automatic entry points retry within minutes, not six hours.
      Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id),
        set: [archive_attempted_at: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -6, :minute)]
      )

      assert Archives.make_node_room(["node-a"])
      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> {:error, "still broken"} end)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      Archives.run()
      refute Archives.make_node_room(["node-a"])
    end

    test "a new pause bypasses an older attempt, but not the pause-age threshold", %{account: account} do
      sandbox = paused_orb(account, archive_attempted_at: DateTime.add(DateTime.utc_now(), -4, :minute))
      refute Archives.make_node_room(["node-a"])

      # A real resume/pause updates paused_at; an old failure must not follow it.
      Repo.update!(Ecto.Changeset.change(sandbox, paused_at: DateTime.truncate(DateTime.utc_now(), :second)))
      assert Archives.make_node_room(["node-a"])
      stub(Nodes, :call, fn _, _, _, _ -> flunk("must respect pause age") end)
      Archives.run()

      # The age-based sweep uses the same eligibility, while still respecting age.
      stub(Environment, :sandbox_archive_after_hours, fn -> 0 end)

      Repo.update!(
        Ecto.Changeset.change(Repo.reload!(sandbox),
          paused_at: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -60, :second)
        )
      )

      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> {:error, "upload failed"} end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      Archives.run()
      assert Repo.reload!(sandbox).archive_upload_id == nil
      refute Archives.make_node_room(["node-a"])
    end

    test "multipart start failures use the short backoff too", %{account: account} do
      sandbox = paused_orb(account)
      expect(Storage, :multipart_start, fn _key, _account -> {:error, :unavailable} end)
      Archives.run()
      assert Repo.reload!(sandbox).archive_attempted_at
      refute Archives.make_node_room(["node-a"])

      Repo.update!(
        Ecto.Changeset.change(Repo.reload!(sandbox),
          archive_attempted_at: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -6, :minute)
        )
      )

      assert Archives.make_node_room(["node-a"])
    end

    test "node transport interruptions abort without penalizing the Orb", %{account: account} do
      for reason <- [:not_connected, :node_disconnected, :timeout] do
        sandbox = paused_orb(account)
        expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
        expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> {:error, reason} end)
        expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)

        assert {:error, ^reason} = Archives.archive(sandbox)

        assert %Sandbox{state: :paused, node_name: "node-a", archive_upload_id: nil, archive_attempted_at: nil} =
                 Repo.reload!(sandbox)

        assert Archives.make_node_room(["node-a"])
        Repo.delete!(sandbox)
      end
    end

    test "a node-confirmed legacy pause becomes archivable and an unsynced checkpoint is safely refreshed", %{
      account: account
    } do
      sandbox = paused_orb(account, paused_at: nil, residency_work_id: "amp:old")

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused"}]})

      sandbox = Repo.reload!(sandbox)
      paused_at = sandbox.paused_at
      assert sandbox.residency_work_id == nil

      expect(Storage, :multipart_start, 2, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", _args, _opts ->
        {:error, "disks were not synced by the last pause: #{sandbox.id}"}
      end)

      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      expect(Capacity, :admit, fn actual -> {:ok, actual} end)
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "pause", %{sync_disks: true}, _opts -> {:ok, %{"disks_synced" => true}} end)

      assert {:ok, :skipped} = Archives.archive(sandbox)

      assert %Sandbox{state: :paused, paused_at: ^paused_at, archive_attempted_at: nil, residency_work_id: nil} =
               Repo.reload!(sandbox)

      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> archive_result() end)
      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _account -> :ok end)
      expect(Storage, :object_exists?, fn _key, _account -> true end)
      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)
      assert {:ok, %Sandbox{state: :archived, node_name: nil}} = Archives.archive(Repo.reload!(sandbox))
    end

    test "refreshing an unsynced pause still needs capacity and cannot interrupt a new turn", %{account: account} do
      sandbox = paused_orb(account)
      expect(Capacity, :admit, fn _actual -> {:error, :no_capacity} end)
      reject(&Nodes.call/4)
      assert {:error, :no_capacity} = Sandboxes.sync_paused_disks(sandbox)
      assert Repo.reload!(sandbox).state == :paused

      Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id),
        set: [state: :running, residency_work_id: "amp:new"],
        inc: [residency_epoch: 1]
      )

      assert {:ok, :skipped} = Sandboxes.sync_paused_disks(sandbox)
      assert %Sandbox{state: :running, residency_work_id: "amp:new"} = Repo.reload!(sandbox)
    end

    test "an Orb resumed during the upload can be archived again after its next pause", %{account: account} do
      reject(&Storage.multipart_complete_upload/4)

      for result <- [archive_result(), {:error, "archive interrupted by a resume or delete"}] do
        sandbox = paused_orb(account)
        expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

        expect(Nodes, :call, fn "node-a", "archive", _args, _opts ->
          # A resume and a new pause land while the node uploads. The
          # result may arrive before or after the node notices cancellation.
          # Even when their second-precision pause time is identical, the
          # residency epoch distinguishes the newer checkpoint.
          Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id),
            inc: [residency_epoch: 2]
          )

          result
        end)

        expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
        assert {:ok, :skipped} = Archives.archive(sandbox)

        assert %Sandbox{
                 state: :paused,
                 node_name: "node-a",
                 archive_key: nil,
                 archived_at: nil,
                 archive_attempted_at: nil
               } =
                 Repo.reload!(sandbox)

        assert Archives.make_node_room(["node-a"])
        Repo.delete!(sandbox)
      end
    end

    test "an upload that never becomes readable leaves the Orb on its node", %{account: account} do
      sandbox = paused_orb(account)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> archive_result() end)
      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _account -> {:error, :timeout} end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)

      Archives.run()

      assert %Sandbox{state: :paused, node_name: "node-a", archived_at: nil} = Repo.reload!(sandbox)
    end

    test "killing an upload caller releases ownership for durable recovery", %{account: account} do
      sandbox = paused_orb(account)
      parent = self()
      supervisor = start_supervised!(Task.Supervisor)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", _args, _opts ->
        send(parent, :transferring)
        receive do: (:finish -> archive_result())
      end)

      task = Task.Supervisor.async_nolink(supervisor, fn -> Archives.archive(sandbox) end)
      assert_receive :transferring
      assert %Sandbox{archive_upload_id: "upload-1", archive_attempted_at: %DateTime{}} = Repo.reload!(sandbox)
      assert [recovery] = all_enqueued(worker: RecoverArchiveUploadWorker)
      assert {:snooze, 60} = perform_job(RecoverArchiveUploadWorker, recovery.args)

      Process.exit(task.pid, :kill)
      assert {:exit, :killed} = Task.yield(task, 1_000)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      assert :ok = perform_job(RecoverArchiveUploadWorker, recovery.args)
      assert %Sandbox{state: :paused, archive_upload_id: nil, archive_attempted_at: nil} = Repo.reload!(sandbox)
      assert [%{args: %{"sandbox_id" => id}}] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert id == sandbox.id
    end

    test "durable recovery requeues a crashed manual archive without waiting 45 minutes", %{account: account} do
      sandbox = paused_orb(account, paused_at: hours_ago(1))
      owner = %{sandbox_id: sandbox.id} |> ArchiveSandboxesWorker.new() |> Oban.insert!()
      owner = owner |> Ecto.Changeset.change(state: "executing") |> Repo.update!() |> Repo.reload!()
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", _args, _opts ->
        # A recovery on another process/replica must not interrupt a live transfer.
        assert {:snooze, 60} =
                 fn -> Archives.recover_upload(sandbox.id, "upload-1") end
                 |> Task.async()
                 |> Task.await()

        raise DBConnection.ConnectionError, "pool full"
      end)

      assert_raise DBConnection.ConnectionError, fn -> ArchiveSandboxesWorker.perform(owner) end
      assert [recovery] = all_enqueued(worker: RecoverArchiveUploadWorker)
      assert DateTime.diff(recovery.scheduled_at, owner.inserted_at) in 299..301
      assert Repo.reload!(sandbox).archive_upload_id == "upload-1"
      assert {:error, {:invalid_state, :paused}} = Archives.request(Repo.reload!(sandbox))

      # A dead replica can leave Oban saying executing. Process ownership,
      # not that stale job state, decides whether recovery can proceed.
      assert Repo.reload!(owner).state == "executing"
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      expect(Oban, :insert, fn _changeset -> raise DBConnection.ConnectionError, "pool still full" end)
      assert_raise DBConnection.ConnectionError, fn -> perform_job(RecoverArchiveUploadWorker, recovery.args) end
      # Clearing the claim and requeueing commit together, so recovery can retry.
      assert Repo.reload!(sandbox).archive_upload_id == "upload-1"

      expect(Oban, :insert, fn changeset -> Mimic.call_original(Oban, :insert, [changeset]) end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      assert :ok = perform_job(RecoverArchiveUploadWorker, recovery.args)

      assert %Sandbox{state: :paused, node_name: "node-a", archive_upload_id: nil, archive_attempted_at: nil} =
               Repo.reload!(sandbox)

      assert [%{args: %{"sandbox_id" => id}}] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert id == sandbox.id

      # A replay cannot abort a newer attempt or erase its backoff.
      Repo.update!(
        Ecto.Changeset.change(Repo.reload!(sandbox),
          archive_upload_id: "new-upload",
          archive_attempted_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
      )

      reject(&Storage.multipart_abort/3)
      assert :ok = perform_job(RecoverArchiveUploadWorker, recovery.args)
      assert %Sandbox{archive_upload_id: "new-upload", archive_attempted_at: %DateTime{}} = Repo.reload!(sandbox)
    end

    test "a refused finish lock discards its upload instead of leaving a completed job's claim", %{account: account} do
      sandbox = paused_orb(account)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> archive_result() end)
      expect(Sandboxes, :with_sandbox_lock, fn _id, _fun -> {:error, :locked} end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      reject(&Storage.multipart_complete_upload/4)

      assert {:error, :locked} = Archives.archive(sandbox)
      assert %Sandbox{state: :paused, archive_upload_id: nil, archive_attempted_at: nil} = Repo.reload!(sandbox)
    end

    test "recovery handles completed owners too, but never requeues a resumed Orb", %{account: account} do
      for state <- [:paused, :running] do
        sandbox = paused_orb(account, state: state, archive_key: "old", archive_upload_id: "orphan")
        owner = %{sandbox_id: sandbox.id} |> ArchiveSandboxesWorker.new() |> Oban.insert!()
        Repo.update!(Ecto.Changeset.change(owner, state: "completed"))
        expect(Storage, :multipart_abort, fn "old", "orphan", _account -> :ok end)

        assert :ok =
                 perform_job(RecoverArchiveUploadWorker, %{
                   sandbox_id: sandbox.id,
                   upload_id: "orphan"
                 })

        assert %Sandbox{state: ^state, archive_upload_id: nil, archive_attempted_at: nil} = Repo.reload!(sandbox)
        jobs = all_enqueued(worker: ArchiveSandboxesWorker)
        assert Enum.any?(jobs, &(&1.args["sandbox_id"] == sandbox.id)) == (state == :paused)
      end
    end

    test "aborts uploads whose caller died and reverts restores that never finished", %{account: account} do
      abandoned =
        paused_orb(account,
          archive_key: "k",
          archive_upload_id: "upload-old",
          archive_attempted_at: DateTime.add(DateTime.utc_now(), -2, :hour)
        )

      restoring = archived_orb(account, state: :creating, amp_orb_id: "restoring")

      Repo.update_all(from(s in Sandbox, where: s.id == ^restoring.id),
        set: [updated_at: DateTime.add(DateTime.utc_now(), -20, :minute)]
      )

      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      expect(Storage, :multipart_abort, fn "k", "upload-old", _account -> :ok end)

      Archives.run()

      assert %Sandbox{archive_upload_id: nil, archive_key: nil, archive_attempted_at: nil, state: :paused} =
               Repo.reload!(abandoned)

      assert %Sandbox{state: :archived, node_name: nil, archive_key: key} = Repo.reload!(restoring)
      assert key == restoring.archive_key
    end

    test "deletes the archives of restored Orbs, never of archived or errored ones", %{account: account} do
      restored = archived_orb(account, state: :running, node_name: "node-a", archive_key: "restored-key")
      archived = archived_orb(account, amp_orb_id: "still-archived")
      errored = archived_orb(account, amp_orb_id: "errored", state: :error, archive_key: "errored-key")

      expect(Storage, :delete_object, fn "restored-key", _account -> :ok end)

      Archives.run()

      assert %Sandbox{archive_key: nil, archived_at: nil, archive_bytes: nil} = Repo.reload!(restored)
      assert Repo.reload!(archived).archive_key
      assert Repo.reload!(errored).archive_key == "errored-key"
    end
  end

  describe "restoring through Amp" do
    test "a spawn places an archived Orb on any node, cold boots it with fresh credentials and deletes the archive",
         %{account: account} do
      # Archives made before cooldown cleanup was fixed retain their attempt.
      sandbox = archived_orb(account, archive_attempted_at: hours_ago(1))

      expect(Storage, :generate_download_url, fn key, _account, _opts when key == sandbox.archive_key ->
        "https://s3/get"
      end)

      expect(Capacity, :place, fn %Sandbox{state: :creating, node_name: nil} = placed ->
        Repo.update!(Sandbox.update_changeset(placed, %{node_name: "node-b"}))
        {:ok, "node-b"}
      end)

      expect(Nodes, :call, fn "node-b", "create", args, opts ->
        assert args.sandbox_id == sandbox.id
        assert args.from_archive == %{url: "https://s3/get", bytes: 3 * @gib, sha256: "abc123"}
        assert opts[:timeout] > to_timeout(second: 120)
        {:ok, %{"template_tag" => "sha-new"}}
      end)

      expect(Storage, :delete_object, fn key, _account when key == sandbox.archive_key -> :ok end)

      expect(Nodes, :call, fn "node-b", "exec", %{env: env}, _opts ->
        assert env["ORB_TOKEN"] == "fresh"
        {:ok, %{"exit_code" => 0}}
      end)

      assert {:ok, %Sandbox{id: id, state: :running, node_name: "node-b"}} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "spawn", orb_token: "fresh"})

      assert id == sandbox.id

      assert %Sandbox{archive_key: nil, archived_at: nil, archive_attempted_at: nil, residency_work_id: "amp:amp-thread"} =
               restored = Repo.reload!(sandbox)

      assert {:ok, idle} = Sandboxes.end_residency(restored)
      expect(Nodes, :call, fn "node-b", "pause", _args, _opts -> {:ok, %{}} end)
      assert {:ok, %{state: :paused}} = Sandboxes.pause(idle)

      stub(Nodes, :connected_nodes, fn ->
        [Map.merge(@node, %{name: "node-b", disk: %{budget_bytes: 20 * @gib}})]
      end)

      Archives.run()
      assert [job] = all_enqueued(worker: ArchiveSandboxesWorker)
      assert job.args == %{"disk_pressure" => true, "node_names" => ["node-b"]}

      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
      expect(Nodes, :call, fn "node-b", "archive", _args, _opts -> archive_result() end)
      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _account -> :ok end)
      expect(Storage, :object_exists?, fn _key, _account -> true end)
      expect(Nodes, :call, fn "node-b", "delete", _args, _opts -> {:ok, %{}} end)
      assert :ok = perform_job(ArchiveSandboxesWorker, job.args)
      assert Repo.reload!(sandbox).state == :archived
    end

    test "an archive with memory resumes warm on a node of its kind and stays until that node loaded it",
         %{account: account} do
      memory = %{"tail_offset" => 900, "tail_sha256" => "tail", "compat" => "zen5", "node" => "node-d"}
      sandbox = archived_orb(account, archive_memory: memory)
      stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://s3/get" end)

      expect(Capacity, :place, fn placed, filter, opts ->
        assert opts[:avoid] == ["node-d"]
        assert filter.(%{name: "node-b", snapshot_compat: "zen5"})
        refute filter.(%{name: "node-a", snapshot_compat: "zen4"})
        refute filter.(%{name: "node-c"})
        Repo.update!(Sandbox.update_changeset(placed, %{node_name: "node-b"}))
        {:ok, "node-b"}
      end)

      expect(Nodes, :call, fn "node-b", "create", args, _opts ->
        assert args.from_archive ==
                 %{url: "https://s3/get", bytes: 3 * @gib, sha256: "abc123", tail_offset: 900, tail_sha256: "tail"}

        {:ok, %{"memory_pending" => true}}
      end)

      stub(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)
      stub(Storage, :delete_object, fn _key, _account -> flunk("the archive went while its memory was loading") end)

      assert {:ok, %Sandbox{state: :running}} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "spawn", orb_token: "fresh"})

      assert %Sandbox{archive_key: key, archive_memory: %{"loading_since" => _}} = Repo.reload!(sandbox)
      assert key == sandbox.archive_key
      Archives.run()
      assert Repo.reload!(sandbox).archive_key == key

      # Only the node holding it can report it loaded.
      Sandboxes.handle_node_event("node-a", %{"event" => "memory_loaded", "sandbox_id" => sandbox.id})
      assert Repo.reload!(sandbox).archive_key == key

      expect(Storage, :delete_object, fn ^key, _account -> :ok end)
      Sandboxes.handle_node_event("node-b", %{"event" => "memory_loaded", "sandbox_id" => sandbox.id})
      assert %Sandbox{archive_key: nil, archive_memory: nil, archived_at: nil} = Repo.reload!(sandbox)
    end

    test "an archive with lazy disks restores only on nodes that read them", %{account: account} do
      memory = %{
        "tail_offset" => 900,
        "tail_sha256" => "tail",
        "compat" => "zen5",
        "node" => "node-d",
        "lazy_disks" => true
      }

      archived_orb(account, archive_memory: memory)
      stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://s3/get" end)

      expect(Capacity, :place, fn _placed, warm, [avoid: ["node-d"]] ->
        refute warm.(%{name: "node-b", snapshot_compat: "zen5"})
        assert warm.(%{name: "node-b", snapshot_compat: "zen5", lazy_disks: true})
        {:error, :no_node}
      end)

      # Without a node of its kind it cold boots, still only where the disks
      # can be read.
      expect(Capacity, :place, fn placed, any ->
        refute any.(%{name: "node-a", snapshot_compat: "zen4"})
        assert any.(%{name: "node-a", snapshot_compat: "zen4", lazy_disks: true})
        Repo.update!(Sandbox.update_changeset(placed, %{node_name: "node-a"}))
        {:ok, "node-a"}
      end)

      expect(Nodes, :call, fn "node-a", "create", args, _opts ->
        assert args.from_archive.lazy_disks
        {:ok, %{}}
      end)

      stub(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)
      expect(Storage, :delete_object, fn _key, _account -> :ok end)

      assert {:ok, %Sandbox{state: :running, node_name: "node-a"}} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "spawn", orb_token: "fresh"})
    end

    test "an archive with memory cold boots elsewhere when no node of its kind is connected", %{account: account} do
      sandbox =
        archived_orb(account, archive_memory: %{"tail_offset" => 900, "tail_sha256" => "tail", "compat" => "zen5"})

      stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://s3/get" end)
      expect(Capacity, :place, fn _placed, _warm, [avoid: []] -> {:error, :no_node} end)

      expect(Capacity, :place, fn placed, any ->
        assert any.(%{name: "node-a", snapshot_compat: "zen4"})
        Repo.update!(Sandbox.update_changeset(placed, %{node_name: "node-a"}))
        {:ok, "node-a"}
      end)

      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)
      stub(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)
      expect(Storage, :delete_object, fn _key, _account -> :ok end)

      assert {:ok, %Sandbox{state: :running, node_name: "node-a"}} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "spawn", orb_token: "fresh"})

      assert Repo.reload!(sandbox).archive_key == nil
    end

    test "a memory report that beats the create answer still lets the archive go", %{account: account} do
      # The restore placed it and waits on the node's create answer.
      sandbox =
        archived_orb(account,
          state: :creating,
          node_name: "node-b",
          archive_memory: %{"tail_offset" => 900, "tail_sha256" => "tail", "compat" => "zen5"}
        )

      stub(Storage, :delete_object, fn _key, _account -> flunk("the archive went before the restore finished") end)
      Sandboxes.handle_node_event("node-b", %{"event" => "memory_loaded", "sandbox_id" => sandbox.id})
      assert Repo.reload!(sandbox).archive_key == sandbox.archive_key

      running = sandbox |> Repo.reload!() |> Sandbox.update_changeset(%{state: :running}) |> Repo.update!()
      expect(Storage, :delete_object, fn _key, _account -> :ok end)
      assert :ok = Archives.memory_loading(running)
      assert Repo.reload!(sandbox).archive_key == nil
    end

    test "a failed restore keeps the Orb archived for the next spawn", %{account: account} do
      sandbox = archived_orb(account)
      stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://s3/get" end)

      expect(Capacity, :place, fn placed ->
        Repo.update!(Sandbox.update_changeset(placed, %{node_name: "node-b"}))
        {:ok, "node-b"}
      end)

      expect(Nodes, :call, fn "node-b", "create", _args, _opts -> {:error, "restoring archive: checksum mismatch"} end)
      reject(&Storage.delete_object/2)

      assert {:error, "restoring archive: checksum mismatch"} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "spawn", orb_token: "fresh"})

      assert %Sandbox{state: :archived, node_name: nil, archive_key: key} = Repo.reload!(sandbox)
      assert key == sandbox.archive_key
    end

    test "pausing an archived Orb is a no-op and deleting it deletes the archive", %{account: account} do
      sandbox = archived_orb(account)
      reject(&Nodes.call/4)
      assert {:ok, %Sandbox{state: :archived}} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})

      expect(Storage, :delete_object, fn key, _account when key == sandbox.archive_key -> {:error, :unavailable} end)
      assert {:error, :unavailable} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "delete"})
      assert Repo.reload!(sandbox).archive_key == sandbox.archive_key

      expect(Storage, :delete_object, fn _key, _account -> :ok end)
      assert {:ok, nil} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "delete"})
      refute Repo.reload(sandbox)
    end
  end

  describe "node reports" do
    test "remove the jail of an archived sandbox and revert a restore the node lost", %{account: account} do
      archived = archived_orb(account)
      restoring = archived_orb(account, amp_orb_id: "restoring", state: :creating, node_name: "node-a")

      Repo.update_all(from(s in Sandbox, where: s.id == ^restoring.id),
        set: [updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)]
      )

      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: id}, _opts when id == archived.id -> {:ok, %{}} end)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => archived.id, "state" => "paused"}]})

      assert Repo.reload!(archived).state == :archived
      assert %Sandbox{state: :archived, node_name: nil} = Repo.reload!(restoring)
    end
  end

  describe "disk snapshots" do
    test "a ready snapshot is uploaded from its node and kept there", %{account: account} do
      snapshot = disk_snapshot_fixture(account: account, node_name: "node-a")
      assert Archives.queue_disk_snapshot(snapshot)
      assert [job] = all_enqueued(worker: ArchiveDiskSnapshotWorker)
      parent = self()

      expect(Storage, :multipart_start, fn key, %Account{} ->
        assert String.starts_with?(key, Archives.object_prefix(account.id) <> "disk-snapshots/#{snapshot.id}/")
        {:ok, "upload-1"}
      end)

      expect(Nodes, :call, fn "node-a", "archive_disks", args, opts ->
        assert args.snapshot_id == snapshot.id
        assert opts[:timeout] > to_timeout(minute: 30)
        assert length(args.part_urls) * args.part_size > 10 * @gib
        assert Repo.reload!(snapshot).archive_upload_id == "upload-1"
        archive_result()
      end)

      expect(Storage, :multipart_complete_upload, fn key, "upload-1", [{1, _}, {2, _}], _account ->
        send(parent, {:completed, key})
        :ok
      end)

      expect(Storage, :object_exists?, fn _key, _account -> true end)

      assert :ok = perform_job(ArchiveDiskSnapshotWorker, job.args)
      assert_receive {:completed, key}

      assert %DiskSnapshot{
               node_name: "node-a",
               archive_key: ^key,
               archive_upload_id: nil,
               archive_sha256: "deadbeef",
               archived_at: %DateTime{},
               archive_attempted_at: %DateTime{}
             } = Repo.reload!(snapshot)

      assert Archives.archived_bytes(account.id) == 2 * @gib
      refute Archives.queue_disk_snapshot(Repo.reload!(snapshot))
    end

    test "queueing requires archiving on and a ready snapshot, not room in the in-rack budget", %{account: account} do
      snapshot = disk_snapshot_fixture(account: account)
      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      refute Archives.queue_disk_snapshot(snapshot)

      stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)
      archived_orb(account, archive_store: "gra-v1", archive_bytes: 500 * @gib)
      assert Archives.queue_disk_snapshot(snapshot)
      refute Archives.queue_disk_snapshot(disk_snapshot_fixture(account: account_fixture(), state: :saving))
      assert [%{args: %{"disk_snapshot_id" => id}}] = all_enqueued(worker: ArchiveDiskSnapshotWorker)
      assert id == snapshot.id
    end

    test "a failed upload is aborted, keeps the node copy and is retried by the run after five minutes",
         %{account: account} do
      snapshot = disk_snapshot_fixture(account: account)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive_disks", _args, _opts ->
        {:error, ~s(unknown op "archive_disks")}
      end)

      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)

      assert {:error, _reason} = Archives.archive_disk_snapshot(snapshot)

      assert %DiskSnapshot{node_name: "node-a", archive_key: nil, archive_upload_id: nil, archived_at: nil} =
               failed = Repo.reload!(snapshot)

      assert failed.archive_attempted_at

      Archives.run()
      assert [] = all_enqueued(worker: ArchiveDiskSnapshotWorker)

      Repo.update_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id),
        set: [archive_attempted_at: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -6, :minute)]
      )

      Archives.run()
      assert [%{args: %{"disk_snapshot_id" => id}}] = all_enqueued(worker: ArchiveDiskSnapshotWorker)
      assert id == snapshot.id
    end

    test "a snapshot deleted while uploading is not recorded and its upload is aborted", %{account: account} do
      snapshot = disk_snapshot_fixture(account: account)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive_disks", _args, _opts ->
        # A newer save supersedes it while the node uploads.
        expect(Nodes, :call, fn "node-a", "delete_disks", _args, _opts -> {:ok, %{}} end)
        expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
        expect(Storage, :delete_object, fn _key, _account -> :ok end)
        assert :ok = DiskSnapshots.delete(Repo.reload!(snapshot))
        archive_result()
      end)

      reject(&Storage.multipart_complete_upload/4)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)

      assert {:ok, :skipped} = Archives.archive_disk_snapshot(snapshot)
      refute Repo.reload(snapshot)
    end

    test "node transport interruptions do not back off snapshot archives", %{account: account} do
      for reason <- [:not_connected, :node_disconnected, :timeout] do
        snapshot = disk_snapshot_fixture(account: account)
        expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)
        expect(Nodes, :call, fn "node-a", "archive_disks", _args, _opts -> {:error, reason} end)
        expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
        assert {:error, ^reason} = Archives.archive_disk_snapshot(snapshot)

        assert %DiskSnapshot{node_name: "node-a", archive_upload_id: nil, archive_attempted_at: nil} =
                 Repo.reload!(snapshot)
      end
    end

    test "aborts abandoned snapshot uploads", %{account: account} do
      snapshot =
        disk_snapshot_fixture(
          account: account,
          archive_key: "k",
          archive_upload_id: "upload-old",
          archive_attempted_at: hours_ago(2)
        )

      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      expect(Storage, :multipart_abort, fn "k", "upload-old", _account -> :ok end)

      Archives.run()

      assert %DiskSnapshot{archive_key: nil, archive_upload_id: nil, archive_attempted_at: nil} = Repo.reload!(snapshot)
    end
  end

  describe "in-rack stores" do
    @store %{
      "site" => "gra",
      "enabled" => true,
      "private_network_ready" => true,
      "endpoint" => "http://shard-storage.kura.svc.cluster.local:3900",
      "bucket" => "shards",
      "archive_bucket" => "sandbox-archives",
      "archive_capacity_urls" => ["http://shard-storage.kura.svc.cluster.local:3903/metrics"],
      "region" => "garage",
      "access_key_id" => "GK0123",
      "secret_access_key" => "secret"
    }

    setup do
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => @store} end)
      stub(Storage, :available?, fn %S3Target{bucket: "sandbox-archives"} -> true end)

      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: capacity_metrics(200 * @gib, 200 * @gib)}}
      end)

      stub(Sites, :shard_storage_site, fn node -> if node in ["node-a", "node-b"], do: "gra" end)
      :ok
    end

    defp capacity_metrics(data, metadata) do
      """
      # HELP garage_local_disk_avail Garage available disk space on each node
      # TYPE garage_local_disk_avail gauge
      garage_local_disk_avail{volume="data"} #{data}
      garage_local_disk_avail{volume="metadata"} #{metadata}
      garage_local_disk_total{volume="data"} #{300 * @gib}
      """
    end

    defp copy_metadata(account, content) do
      [
        archive_store: "gra-v1",
        archive_key: "sandbox-archives/#{account.id}/#{Ecto.UUID.generate()}/original.sbxa",
        archive_bytes: byte_size(content),
        archive_sha256: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
      ]
    end

    defp copy_storage(content) do
      stub(Storage, :stream_object, fn _key, _actor -> Stream.map(content, & &1) end)

      stub(Storage, :upload, fn source, _key, %Account{} ->
        assert source |> Enum.to_list() |> IO.iodata_to_binary() == IO.iodata_to_binary(content)
        %{status_code: 200}
      end)

      stub(Storage, :object_exists?, fn _key, %Account{} -> true end)
    end

    test "offload streams use valid S3 multipart parts and preserve the final short tail", %{account: account} do
      mib = 1024 * 1024
      chunks = List.duplicate(:binary.copy("x", mib), 32) ++ ["tail"]
      original = archived_orb(account, copy_metadata(account, IO.iodata_to_binary(chunks)))
      store = Map.put(@store, "archive_budget_bytes", 1)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(chunks)

      expect(Storage, :upload, fn source, _key, %Account{} ->
        parts = Enum.to_list(source)
        assert Enum.all?(Enum.drop(parts, -1), &(byte_size(&1) >= 5 * mib))
        assert IO.iodata_to_binary(parts) == IO.iodata_to_binary(chunks)
        assert List.last(parts) == "tail"
        %{}
      end)

      assert :ok = Archives.offload_oldest("gra-v1", 0)
      assert Repo.reload!(original).archive_store == nil
    end

    test "offloads oldest Orb and snapshot archives across accounts, preserving newer data", %{account: account} do
      store = Map.put(@store, "archive_budget_bytes", 12)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      oldest = archived_orb(account, copy_metadata(account, "old!") ++ [archived_at: hours_ago(9)])
      other = account_fixture()

      snapshot =
        disk_snapshot_fixture(
          copy_metadata(other, "middle") ++ [account: other, archived_at: hours_ago(8), node_name: nil]
        )

      newest =
        archived_orb(account, copy_metadata(account, "new-data") ++ [amp_orb_id: "newest", archived_at: hours_ago(7)])

      # Archives in account storage or another rack must never be selected,
      # even when they are older than every candidate in this rack.
      archived_orb(account, amp_orb_id: "account-copy", archived_at: hours_ago(30))
      archived_orb(account, amp_orb_id: "other-rack", archive_store: "other", archived_at: hours_ago(31))
      content = %{oldest.archive_key => "old!", snapshot.archive_key => "middle"}
      test_pid = self()

      stub(Storage, :stream_object, fn key, %S3Target{id: "gra-v1"} ->
        [Map.fetch!(content, key)]
      end)

      stub(Storage, :upload, fn source, key, account ->
        chunks = Enum.to_list(source)
        expect(Storage, :stream_object, fn ^key, %Account{} -> chunks end)
        send(test_pid, {:copied, account.id, IO.iodata_to_binary(chunks)})
        %{}
      end)

      stub(Storage, :object_exists?, fn _key, _actor -> true end)
      reject(&Storage.delete_object/2)
      assert :ok = perform_job(OffloadArchivesWorker, %{store: "gra-v1", max_bytes: 0})
      assert_receive {:copied, account_id, "old!"}
      assert account_id == account.id
      assert_receive {:copied, other_id, "middle"}
      assert other_id == other.id
      refute_receive {:copied, _, _}

      for original <- [oldest, snapshot] do
        fresh = Repo.reload!(original)
        assert fresh.archive_store == nil
        refute fresh.archive_key == original.archive_key
        assert Path.dirname(fresh.archive_key) == Path.dirname(original.archive_key)
        assert fresh.archive_sha256 == original.archive_sha256
        assert fresh.archived_at == original.archived_at
        assert fresh.archive_bytes == original.archive_bytes
        assert Archives.restore_site(fresh) == nil
      end

      assert Repo.reload!(newest).archive_store == "gra-v1"
      cleanups = all_enqueued(worker: DeleteArchiveCopyWorker)
      assert length(cleanups) == 4

      for cleanup <- cleanups do
        assert DateTime.diff(cleanup.scheduled_at, DateTime.utc_now()) in 7190..7200
      end

      # Even with stale capacity readings, already retiring bytes prevent
      # repeatedly offloading newer data before the old copies are reclaimed.
      assert :ok = Archives.offload_oldest("gra-v1", 0)
      assert length(all_enqueued(worker: DeleteArchiveCopyWorker)) == 4
    end

    test "physical pressure offloads only enough old data, counting pending reclamation", %{account: account} do
      oldest = archived_orb(account, copy_metadata(account, "old-data") ++ [archived_at: hours_ago(9)])
      newer = archived_orb(account, copy_metadata(account, "new-data") ++ [amp_orb_id: "newer"])
      copy_storage(["old-", "data"])

      # Budget is well below its limit, but a replica has eight bytes less
      # than the upload plus safety margin needs.
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: capacity_metrics(@gib + 12, 200 * @gib)}}
      end)

      assert :ok = Archives.offload_oldest("gra-v1", 20)
      assert Repo.reload!(oldest).archive_store == nil
      assert Repo.reload!(newer).archive_store == "gra-v1"
      reject(&Storage.upload/3)
      assert :ok = Archives.offload_oldest("gra-v1", 20)
      assert Repo.reload!(newer).archive_store == "gra-v1"
    end

    test "does not move data solely because capacity is unknown or a store is disabled", %{account: account} do
      original = archived_orb(account, copy_metadata(account, "content"))
      stub(Req, :get, fn _url, _opts -> {:error, :timeout} end)
      reject(&Storage.upload/3)
      assert :ok = Archives.offload_oldest("gra-v1", 100 * @gib)
      disabled = @store |> Map.put("archive_budget_bytes", 1) |> Map.put("enabled", false)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => disabled} end)
      assert :ok = Archives.offload_oldest("gra-v1", 100 * @gib)
      assert Repo.reload!(original).archive_store == "gra-v1"
    end

    test "uploads keep falling back until retired rack copies are deleted", %{account: account} do
      original = archived_orb(account, copy_metadata(account, "original"))
      store = Map.put(@store, "archive_budget_bytes", 8)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(["original"])
      assert :ok = Archives.offload_oldest("gra-v1", 0)
      assert Repo.reload!(original).archive_store == nil
      source = Enum.find(all_enqueued(worker: DeleteArchiveCopyWorker), &(&1.args["store"] == "gra-v1"))

      stub(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _actor -> :ok end)
      stub(Storage, :object_exists?, fn _key, _actor -> true end)
      stub(Nodes, :call, fn _node, op, _args, _opts -> if op == "delete", do: {:ok, %{}}, else: archive_result() end)
      expect(Storage, :multipart_start, fn _key, %Account{} -> {:ok, "upload-1"} end)
      assert {:ok, %{archive_store: nil}} = Archives.archive(paused_orb(account))
      assert_enqueued(worker: OffloadArchivesWorker, args: %{store: "gra-v1"})

      # Oban executes and completes the durable cleanup obligation. Only
      # then may the logical budget stop charging the retired source copy.
      stub(Storage, :delete_object, fn _key, %S3Target{} -> :ok end)
      assert :ok = perform_job(DeleteArchiveCopyWorker, source.args)
      Repo.update!(Ecto.Changeset.change(source, state: "completed", completed_at: DateTime.utc_now()))
      expect(Storage, :multipart_start, fn _key, %S3Target{id: "gra-v1"} -> {:ok, "upload-1"} end)
      assert {:ok, %{archive_store: "gra-v1"}} = Archives.archive(paused_orb(account))
    end

    test "competing offload callers do not copy the same oldest archive concurrently", %{account: account} do
      original = archived_orb(account, copy_metadata(account, "original"))
      store = Map.put(@store, "archive_budget_bytes", 1)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(["original"])
      parent = self()

      stub(Storage, :upload, fn source, _key, _account ->
        assert Enum.to_list(source) == ["original"]
        send(parent, {:copying, self()})

        receive do
          :finish_copy -> %{}
        after
          5_000 -> flunk("copy was not released")
        end
      end)

      task = Task.async(fn -> Archives.offload_oldest("gra-v1", 0) end)

      try do
        assert_receive {:copying, copier}, 5_000
        assert {:snooze, 60} = Archives.offload_oldest("gra-v1", 0)
        assert Repo.reload!(original).archive_store == "gra-v1"
        send(copier, :finish_copy)
        assert :ok = Task.await(task)
        assert Repo.reload!(original).archive_store == nil
      after
        Task.shutdown(task, :brutal_kill)
      end
    end

    test "cleanup survives account deletion, including its custom storage credentials", %{account: account} do
      account =
        Repo.update!(
          Ecto.Changeset.change(account,
            s3_bucket_name: "custom-bucket",
            s3_access_key_id: "custom-key",
            s3_secret_access_key: "custom-secret"
          )
        )

      archived_orb(account, copy_metadata(account, "original"))
      store = Map.put(@store, "archive_budget_bytes", 1)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(["original"])

      stub(Storage, :upload, fn source, _key, _account ->
        Enum.to_list(source)
        Repo.delete!(account)
        %{}
      end)

      assert :ok = Archives.offload_oldest("gra-v1", 0)
      assert [cleanup] = all_enqueued(worker: DeleteArchiveCopyWorker)
      refute inspect(cleanup.args) =~ "custom-secret"

      expect(Storage, :delete_object, fn _key,
                                         %Account{s3_bucket_name: "custom-bucket", s3_secret_access_key: "custom-secret"} ->
        :ok
      end)

      assert :ok = perform_job(DeleteArchiveCopyWorker, cleanup.args)
    end

    test "a truncated or same-size corrupted destination never replaces the only good copy", %{account: account} do
      original = archived_orb(account, copy_metadata(account, "original"))
      store = Map.put(@store, "archive_budget_bytes", 1)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(["original"])
      reject(&Storage.delete_object/2)

      for bad <- ["short", "corrupt!"] do
        stub(Storage, :stream_object, fn
          _key, %S3Target{} -> ["original"]
          _key, %Account{} -> [bad]
        end)

        assert {:error, :archive_copy_mismatch} = Archives.offload_oldest("gra-v1", 0)
        assert Repo.reload!(original).archive_key == original.archive_key
        assert Repo.reload!(original).archive_store == "gra-v1"
      end

      assert length(all_enqueued(worker: DeleteArchiveCopyWorker)) == 2
      for cleanup <- all_enqueued(worker: DeleteArchiveCopyWorker), do: assert(cleanup.args["store"] == nil)
    end

    test "upload failure and worker death leave durable cleanup without changing the route", %{account: account} do
      original = archived_orb(account, copy_metadata(account, "original"))
      store = Map.put(@store, "archive_budget_bytes", 1)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(["original"])
      stub(Storage, :upload, fn _source, _key, _account -> {:error, :unavailable} end)
      assert {:error, :unavailable} = Archives.offload_oldest("gra-v1", 0)
      stub(Storage, :upload, fn _source, _key, _account -> raise "transfer interrupted" end)
      assert_raise RuntimeError, "transfer interrupted", fn -> Archives.offload_oldest("gra-v1", 0) end
      assert Repo.reload!(original).archive_store == "gra-v1"

      cleanups = all_enqueued(worker: DeleteArchiveCopyWorker)
      assert length(cleanups) == 2
      assert length(Enum.uniq_by(cleanups, & &1.args["key"])) == 2
      stub(Storage, :delete_object, fn _key, %Account{} -> :ok end)
      for job <- cleanups, do: assert(:ok = perform_job(DeleteArchiveCopyWorker, job.args))
    end

    test "a restore or delete during copying wins and the unpublished copy is cleaned up", %{account: account} do
      store = Map.put(@store, "archive_budget_bytes", 1)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(["original"])

      for action <- [:restore, :delete] do
        original =
          archived_orb(account, copy_metadata(account, "original") ++ [amp_orb_id: Atom.to_string(action)])

        stub(Storage, :upload, fn source, _key, _account ->
          Enum.to_list(source)

          case action do
            :restore -> Repo.update!(Sandbox.update_changeset(original, %{state: :creating}))
            :delete -> Repo.delete!(original)
          end

          %{}
        end)

        assert :ok = Archives.offload_oldest("gra-v1", 0)
        if action == :restore, do: assert(Repo.reload!(original).archive_store == "gra-v1")
      end

      cleanups = all_enqueued(worker: DeleteArchiveCopyWorker)
      assert length(cleanups) == 2
      for job <- cleanups, do: assert(job.args["store"] == nil)
      stub(Storage, :delete_object, fn _key, %Account{} -> :ok end)
      for job <- cleanups, do: assert(:ok = perform_job(DeleteArchiveCopyWorker, job.args))
    end

    test "offloaded snapshots restore and delete from the new route even with a stale caller", %{account: account} do
      original =
        disk_snapshot_fixture(copy_metadata(account, "original") ++ [account: account, archived_at: hours_ago(9)])

      store = Map.put(@store, "archive_budget_bytes", 1)
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
      copy_storage(["ori", "ginal"])
      assert :ok = Archives.offload_oldest("gra-v1", 0)
      fresh = Repo.reload!(original)

      expect(Storage, :generate_download_url, fn key, %Account{}, _opts ->
        assert key == fresh.archive_key
        "https://account-storage/archive"
      end)

      assert {:ok, %{url: "https://account-storage/archive"}} = Archives.restore_source(original)
      stub(Storage, :delete_object, fn _key, _actor -> flunk("must not delete the active archive") end)
      destination = Enum.find(all_enqueued(worker: DeleteArchiveCopyWorker), &is_nil(&1.args["store"]))
      assert :ok = perform_job(DeleteArchiveCopyWorker, destination.args)

      expect(Storage, :delete_object, fn key, %Account{} ->
        assert key == fresh.archive_key
        :ok
      end)

      stub(Nodes, :call, fn _node, "delete_disks", _args, _opts -> {:ok, %{}} end)
      assert :ok = DiskSnapshots.delete(original)
      refute Repo.get(DiskSnapshot, original.id)

      source = Enum.find(all_enqueued(worker: DeleteArchiveCopyWorker), &(&1.args["store"] == "gra-v1"))

      expect(Storage, :delete_object, fn key, %S3Target{id: "gra-v1"} ->
        assert key == original.archive_key
        {:error, :unavailable}
      end)

      assert {:snooze, 300} = perform_job(DeleteArchiveCopyWorker, source.args)

      expect(Storage, :delete_object, fn key, %S3Target{id: "gra-v1"} ->
        assert key == original.archive_key
        :ok
      end)

      assert :ok = perform_job(DeleteArchiveCopyWorker, source.args)
    end

    test "physical space must fit the full Orb or snapshot archive plus headroom", %{account: account} do
      # 4 GiB rootfs + 7 GiB workspace + 64 MiB disk overhead + 512 MiB
      # kernel, for an Orb also its 4 GiB of memory and 64 MiB of VM state,
      # then 1% framing/compression allowance and 1 GiB headroom.
      snapshot_bytes = 11 * @gib + 576 * 1024 * 1024
      orb_bytes = snapshot_bytes + 4 * @gib + 64 * 1024 * 1024

      for {subject, uncompressed} <- [orb: orb_bytes, snapshot: snapshot_bytes],
          required = uncompressed + div(uncompressed, 100) + @gib,
          volume <- [:data, :metadata],
          offset <- [-1, 0, 1] do
        {data, metadata} =
          if volume == :data, do: {required + offset, 200 * @gib}, else: {200 * @gib, required + offset}

        stub(Req, :get, fn _url, _opts ->
          {:ok, %Req.Response{status: 200, body: capacity_metrics(data, metadata)}}
        end)

        expected_store = if offset >= 0, do: "gra-v1"

        stub(Storage, :multipart_start, fn _key, actor ->
          if expected_store, do: assert(%S3Target{id: "gra-v1"} = actor), else: assert(%Account{} = actor)
          {:ok, "upload-1"}
        end)

        stub(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _actor -> :ok end)
        stub(Storage, :object_exists?, fn _key, _actor -> true end)

        stub(Nodes, :call, fn "node-a", op, _args, _opts ->
          if op == "delete", do: {:ok, %{}}, else: archive_result()
        end)

        if subject == :orb do
          assert {:ok, archived} = Archives.archive(paused_orb(account, workspace_gb: 7))
          assert archived.archive_store == expected_store
        else
          snapshot = disk_snapshot_fixture(account: account, workspace_gb: 7)
          assert {:ok, snapshot} = Archives.archive_disk_snapshot(snapshot)
          assert snapshot.archive_store == expected_store
        end
      end
    end

    test "unknown physical capacity uses account storage without blocking archives", %{account: account} do
      stub(Storage, :multipart_start, fn _key, %Account{} -> {:ok, "upload-1"} end)
      stub(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, %Account{} -> :ok end)
      stub(Storage, :object_exists?, fn _key, %Account{} -> true end)
      stub(Nodes, :call, fn "node-a", op, _args, _opts -> if op == "delete", do: {:ok, %{}}, else: archive_result() end)

      for response <- [
            {:error, %Req.TransportError{reason: :timeout}},
            {:ok, %Req.Response{status: 503, body: "unavailable"}},
            {:ok, %Req.Response{status: 200, body: ""}},
            {:ok, %Req.Response{status: 200, body: "garage_local_disk_avail{volume=\"data\"} 999999999999\n"}},
            {:ok, %Req.Response{status: 200, body: capacity_metrics("NaN", "NaN")}},
            {:ok, %Req.Response{status: 200, body: capacity_metrics("+Inf", "+Inf")}},
            {:ok, %Req.Response{status: 200, body: %{}}}
          ] do
        stub(Req, :get, fn _url, _opts -> response end)
        assert {:ok, %{archive_store: nil}} = Archives.archive(paused_orb(account))
      end

      reject(&Req.get/2)

      for store <- [Map.delete(@store, "archive_capacity_urls"), Map.put(@store, "archive_capacity_urls", [])] do
        stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)
        assert {:ok, %{archive_store: nil}} = Archives.archive(paused_orb(account))
      end
    end

    test "a replicated store falls back when any replica is full", %{account: account} do
      store = Map.put(@store, "archive_capacity_urls", ["http://replica-0/metrics", "http://replica-1/metrics"])
      stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)

      stub(Req, :get, fn url, _opts ->
        bytes = if url == "http://replica-0/metrics", do: 200 * @gib, else: 0
        {:ok, %Req.Response{status: 200, body: capacity_metrics(bytes, bytes)}}
      end)

      expect(Storage, :multipart_start, fn _key, %Account{} -> {:ok, "upload-1"} end)
      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, %Account{} -> :ok end)
      expect(Storage, :object_exists?, fn _key, %Account{} -> true end)
      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> archive_result() end)
      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %{archive_store: nil}} = Archives.archive(paused_orb(account))
    end

    for budget_gib <- [nil, 100, 500], offset <- [-1, 0, 1] do
      @budget_gib budget_gib
      @offset offset
      test "routes new Orb and snapshot archives with budget #{inspect(budget_gib)} GiB at offset #{offset}",
           %{account: account} do
        budget = (@budget_gib || 100) * @gib
        store = if @budget_gib, do: Map.put(@store, "archive_budget_bytes", budget), else: @store
        stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => store} end)

        # Account storage and other rack stores must not consume this budget.
        archived_orb(account, archive_bytes: 600 * @gib)
        archived_orb(account, amp_orb_id: "other-store", archive_store: "retired-store", archive_bytes: 600 * @gib)

        # Share one store's budget across accounts and count restored Orbs
        # awaiting deletion as well as snapshots whose node copy is gone.
        retained =
          archived_orb(account_fixture(),
            amp_orb_id: "restored",
            state: :running,
            archive_store: "gra-v1",
            archive_bytes: budget - 20 * @gib
          )

        disk_snapshot_fixture(
          account: account,
          node_name: nil,
          archived_at: hours_ago(1),
          archive_store: "gra-v1",
          archive_bytes: 20 * @gib + @offset,
          archive_key: "snapshot.sbxa"
        )

        sandbox = paused_orb(account)
        snapshot = disk_snapshot_fixture(account: account)

        expected_store = if @offset < 0, do: "gra-v1"

        stub(Storage, :multipart_start, fn _key, actor ->
          case expected_store do
            nil ->
              assert %Account{id: id} = actor
              assert id == account.id

            "gra-v1" ->
              assert %S3Target{id: "gra-v1"} = actor
          end

          {:ok, "upload-1"}
        end)

        stub(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, _actor -> :ok end)
        stub(Storage, :object_exists?, fn _key, _actor -> true end)

        stub(Nodes, :call, fn "node-a", op, _args, _opts ->
          if op == "delete", do: {:ok, %{}}, else: archive_result()
        end)

        assert {:ok, archived} = Archives.archive(sandbox)
        assert archived.archive_store == expected_store

        # Remove only the newly written object from the accounting to test
        # both kinds against the exact same boundary.
        Repo.update!(Ecto.Changeset.change(archived, archived_at: nil))
        assert {:ok, archived_snapshot} = Archives.archive_disk_snapshot(snapshot)
        assert archived_snapshot.archive_store == expected_store

        if expected_store == nil do
          # Even if rack usage later falls, reads/deletes must keep using
          # the recorded account-storage route, not select a new store.
          Repo.delete!(retained)
          assert Archives.restore_site(archived) == nil

          expect(Storage, :generate_download_url, fn key, %Account{id: id}, _opts ->
            assert key == archived.archive_key
            assert id == account.id
            "https://account-storage/archive"
          end)

          assert {:ok, %{url: "https://account-storage/archive", bytes: bytes, sha256: "deadbeef"}} =
                   Archives.restore_source(archived)

          assert bytes == 2 * @gib

          expect(Storage, :delete_object, fn key, %Account{id: id} ->
            assert key == archived_snapshot.archive_key
            assert id == account.id
            :ok
          end)

          assert :ok = Archives.delete_disk_snapshot_archive(archived_snapshot)
        end
      end
    end

    test "archive an Orb to the store at its node's site and restore it on a node at that site", %{account: account} do
      sandbox = paused_orb(account)

      expect(Storage, :multipart_start, fn _key, %S3Target{id: "gra-v1", bucket: "sandbox-archives"} ->
        {:ok, "upload-1"}
      end)

      expect(Nodes, :call, fn "node-a", "archive", _args, _opts -> archive_result() end)
      expect(Storage, :multipart_complete_upload, fn _key, "upload-1", _parts, %S3Target{id: "gra-v1"} -> :ok end)
      expect(Storage, :object_exists?, fn _key, %S3Target{id: "gra-v1"} -> true end)
      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)

      Archives.run()

      assert %Sandbox{state: :archived, archive_store: "gra-v1", archive_key: key} = archived = Repo.reload!(sandbox)
      assert Archives.restore_site(archived) == "gra"

      expect(Storage, :generate_download_url, fn ^key, %S3Target{bucket: "sandbox-archives"}, _opts ->
        "http://shard-storage/get"
      end)

      expect(Capacity, :place, fn %Sandbox{state: :creating} = placed, node_filter ->
        assert node_filter.(%{name: "node-b"})
        refute node_filter.(%{name: "node-c"})
        Repo.update!(Sandbox.update_changeset(placed, %{node_name: "node-b"}))
        {:ok, "node-b"}
      end)

      expect(Nodes, :call, fn "node-b", "create", %{from_archive: %{url: "http://shard-storage/get"}}, _opts ->
        {:ok, %{"template_tag" => "sha-new"}}
      end)

      expect(Storage, :delete_object, fn ^key, %S3Target{id: "gra-v1"} -> :ok end)
      expect(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %Sandbox{state: :running, node_name: "node-b"}} =
               AmpOrbs.dispatch(account, sandbox.amp_orb_id, %{operation: "spawn", orb_token: "fresh"})

      assert %Sandbox{archive_key: nil, archive_store: nil, archived_at: nil} = Repo.reload!(sandbox)
    end

    test "archives stay in the account's storage off the store's site and for accounts with their own storage",
         %{account: account} do
      off_site = paused_orb(account, node_name: "node-c")
      stub(Nodes, :connected_nodes, fn -> [@node, %{@node | name: "node-c"}] end)
      stub(Nodes, :call, fn _node, "archive", _args, _opts -> {:error, :unavailable} end)

      expect(Storage, :multipart_start, fn _key, %Account{id: id} when id == account.id -> {:ok, "upload-1"} end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", %Account{} -> :ok end)
      assert {:error, :unavailable} = Archives.archive(off_site)

      custom =
        Repo.update!(
          Ecto.Changeset.change(account_fixture(),
            s3_bucket_name: "custom",
            s3_access_key_id: "key",
            s3_secret_access_key: "secret"
          )
        )

      reject(&Sites.shard_storage_site/1)
      expect(Storage, :multipart_start, fn _key, %Account{id: id} when id == custom.id -> {:ok, "upload-1"} end)
      expect(Storage, :multipart_abort, fn _key, "upload-1", %Account{} -> :ok end)
      assert {:error, :unavailable} = Archives.archive(paused_orb(custom))
    end

    test "an archive whose store is no longer configured stays archived", %{account: account} do
      sandbox = archived_orb(account, archive_store: "gra-v0")
      reject(&Capacity.place/2)
      reject(&Storage.delete_object/2)

      assert {:error, :archive_store_unavailable} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "spawn", orb_token: "fresh"})

      assert %Sandbox{state: :archived, archive_store: "gra-v0"} = Repo.reload!(sandbox)

      assert {:error, :archive_store_unavailable} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "delete"})
      assert %Sandbox{archive_key: key, archive_store: "gra-v0"} = Repo.reload!(sandbox)
      assert key == sandbox.archive_key
    end

    test "purging an account deletes its archives in its storage and in every store", %{account: account} do
      prefix = Archives.object_prefix(account.id)
      expect(Storage, :delete_all_objects, fn ^prefix, %Account{} -> :ok end)
      expect(Storage, :delete_all_objects, fn ^prefix, %S3Target{id: "gra-v1", bucket: "sandbox-archives"} -> :ok end)
      assert :ok = Archives.purge_account(account)
    end
  end
end
