defmodule Cache.Registry.SyncWorkerTest do
  use CacheWeb.ConnCase, async: false
  use Mimic

  alias Cache.Registry.GitHub
  alias Cache.Registry.Lock
  alias Cache.Registry.Metadata
  alias Cache.Registry.ReleaseWorker
  alias Cache.Registry.SyncCursor
  alias Cache.Registry.SyncWorker
  alias Cache.Registry.SwiftPackageIndex

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :registry_github_token, "token")
    on_exit(fn -> Application.delete_env(:cache, :registry_github_token) end)
    stub(Lock, :release, fn _ -> :ok end)
    :ok
  end

  test "enqueues release workers for missing versions" do
    expect(Lock, :try_acquire, 2, fn
      :sync, _ -> {:ok, :acquired}
      {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired}
    end)

    expect(SwiftPackageIndex, :list_packages, fn "token" ->
      {:ok, [%{scope: "apple", name: "swift-argument-parser", repository_full_handle: "apple/swift-argument-parser"}]}
    end)

    expect(SyncCursor, :get, fn -> 0 end)
    expect(SyncCursor, :put, fn 0 -> :ok end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser" -> {:error, :not_found} end)
    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", _metadata -> :ok end)
    expect(GitHub, :list_tags, fn "apple/swift-argument-parser", "token" -> {:ok, ["v1.2.3"]} end)

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

  test "skips sync when token is missing" do
    Application.put_env(:cache, :registry_github_token, nil)

    assert :ok = SyncWorker.perform(%Oban.Job{args: %{}})
    refute_enqueued(worker: ReleaseWorker)
  end
end
