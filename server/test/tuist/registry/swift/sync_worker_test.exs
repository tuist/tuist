defmodule Tuist.Registry.Swift.SyncWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Tuist.Repo
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Registry
  alias Tuist.Registry.Swift.Lock
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.Purge
  alias Tuist.Registry.Swift.ReleaseWorker
  alias Tuist.Registry.Swift.SwiftPackageIndex
  alias Tuist.Registry.Swift.SyncCursor
  alias Tuist.Registry.Swift.SyncWorker

  setup :set_mimic_from_context

  setup do
    Sandbox.checkout(Tuist.Repo)

    stub(Registry, :swift_registry_github_token, fn -> "token" end)
    stub(Registry, :swift_registry_enabled?, fn -> true end)
    stub(Registry, :swift_registry_sync_enabled?, fn -> true end)
    stub(Registry, :swift_registry_sync_allowlist, fn -> nil end)
    stub(Registry, :swift_registry_sync_limit, fn -> 1_000 end)
    stub(Lock, :try_acquire, fn _, _ -> {:ok, :acquired} end)
    stub(Lock, :release, fn _ -> :ok end)
    stub(SwiftPackageIndex, :list_packages, fn _ -> {:ok, []} end)

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

  test "does not enqueue skipped versions" do
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
      {:ok, %{"releases" => %{}, "skipped_releases" => %{"7.0.0" => %{"reason" => "missing_manifests"}}}}
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

  test "discards the job on a transient transport error instead of failing" do
    reason = %Req.HTTPError{protocol: :http2, reason: :closed_for_writing}
    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:error, reason} end)

    assert {:discard, ^reason} = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "surfaces an HTTP status error as a hard failure" do
    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:error, {:http_error, 403}} end)

    assert {:error, {:http_error, 403}} = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "force resyncs only the requested package version without taking the catalog lock" do
    package = %{
      scope: "apple",
      name: "swift-argument-parser",
      repository_full_handle: "apple/swift-argument-parser"
    }

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)

    expect(Lock, :try_acquire, fn
      {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired}
    end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:ok, ["v1.2.3", "2.0.0"]}
    end)

    expect(Purge, :purge_version, fn "apple", "swift-argument-parser", "1.2.3" ->
      {:ok, %{artifacts_deleted: 1, metadata: %{removed_from: ["releases"]}}}
    end)

    assert :ok =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "version" => "1.2.3"
               }
             })

    assert_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "apple",
        "name" => "swift-argument-parser",
        "repository_full_handle" => "apple/swift-argument-parser",
        "tag" => "v1.2.3"
      }
    )

    refute_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "apple",
        "name" => "swift-argument-parser",
        "repository_full_handle" => "apple/swift-argument-parser",
        "tag" => "2.0.0"
      }
    )
  end

  test "does not purge a version when its tags cannot be fetched" do
    package = %{
      scope: "apple",
      name: "swift-argument-parser",
      repository_full_handle: "apple/swift-argument-parser"
    }

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)

    expect(Lock, :try_acquire, fn
      {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired}
    end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:error, :timeout}
    end)

    assert {:error, :timeout} =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "version" => "1.2.3"
               }
             })

    refute_enqueued(worker: ReleaseWorker)
  end

  test "discards force resync requests for versions outside the catalog" do
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

    assert {:discard, :package_not_found} =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "repository_full_handle" => "unknown/package",
                 "version" => "1.2.3"
               }
             })

    refute_enqueued(worker: ReleaseWorker)
  end

  test "discards force resync requests when the version is not a current source tag" do
    package = %{
      scope: "apple",
      name: "swift-argument-parser",
      repository_full_handle: "apple/swift-argument-parser"
    }

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)

    expect(Lock, :try_acquire, fn
      {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired}
    end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:ok, ["2.0.0"]}
    end)

    assert {:discard, :version_not_found} =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "version" => "1.2.3"
               }
             })

    refute_enqueued(worker: ReleaseWorker)
  end

  test "discards force resync requests with an invalid version" do
    assert {:discard, :invalid_version} =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "version" => "not-a-version"
               }
             })

    refute_enqueued(worker: ReleaseWorker)
  end

  test "snoozes a version resync while the package is locked" do
    package = %{
      scope: "apple",
      name: "swift-argument-parser",
      repository_full_handle: "apple/swift-argument-parser"
    }

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)

    expect(Lock, :try_acquire, fn
      {:package, "apple", "swift-argument-parser"}, _ -> {:error, :already_locked}
    end)

    assert {:snooze, 30} =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "version" => "1.2.3"
               }
             })
  end
end
