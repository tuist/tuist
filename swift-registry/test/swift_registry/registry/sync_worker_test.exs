defmodule SwiftRegistry.Registry.SyncWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: SwiftRegistry.Repo
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias SwiftRegistry.Config
  alias SwiftRegistry.Registry.Lock
  alias SwiftRegistry.Registry.Metadata
  alias SwiftRegistry.Registry.ReleaseWorker
  alias SwiftRegistry.Registry.SwiftPackageIndex
  alias SwiftRegistry.Registry.SyncCursor
  alias SwiftRegistry.Registry.SyncWorker

  setup :set_mimic_from_context

  setup do
    Sandbox.checkout(SwiftRegistry.Repo)
    :ok
  end

  setup do
    stub(Config, :registry_github_token, fn -> "token" end)

    stub(Config, :registry_bucket, fn -> "test-bucket" end)
    stub(Config, :registry_enabled?, fn -> true end)
    stub(Config, :registry_sync_enabled?, fn -> true end)
    stub(Lock, :try_acquire, fn _, _ -> {:ok, :acquired} end)
    stub(SwiftPackageIndex, :list_packages, fn _ -> {:ok, []} end)
    stub(Lock, :release, fn _ -> :ok end)
    :ok
  end

  test "enqueues release workers for missing versions" do
    expect(Lock, :try_acquire, 2, fn
      :sync, _ -> {:ok, :acquired}
      {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired}
    end)

    expect(SwiftPackageIndex, :list_packages, fn "token" ->
      {:ok,
       [
         %{
           scope: "apple",
           name: "swift-argument-parser",
           repository_full_handle: "apple/swift-argument-parser"
         }
       ]}
    end)

    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser" -> {:error, :not_found} end)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", _metadata -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:ok, ["v1.2.3"]}
    end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "apple",
        "name" => "swift-argument-parser",
        "repository_full_handle" => "apple/swift-argument-parser",
        "tag" => "v1.2.3"
      }
    )
  end

  test "enqueues release workers for multi-segment prereleases" do
    expect(Lock, :try_acquire, 2, fn
      :sync, _ -> {:ok, :acquired}
      {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired}
    end)

    expect(SwiftPackageIndex, :list_packages, fn "token" ->
      {:ok,
       [
         %{
           scope: "apple",
           name: "swift-argument-parser",
           repository_full_handle: "apple/swift-argument-parser"
         }
       ]}
    end)

    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser" -> {:error, :not_found} end)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", _metadata -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:ok, ["1.2.3-alpha.1.2"]}
    end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "apple",
        "name" => "swift-argument-parser",
        "repository_full_handle" => "apple/swift-argument-parser",
        "tag" => "1.2.3-alpha.1.2"
      }
    )
  end

  test "does not enqueue release workers for skipped versions" do
    expect(Lock, :try_acquire, 2, fn
      :sync, _ -> {:ok, :acquired}
      {:package, "newrelic", "newrelic-ios-agent-spm"}, _ -> {:ok, :acquired}
    end)

    expect(SwiftPackageIndex, :list_packages, fn "token" ->
      {:ok,
       [
         %{
           scope: "newrelic",
           name: "newrelic-ios-agent-spm",
           repository_full_handle: "newrelic/newrelic-ios-agent-spm"
         }
       ]}
    end)

    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(Metadata, :get_package, fn "newrelic", "newrelic-ios-agent-spm" ->
      {:ok,
       %{
         "releases" => %{},
         "skipped_releases" => %{"7.0.0" => %{"reason" => "missing_manifests"}}
       }}
    end)

    expect(Metadata, :put_package, fn "newrelic", "newrelic-ios-agent-spm", metadata ->
      assert metadata["skipped_releases"] == %{"7.0.0" => %{"reason" => "missing_manifests"}}
      :ok
    end)

    expect(TuistCommon.GitHub, :list_tags, fn "newrelic/newrelic-ios-agent-spm", "token", _ ->
      {:ok, ["7.0.0"]}
    end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    refute_enqueued(worker: ReleaseWorker)
  end

  test "ignores tags that do not match the accepted source format" do
    expect(Lock, :try_acquire, 2, fn
      :sync, _ -> {:ok, :acquired}
      {:package, "realm", "realm-swift"}, _ -> {:ok, :acquired}
    end)

    expect(SwiftPackageIndex, :list_packages, fn "token" ->
      {:ok,
       [
         %{
           scope: "realm",
           name: "realm-swift",
           repository_full_handle: "realm/realm-swift"
         }
       ]}
    end)

    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(Metadata, :get_package, fn "realm", "realm-swift" -> {:error, :not_found} end)

    expect(Metadata, :put_package, fn "realm", "realm-swift", _metadata -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "realm/realm-swift", "token", _ ->
      {:ok, ["10.28.1", "0.0.24b"]}
    end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "realm",
        "name" => "realm-swift",
        "repository_full_handle" => "realm/realm-swift",
        "tag" => "10.28.1"
      }
    )

    refute_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "realm",
        "name" => "realm-swift",
        "repository_full_handle" => "realm/realm-swift",
        "tag" => "0.0.24b"
      }
    )
  end

  @tag capture_log: true
  test "skips sync when registry sync is disabled" do
    stub(Config, :registry_sync_enabled?, fn -> false end)
    reject(Lock, :try_acquire, 2)
    reject(SwiftPackageIndex, :list_packages, 1)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    refute_enqueued(worker: ReleaseWorker)
  end

  @tag capture_log: true
  test "skips sync when token is missing" do
    stub(Config, :registry_github_token, fn -> nil end)
    stub(Config, :registry_enabled?, fn -> false end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    refute_enqueued(worker: ReleaseWorker)
  end
end
