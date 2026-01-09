defmodule Cache.Registry.LeaderElectionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Registry.LeaderElection
  alias ExAws.Operation.S3

  @lock_key "registry/sync/leader.lock"

  setup :set_mimic_global

  describe "try_acquire_lock/0" do
    test "returns {:ok, :acquired} when no lock exists" do
      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, body, opts ->
        assert Keyword.get(opts, :content_type) == "application/json"
        assert Keyword.get(opts, :if_none_match) == "*"

        lock = Jason.decode!(body)
        assert Map.has_key?(lock, "node")
        assert Map.has_key?(lock, "acquired_at")
        assert Map.has_key?(lock, "expires_at")

        %S3{
          bucket: "test-bucket",
          path: @lock_key,
          body: body,
          headers: %{}
        }
      end)

      expect(ExAws, :request, fn operation ->
        assert operation.headers["x-tigris-consistent"] == "true"
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = LeaderElection.try_acquire_lock()
    end

    test "returns {:error, :already_locked} when valid lock exists" do
      node_name = "other-node.tuist.dev"
      now = DateTime.utc_now()
      expires_at = DateTime.add(now, 3600, :second)

      existing_lock =
        Jason.encode!(%{
          "node" => node_name,
          "acquired_at" => DateTime.to_iso8601(now),
          "expires_at" => DateTime.to_iso8601(expires_at)
        })

      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, _body, _opts ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:error, {:http_error, 412, "Precondition Failed"}}
      end)

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: existing_lock}}
      end)

      assert {:error, :already_locked} = LeaderElection.try_acquire_lock()
    end

    test "acquires lock when existing lock is expired" do
      node_name = "other-node.tuist.dev"
      past = DateTime.add(DateTime.utc_now(), -7200, :second)
      expired_at = DateTime.add(past, 3600, :second)

      expired_lock =
        Jason.encode!(%{
          "node" => node_name,
          "acquired_at" => DateTime.to_iso8601(past),
          "expires_at" => DateTime.to_iso8601(expired_at)
        })

      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, _body, _opts ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:error, {:http_error, 412, "Precondition Failed"}}
      end)

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: expired_lock}}
      end)

      expect(ExAws.S3, :delete_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{status_code: 204}}
      end)

      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, _body, _opts ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = LeaderElection.try_acquire_lock()
    end

    test "lock JSON contains required fields with correct TTL" do
      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, body, _opts ->
        lock = Jason.decode!(body)

        assert is_binary(lock["node"])
        assert is_binary(lock["acquired_at"])
        assert is_binary(lock["expires_at"])

        {:ok, acquired_at, _} = DateTime.from_iso8601(lock["acquired_at"])
        {:ok, expires_at, _} = DateTime.from_iso8601(lock["expires_at"])

        diff = DateTime.diff(expires_at, acquired_at, :second)
        assert diff == 4200

        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = LeaderElection.try_acquire_lock()
    end
  end

  describe "release_lock/0" do
    test "releases lock when we are the leader" do
      System.put_env("PHX_HOST", "my-node.tuist.dev")

      on_exit(fn ->
        System.delete_env("PHX_HOST")
      end)

      now = DateTime.utc_now()
      expires_at = DateTime.add(now, 3600, :second)

      our_lock =
        Jason.encode!(%{
          "node" => "my-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(now),
          "expires_at" => DateTime.to_iso8601(expires_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: our_lock}}
      end)

      expect(ExAws.S3, :delete_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{status_code: 204}}
      end)

      assert :ok = LeaderElection.release_lock()
    end

    test "returns {:error, :not_leader} when another node holds the lock" do
      System.put_env("PHX_HOST", "my-node.tuist.dev")

      on_exit(fn ->
        System.delete_env("PHX_HOST")
      end)

      now = DateTime.utc_now()
      expires_at = DateTime.add(now, 3600, :second)

      other_lock =
        Jason.encode!(%{
          "node" => "other-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(now),
          "expires_at" => DateTime.to_iso8601(expires_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: other_lock}}
      end)

      assert {:error, :not_leader} = LeaderElection.release_lock()
    end

    test "returns {:error, :not_leader} when no lock exists" do
      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:error, {:http_error, 404, "Not Found"}}
      end)

      assert {:error, :not_leader} = LeaderElection.release_lock()
    end
  end

  describe "is_leader?/0" do
    test "returns true when we hold a valid lock" do
      System.put_env("PHX_HOST", "my-node.tuist.dev")

      on_exit(fn ->
        System.delete_env("PHX_HOST")
      end)

      now = DateTime.utc_now()
      expires_at = DateTime.add(now, 3600, :second)

      our_lock =
        Jason.encode!(%{
          "node" => "my-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(now),
          "expires_at" => DateTime.to_iso8601(expires_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: our_lock}}
      end)

      assert LeaderElection.is_leader?() == true
    end

    test "returns false when another node holds the lock" do
      System.put_env("PHX_HOST", "my-node.tuist.dev")

      on_exit(fn ->
        System.delete_env("PHX_HOST")
      end)

      now = DateTime.utc_now()
      expires_at = DateTime.add(now, 3600, :second)

      other_lock =
        Jason.encode!(%{
          "node" => "other-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(now),
          "expires_at" => DateTime.to_iso8601(expires_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: other_lock}}
      end)

      assert LeaderElection.is_leader?() == false
    end

    test "returns false after TTL expires" do
      System.put_env("PHX_HOST", "my-node.tuist.dev")

      on_exit(fn ->
        System.delete_env("PHX_HOST")
      end)

      past = DateTime.add(DateTime.utc_now(), -7200, :second)
      expired_at = DateTime.add(past, 3600, :second)

      expired_lock =
        Jason.encode!(%{
          "node" => "my-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(past),
          "expires_at" => DateTime.to_iso8601(expired_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: expired_lock}}
      end)

      assert LeaderElection.is_leader?() == false
    end

    test "returns false when no lock exists" do
      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:error, {:http_error, 404, "Not Found"}}
      end)

      assert LeaderElection.is_leader?() == false
    end
  end

  describe "current_leader/0" do
    test "returns {:ok, node_name} when valid lock exists" do
      now = DateTime.utc_now()
      expires_at = DateTime.add(now, 3600, :second)

      lock =
        Jason.encode!(%{
          "node" => "leader-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(now),
          "expires_at" => DateTime.to_iso8601(expires_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: lock}}
      end)

      assert {:ok, "leader-node.tuist.dev"} = LeaderElection.current_leader()
    end

    test "returns {:error, :no_lock} when lock is expired" do
      past = DateTime.add(DateTime.utc_now(), -7200, :second)
      expired_at = DateTime.add(past, 3600, :second)

      expired_lock =
        Jason.encode!(%{
          "node" => "leader-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(past),
          "expires_at" => DateTime.to_iso8601(expired_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: expired_lock}}
      end)

      assert {:error, :no_lock} = LeaderElection.current_leader()
    end

    test "returns {:error, :no_lock} when no lock file exists" do
      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:error, {:http_error, 404, "Not Found"}}
      end)

      assert {:error, :no_lock} = LeaderElection.current_leader()
    end

    test "returns {:error, :no_lock} when lock JSON is malformed" do
      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: "not valid json"}}
      end)

      assert {:error, :no_lock} = LeaderElection.current_leader()
    end

    test "returns {:error, :no_lock} when lock JSON is missing required fields" do
      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{body: Jason.encode!(%{"node" => "test"})}}
      end)

      assert {:error, :no_lock} = LeaderElection.current_leader()
    end

    test "uses x-tigris-consistent header for all S3 operations" do
      now = DateTime.utc_now()
      expires_at = DateTime.add(now, 3600, :second)

      lock =
        Jason.encode!(%{
          "node" => "leader-node.tuist.dev",
          "acquired_at" => DateTime.to_iso8601(now),
          "expires_at" => DateTime.to_iso8601(expires_at)
        })

      expect(ExAws.S3, :get_object, fn "test-bucket", @lock_key ->
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn operation ->
        assert operation.headers["x-tigris-consistent"] == "true"
        {:ok, %{body: lock}}
      end)

      assert {:ok, _} = LeaderElection.current_leader()
    end
  end

  describe "node identification" do
    test "uses PHX_HOST when available" do
      System.put_env("PHX_HOST", "phx-host.tuist.dev")
      System.delete_env("HOSTNAME")

      on_exit(fn ->
        System.delete_env("PHX_HOST")
      end)

      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, body, _opts ->
        lock = Jason.decode!(body)
        assert lock["node"] == "phx-host.tuist.dev"
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = LeaderElection.try_acquire_lock()
    end

    test "falls back to HOSTNAME when PHX_HOST not set" do
      System.delete_env("PHX_HOST")
      System.put_env("HOSTNAME", "hostname-fallback.tuist.dev")

      on_exit(fn ->
        System.delete_env("HOSTNAME")
      end)

      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, body, _opts ->
        lock = Jason.decode!(body)
        assert lock["node"] == "hostname-fallback.tuist.dev"
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = LeaderElection.try_acquire_lock()
    end

    test "uses 'unknown' when no environment variables set" do
      System.delete_env("PHX_HOST")
      System.delete_env("HOSTNAME")

      expect(ExAws.S3, :put_object, fn "test-bucket", @lock_key, body, _opts ->
        lock = Jason.decode!(body)
        assert lock["node"] == "unknown"
        %S3{bucket: "test-bucket", path: @lock_key, headers: %{}}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = LeaderElection.try_acquire_lock()
    end
  end
end
