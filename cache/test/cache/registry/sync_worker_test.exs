defmodule Cache.Registry.SyncWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Registry.LeaderElection
  alias Cache.Registry.SyncWorker

  @moduletag capture_log: true

  setup :set_mimic_global

  describe "perform/1" do
    test "skips sync when not leader" do
      expect(LeaderElection, :try_acquire_lock, fn ->
        {:error, :already_locked}
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "syncs packages when leader and releases lock after" do
      packages = [
        %{"scope" => "apple", "name" => "swift-argument-parser"},
        %{"scope" => "swift", "name" => "swift-nio"}
      ]

      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn url, _opts ->
        assert String.ends_with?(url, "/api/registry/swift/packages")
        {:ok, %Req.Response{status: 200, body: packages}}
      end)

      expect(Oban, :insert, 2, fn changeset ->
        assert changeset.changes.queue == "registry_sync"
        assert changeset.changes.worker == "Cache.Registry.ReleaseWorker"
        {:ok, %Oban.Job{}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "releases lock even when fetch fails" do
      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:error, :timeout}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert {:error, :timeout} = SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "handles packages with repository_full_handle format" do
      packages = [
        %{"repository_full_handle" => "apple/swift-argument-parser"},
        %{"repository_full_handle" => "swift/swift-nio"}
      ]

      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: packages}}
      end)

      expect(Oban, :insert, 2, fn changeset ->
        args = changeset.changes.args
        assert is_binary(args[:scope])
        assert is_binary(args[:name])
        {:ok, %Oban.Job{}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "handles server response with nested data structure" do
      packages = [%{"scope" => "apple", "name" => "swift-argument-parser"}]

      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"packages" => packages}}}
      end)

      expect(Oban, :insert, fn changeset ->
        args = changeset.changes.args
        assert args[:scope] == "apple"
        assert args[:name] == "swift-argument-parser"
        {:ok, %Oban.Job{}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "handles server response with data key" do
      packages = [%{"scope" => "apple", "name" => "swift-argument-parser"}]

      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"data" => packages}}}
      end)

      expect(Oban, :insert, fn changeset ->
        args = changeset.changes.args
        assert args[:scope] == "apple"
        assert args[:name] == "swift-argument-parser"
        {:ok, %Oban.Job{}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "skips packages with missing scope or name" do
      packages = [
        %{"scope" => "apple", "name" => "swift-argument-parser"},
        %{"invalid" => "package"},
        %{"scope" => "swift"}
      ]

      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: packages}}
      end)

      expect(Oban, :insert, fn changeset ->
        args = changeset.changes.args
        assert args[:scope] == "apple"
        assert args[:name] == "swift-argument-parser"
        {:ok, %Oban.Job{}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "handles HTTP error from server" do
      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: "Internal Server Error"}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert {:error, {:http_error, 500, "Internal Server Error"}} =
               SyncWorker.perform(%Oban.Job{args: %{}})
    end

    test "handles empty package list" do
      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end
  end

  describe "ReleaseWorker job creation" do
    test "creates jobs with correct queue and args" do
      packages = [%{"scope" => "apple", "name" => "swift-argument-parser"}]

      expect(LeaderElection, :try_acquire_lock, fn ->
        {:ok, :acquired}
      end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: packages}}
      end)

      expect(Oban, :insert, fn changeset ->
        assert changeset.changes.queue == "registry_sync"
        assert changeset.changes.worker == "Cache.Registry.ReleaseWorker"
        assert changeset.changes.args == %{scope: "apple", name: "swift-argument-parser"}
        {:ok, %Oban.Job{}}
      end)

      expect(LeaderElection, :release_lock, fn ->
        :ok
      end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
