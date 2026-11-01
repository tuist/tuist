defmodule Tuist.Sandboxes.ArchivesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpOrbs
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker
  alias Tuist.Storage

  @gib 1024 * 1024 * 1024
  @node %{name: "node-a", templates: [%{name: "default", ready: true, rootfs_bytes: 4 * @gib}]}

  setup do
    account = account_fixture()
    stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)
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

  describe "enqueue_if_over_cap/1" do
    test "queues a run once an account keeps more paused Orbs on nodes than the cap", %{account: account} do
      for _ <- 1..Archives.max_paused_on_node_per_account(), do: paused_orb(account, paused_at: hours_ago(1))
      assert :ok = Archives.enqueue_if_over_cap(account.id)
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)

      paused_orb(account, paused_at: hours_ago(1))
      assert :ok = Archives.enqueue_if_over_cap(account.id)
      assert [_job] = all_enqueued(worker: ArchiveSandboxesWorker)
    end

    test "queues nothing while archiving is off", %{account: account} do
      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      for _ <- 0..Archives.max_paused_on_node_per_account(), do: paused_orb(account, paused_at: hours_ago(1))
      assert :ok = Archives.enqueue_if_over_cap(account.id)
      assert [] = all_enqueued(worker: ArchiveSandboxesWorker)
    end
  end

  describe "run/0" do
    test "archives Orbs paused past the threshold and removes them from their node", %{account: account} do
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
               archive_sha256: "deadbeef",
               archived_at: %DateTime{}
             } = archived = Repo.reload!(sandbox)

      assert archived.archive_bytes == 2 * @gib
      assert Repo.reload!(recent).state == :paused
      assert Archives.archived_bytes(account.id) == 2 * @gib
    end

    test "does nothing but clean up while no threshold is configured", %{account: account} do
      stub(Environment, :sandbox_archive_after_hours, fn -> nil end)
      sandbox = paused_orb(account)
      reject(&Storage.multipart_start/2)
      reject(&Nodes.call/4)
      Archives.run()
      assert Repo.reload!(sandbox).state == :paused
    end

    test "archives the least recently paused Orbs of an account over the on-node cap", %{account: account} do
      oldest = paused_orb(account, paused_at: hours_ago(3))

      for n <- 1..Archives.max_paused_on_node_per_account(),
          do: paused_orb(account, paused_at: DateTime.add(hours_ago(2), n, :minute))

      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", %{sandbox_id: id}, _opts ->
        assert id == oldest.id
        {:error, "object storage answered 503"}
      end)

      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)
      Archives.run()
    end

    test "leaves non-Amp sandboxes, busy Orbs and accounts at their archive cap alone", %{account: account} do
      sandbox_fixture(account: account, state: :paused, node_name: "node-a", paused_at: hours_ago(48))
      paused_orb(account, residency_work_id: "amp:busy")
      capped = account_fixture()
      paused_orb(capped)
      archived_orb(capped, archive_bytes: Archives.max_archived_bytes_per_account())
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
      reject(&Nodes.call/4)
      Archives.run()
    end

    test "an Orb resumed during the upload stays hot and the upload is discarded", %{account: account} do
      sandbox = paused_orb(account)
      expect(Storage, :multipart_start, fn _key, _account -> {:ok, "upload-1"} end)

      expect(Nodes, :call, fn "node-a", "archive", _args, _opts ->
        # A resume and a new pause land while the node uploads.
        Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id),
          set: [paused_at: DateTime.truncate(DateTime.utc_now(), :second)]
        )

        archive_result()
      end)

      reject(&Storage.multipart_complete_upload/4)
      expect(Storage, :multipart_abort, fn _key, "upload-1", _account -> :ok end)

      Archives.run()

      assert %Sandbox{state: :paused, node_name: "node-a", archive_key: nil, archived_at: nil} = Repo.reload!(sandbox)
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

      assert %Sandbox{archive_upload_id: nil, archive_key: nil, state: :paused} = Repo.reload!(abandoned)
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
      sandbox = archived_orb(account)

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

      assert %Sandbox{archive_key: nil, archived_at: nil, residency_work_id: "amp:amp-thread"} =
               Repo.reload!(sandbox)
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

    test "archived Orbs do not count toward the on-node cap, a restore does", %{account: account} do
      for n <- 1..Sandboxes.max_on_node_sandboxes_per_account(), do: archived_orb(account, amp_orb_id: "archived-#{n}")
      expect(Capacity, :place, fn _sandbox -> {:error, :no_capacity} end)
      assert {:error, :no_capacity} = Sandboxes.create_sandbox(account, %{})

      account = account_fixture()
      sandbox = archived_orb(account)
      for _ <- 1..Sandboxes.max_on_node_sandboxes_per_account(), do: paused_orb(account, amp_orb_id: nil)
      stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://s3/get" end)
      reject(&Capacity.place/1)

      assert {:error, :sandbox_limit} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "spawn", orb_token: "fresh"})

      assert Repo.reload!(sandbox).state == :archived
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
end
