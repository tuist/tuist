defmodule Cache.Registry.LockTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Registry.Lock

  setup :set_mimic_from_context

  setup do
    stub(Cache.Config, :registry_bucket, fn -> "test-bucket" end)
    :ok
  end

  describe "try_acquire/2" do
    test "acquires lock when no lock exists" do
      expect(ExAws, :request, fn %{http_method: :put, path: "registry/locks/sync.json"} = op ->
        assert op.headers["X-Tigris-Consistent"] == "true"
        assert op.headers["if-none-match"] == "*"
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = Lock.try_acquire(:sync, 60)
    end

    test "acquires expired lock via etag replacement" do
      expired_at = System.system_time(:second) - 100
      lock_body = Jason.encode!(%{acquired_at: expired_at - 60, expires_at: expired_at, node: "other@node"})

      # First put attempt: 412 Precondition Failed (lock exists)
      expect(ExAws, :request, fn %{http_method: :put} -> {:error, {:http_error, 412, ""}} end)

      # Read existing lock to check expiry
      expect(ExAws, :request, fn %{http_method: :get, path: "registry/locks/sync.json"} = op ->
        assert op.headers["X-Tigris-Consistent"] == "true"
        {:ok, %{body: lock_body, headers: %{"etag" => "\"abc123\""}}}
      end)

      # Replace with etag match
      expect(ExAws, :request, fn %{http_method: :put, path: "registry/locks/sync.json"} = op ->
        assert op.headers["X-Tigris-Consistent"] == "true"
        assert op.headers["if-match"] == "\"abc123\""
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = Lock.try_acquire(:sync, 60)
    end

    test "returns already_locked when lock is held and not expired" do
      future = System.system_time(:second) + 600
      lock_body = Jason.encode!(%{acquired_at: System.system_time(:second), expires_at: future, node: "other@node"})

      # First put: 412 (lock exists)
      expect(ExAws, :request, fn %{http_method: :put} -> {:error, {:http_error, 412, ""}} end)

      # Read lock — not expired
      expect(ExAws, :request, fn %{http_method: :get} ->
        {:ok, %{body: lock_body, headers: %{"etag" => "\"abc123\""}}}
      end)

      assert {:error, :already_locked} = Lock.try_acquire(:sync, 60)
    end

    test "retries creation when lock disappears between 412 and read" do
      # First put: 412
      expect(ExAws, :request, fn %{http_method: :put} -> {:error, {:http_error, 412, ""}} end)

      # Read: 404 (lock was deleted between precondition check and read)
      expect(ExAws, :request, fn %{http_method: :get} -> {:error, {:http_error, 404, ""}} end)

      # Retry creation
      expect(ExAws, :request, fn %{http_method: :put} = op ->
        assert op.headers["if-none-match"] == "*"
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, :acquired} = Lock.try_acquire(:sync, 60)
    end

    test "returns already_locked when expired lock replacement fails (race)" do
      expired_at = System.system_time(:second) - 100
      lock_body = Jason.encode!(%{acquired_at: expired_at - 60, expires_at: expired_at, node: "other@node"})

      # First put: 412
      expect(ExAws, :request, fn %{http_method: :put} -> {:error, {:http_error, 412, ""}} end)

      # Read expired lock
      expect(ExAws, :request, fn %{http_method: :get} ->
        {:ok, %{body: lock_body, headers: %{"etag" => "\"abc123\""}}}
      end)

      # Replace attempt fails — another node beat us
      expect(ExAws, :request, fn %{http_method: :put} ->
        {:error, {:http_error, 412, ""}}
      end)

      assert {:error, :already_locked} = Lock.try_acquire(:sync, 60)
    end
  end

  describe "release/1" do
    test "deletes the lock object from S3" do
      expect(ExAws, :request, fn %{http_method: :delete, path: "registry/locks/sync.json"} ->
        {:ok, %{status_code: 204}}
      end)

      assert :ok = Lock.release(:sync)
    end

    test "returns ok even if delete fails" do
      expect(ExAws, :request, fn %{http_method: :delete} ->
        {:error, {:http_error, 500, ""}}
      end)

      assert :ok = Lock.release(:sync)
    end
  end

  describe "lock key generation" do
    test "generates correct key for sync lock" do
      expect(ExAws, :request, fn %{path: "registry/locks/sync.json"} ->
        {:ok, %{status_code: 200}}
      end)

      Lock.try_acquire(:sync, 60)
    end

    test "generates correct key for package lock" do
      expect(ExAws, :request, fn %{path: "registry/locks/packages/apple/swift-argument-parser.json"} ->
        {:ok, %{status_code: 200}}
      end)

      Lock.try_acquire({:package, "apple", "swift-argument-parser"}, 60)
    end

    test "generates correct key for release lock" do
      expect(ExAws, :request, fn %{path: "registry/locks/releases/apple/swift-argument-parser/1.0.0.json"} ->
        {:ok, %{status_code: 200}}
      end)

      Lock.try_acquire({:release, "apple", "swift-argument-parser", "1.0.0"}, 60)
    end

    test "normalizes scope and name in lock key" do
      expect(ExAws, :request, fn %{path: "registry/locks/packages/apple/swift_nio.json"} ->
        {:ok, %{status_code: 200}}
      end)

      Lock.try_acquire({:package, "Apple", "swift.nio"}, 60)
    end

    test "scope normalization only downcases without replacing dots" do
      expect(ExAws, :request, fn %{path: "registry/locks/packages/org.example/my_pkg.json"} ->
        {:ok, %{status_code: 200}}
      end)

      Lock.try_acquire({:package, "Org.Example", "my.pkg"}, 60)
    end
  end

  describe "X-Tigris-Consistent header" do
    test "is set on put operations" do
      expect(ExAws, :request, fn %{http_method: :put, headers: headers} ->
        assert headers["X-Tigris-Consistent"] == "true"
        {:ok, %{status_code: 200}}
      end)

      Lock.try_acquire(:sync, 60)
    end

    test "is set on get operations during expired lock check" do
      # 412 to trigger read
      expect(ExAws, :request, fn %{http_method: :put} -> {:error, {:http_error, 412, ""}} end)

      expect(ExAws, :request, fn %{http_method: :get, headers: headers} ->
        assert headers["X-Tigris-Consistent"] == "true"
        {:error, {:http_error, 404, ""}}
      end)

      # Retry after not_found
      expect(ExAws, :request, fn %{http_method: :put} -> {:ok, %{status_code: 200}} end)

      Lock.try_acquire(:sync, 60)
    end
  end
end
