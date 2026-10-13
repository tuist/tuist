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

    # A catalog pass enqueues only versions the catalog is missing, so it never
    # asks the release worker to rebuild one that is already published.
    refute_enqueued(worker: ReleaseWorker, args: %{"force" => true})
  end

  test "does not enqueue versions with a verified skip classification" do
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
         "skipped_releases" => %{
           "7.0.0" => %{"classification_version" => 2, "reason" => "missing_manifests"}
         }
       }}
    end)

    expect(Metadata, :put_package, fn "newrelic", "newrelic-ios-agent-spm", metadata ->
      assert metadata["skipped_releases"] == %{
               "7.0.0" => %{"classification_version" => 2, "reason" => "missing_manifests"}
             }

      :ok
    end)

    expect(TuistCommon.GitHub, :list_tags, fn "newrelic/newrelic-ios-agent-spm", "token", _ ->
      {:ok, ["7.0.0"]}
    end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    refute_enqueued(worker: ReleaseWorker)
  end

  test "rechecks versions skipped before skip classifications were versioned" do
    expect(Lock, :try_acquire, 2, fn
      :sync, _ -> {:ok, :acquired}
      {:package, "adjust", "ios_sdk"}, _ -> {:ok, :acquired}
    end)

    expect(SwiftPackageIndex, :list_packages, fn "token" ->
      {:ok,
       [
         %{
           scope: "adjust",
           name: "ios_sdk",
           repository_full_handle: "adjust/ios_sdk"
         }
       ]}
    end)

    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(Metadata, :get_package, fn "adjust", "ios_sdk" ->
      {:ok,
       %{
         "releases" => %{},
         "skipped_releases" => %{"5.6.2" => %{"reason" => "missing_manifests"}}
       }}
    end)

    expect(Metadata, :put_package, fn "adjust", "ios_sdk", _metadata -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "adjust/ios_sdk", "token", _ ->
      {:ok, ["v5.6.2"]}
    end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "adjust",
        "name" => "ios_sdk",
        "repository_full_handle" => "adjust/ios_sdk",
        "tag" => "v5.6.2"
      }
    )
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

  test "defers the job to the reported quota reset when GitHub rate limits the catalog request" do
    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:error, {:rate_limited, 403, 900}} end)

    assert {:snooze, 900} = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "falls back to a default deferral when GitHub reports no reset" do
    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:error, {:rate_limited, 403, nil}} end)

    assert {:snooze, 600} = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "clamps a reported reset that is longer than GitHub's quota window" do
    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:error, {:rate_limited, 429, 100_000}} end)

    assert {:snooze, 3_600} = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "clamps a reset that has already elapsed so the pass does not immediately replay" do
    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:error, {:rate_limited, 429, 0}} end)

    assert {:snooze, 60} = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "stops the pass at the throttled package and advances the cursor only over the ones it visited" do
    packages =
      Enum.map(1..3, fn index ->
        %{scope: "acme", name: "package-#{index}", repository_full_handle: "acme/package-#{index}"}
      end)

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, packages} end)
    expect(SyncCursor, :get, fn -> 0 end)

    expect(Metadata, :get_package, 2, fn _scope, _name -> {:error, :not_found} end)
    expect(Metadata, :put_package, fn "acme", "package-1", _metadata -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-1", "token", _ -> {:ok, []} end)
    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-2", "token", _ -> {:error, {:rate_limited, 403, 300}} end)

    # Only the one package that was actually read. The cursor must not skip
    # package-2 and package-3, which the pass never looked at.
    expect(SyncCursor, :put, fn 1 -> :ok end)

    assert {:snooze, 300} = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "reports the coverage a throttled pass gave up on" do
    packages =
      Enum.map(1..2, fn index ->
        %{scope: "acme", name: "package-#{index}", repository_full_handle: "acme/package-#{index}"}
      end)

    :telemetry.attach(
      "sync-coverage-deferred-test",
      SyncWorker.coverage_deferred_event_name(),
      fn _event, measurements, metadata, pid -> send(pid, {:coverage_deferred, measurements, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach("sync-coverage-deferred-test") end)

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, packages} end)
    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-1", "token", _ -> {:error, {:rate_limited, 403, 300}} end)

    expect(Metadata, :get_package, fn "acme", "package-1" -> {:error, :not_found} end)

    assert {:snooze, 300} = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_receive {:coverage_deferred, %{packages: 2}, %{reason: :rate_limited}}
  end

  # A release worker holds this same lock while writing a package's catalog
  # entry, so contention is ordinary. The pass moves on rather than stalling the
  # rotation, but the miss has to be counted rather than silent.
  test "counts a package it could not lock as skipped coverage" do
    package = %{scope: "acme", name: "package-1", repository_full_handle: "acme/package-1"}

    :telemetry.attach(
      "sync-package-locked-test",
      SyncWorker.package_skipped_event_name(),
      fn _event, measurements, metadata, pid -> send(pid, {:package_skipped, measurements, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach("sync-package-locked-test") end)

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)
    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(Lock, :try_acquire, 2, fn
      :sync, _ -> {:ok, :acquired}
      {:package, "acme", "package-1"}, _ -> {:error, :already_locked}
    end)

    reject(&TuistCommon.GitHub.list_tags/3)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_receive {:package_skipped, %{packages: 1}, %{reason: :package_locked}}
  end

  # A 401 is the credential, not the repository, so every remaining package
  # would fail the same way. Skipping them one by one would advance the cursor
  # over the whole batch and report a clean pass.
  test "stops the pass when GitHub rejects the credential rather than skipping every package" do
    packages =
      Enum.map(1..3, fn index ->
        %{scope: "acme", name: "package-#{index}", repository_full_handle: "acme/package-#{index}"}
      end)

    :telemetry.attach(
      "sync-unauthorized-test",
      SyncWorker.coverage_deferred_event_name(),
      fn _event, measurements, metadata, pid -> send(pid, {:coverage_deferred, measurements, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach("sync-unauthorized-test") end)

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, packages} end)
    expect(SyncCursor, :get, fn -> 0 end)
    expect(Metadata, :get_package, fn "acme", "package-1" -> {:error, :not_found} end)

    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-1", "token", _ -> {:error, {:http_error, 401}} end)

    expect(SyncCursor, :put, fn 0 -> :ok end)

    assert {:snooze, 600} = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_receive {:coverage_deferred, %{packages: 3}, %{reason: :unauthorized}}
  end

  test "reports a package the pass passed over without reading its tags" do
    packages =
      Enum.map(1..2, fn index ->
        %{scope: "acme", name: "package-#{index}", repository_full_handle: "acme/package-#{index}"}
      end)

    :telemetry.attach(
      "sync-package-skipped-test",
      SyncWorker.package_skipped_event_name(),
      fn _event, measurements, metadata, pid -> send(pid, {:package_skipped, measurements, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach("sync-package-skipped-test") end)

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, packages} end)
    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)
    expect(Metadata, :get_package, 2, fn _scope, _name -> {:error, :not_found} end)
    expect(Metadata, :put_package, fn "acme", "package-2", _metadata -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-1", "token", _ -> {:error, {:http_error, 500}} end)
    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-2", "token", _ -> {:ok, []} end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_receive {:package_skipped, %{packages: 1}, %{reason: :tag_fetch_failed}}
  end

  # GitHub answers a repository a credential cannot see with 404, not 401, so a
  # credential that stops working looks like several hundred unrelated
  # repositories failing at once rather than like an authentication error. Per
  # package that is survivable; all of them at once is the mirror being broken,
  # and it must not read as a clean pass.
  test "treats a pass in which every package failed as lost coverage and holds the cursor" do
    packages =
      Enum.map(1..3, fn index ->
        %{scope: "acme", name: "package-#{index}", repository_full_handle: "acme/package-#{index}"}
      end)

    :telemetry.attach(
      "sync-all-failed-test",
      SyncWorker.coverage_deferred_event_name(),
      fn _event, measurements, metadata, pid -> send(pid, {:coverage_deferred, measurements, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach("sync-all-failed-test") end)

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, packages} end)
    expect(SyncCursor, :get, fn -> 2 end)
    expect(Metadata, :get_package, 3, fn _scope, _name -> {:error, :not_found} end)
    stub(TuistCommon.GitHub, :list_tags, fn _handle, "token", _ -> {:error, {:http_error, 404}} end)

    # Held where it was: nothing was mirrored, so there is no progress to record,
    # and rotating on would spend the next pass failing the same way elsewhere.
    expect(SyncCursor, :put, fn 2 -> :ok end)

    assert {:snooze, 600} = SyncWorker.perform(%Oban.Job{args: %{}})

    assert_receive {:coverage_deferred, %{packages: 3}, %{reason: :all_packages_failed}}
  end

  test "does not read a partly failed pass as systemic" do
    packages =
      Enum.map(1..2, fn index ->
        %{scope: "acme", name: "package-#{index}", repository_full_handle: "acme/package-#{index}"}
      end)

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, packages} end)
    expect(SyncCursor, :get, fn -> 0 end)
    expect(Metadata, :get_package, 2, fn _scope, _name -> {:error, :not_found} end)
    expect(Metadata, :put_package, fn "acme", "package-1", _metadata -> :ok end)

    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-1", "token", _ -> {:ok, []} end)
    expect(TuistCommon.GitHub, :list_tags, fn "acme/package-2", "token", _ -> {:error, {:http_error, 404}} end)

    expect(SyncCursor, :put, fn 0 -> :ok end)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
  end

  test "force resyncs the requested version in place, without purging it first" do
    package = %{
      scope: "apple",
      name: "swift-argument-parser",
      repository_full_handle: "apple/swift-argument-parser"
    }

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:ok, ["v1.2.3", "2.0.0"]}
    end)

    # The rebuild replaces the archive and rewrites the catalog entry in place,
    # so the version keeps resolving for the whole repair instead of going
    # missing between the purge and a rebuild that may never land.
    reject(Purge, :purge_version, 3)
    reject(Lock, :try_acquire, 2)

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
        "tag" => "v1.2.3",
        "force" => true
      }
    )

    refute_enqueued(worker: ReleaseWorker, args: %{"allow_checksum_change" => true})

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

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:error, :timeout}
    end)

    reject(Lock, :try_acquire, 2)

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

    # Never mirrored, so there is no catalog document to fall back to.
    expect(Metadata, :get_package, fn "unknown", "package" -> {:error, :not_found} end)

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

  test "force resyncs a package the index no longer lists, keeping the mirrored identity" do
    # Upstream renamed the repository, so the Swift Package Index lists it under
    # the new handle and the old one -- the identity clients resolve -- is absent.
    # Without a fallback these versions are permanently unrepairable.
    expect(SwiftPackageIndex, :list_packages, fn "token" ->
      {:ok,
       [
         %{
           scope: "swiftlang",
           name: "swift-tools-support-core",
           repository_full_handle: "swiftlang/swift-tools-support-core"
         }
       ]}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-tools-support-core" ->
      {:ok, %{"repository_full_handle" => "apple/swift-tools-support-core"}}
    end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-tools-support-core", "token", _ ->
      {:ok, ["0.1.8"]}
    end)

    assert :ok =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "allow_checksum_change" => true,
                 "repository_full_handle" => "apple/swift-tools-support-core",
                 "version" => "0.1.8"
               }
             })

    # The pre-rename scope and name are preserved: publishing under the new
    # upstream name would create an identity no client pins, leaving the broken
    # one untouched.
    assert_enqueued(
      worker: ReleaseWorker,
      args: %{
        "scope" => "apple",
        "name" => "swift-tools-support-core",
        "repository_full_handle" => "apple/swift-tools-support-core",
        "tag" => "0.1.8"
      }
    )
  end

  test "discards force resync requests when the version is not a current source tag" do
    package = %{
      scope: "apple",
      name: "swift-argument-parser",
      repository_full_handle: "apple/swift-argument-parser"
    }

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:ok, ["2.0.0"]}
    end)

    reject(Lock, :try_acquire, 2)

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

  test "carries an explicit checksum-change override through to the release worker" do
    package = %{
      scope: "apple",
      name: "swift-argument-parser",
      repository_full_handle: "apple/swift-argument-parser"
    }

    expect(SwiftPackageIndex, :list_packages, fn "token" -> {:ok, [package]} end)

    expect(TuistCommon.GitHub, :list_tags, fn "apple/swift-argument-parser", "token", _ ->
      {:ok, ["1.2.3"]}
    end)

    reject(Purge, :purge_version, 3)

    assert :ok =
             SyncWorker.perform(%Oban.Job{
               args: %{
                 "force" => true,
                 "allow_checksum_change" => true,
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "version" => "1.2.3"
               }
             })

    assert_enqueued(
      worker: ReleaseWorker,
      args: %{"tag" => "1.2.3", "force" => true, "allow_checksum_change" => true}
    )
  end
end
