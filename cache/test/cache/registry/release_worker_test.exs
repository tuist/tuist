defmodule Cache.Registry.ReleaseWorkerTest do
  use CacheWeb.ConnCase, async: false
  use Mimic

  alias Cache.Registry.GitHub
  alias Cache.Registry.Lock
  alias Cache.Registry.Metadata
  alias Cache.Registry.ReleaseWorker

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :registry_github_token, "token")
    on_exit(fn -> Application.delete_env(:cache, :registry_github_token) end)
    stub(Lock, :release, fn _ -> :ok end)
    :ok
  end

  test "skips when release already exists" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ -> {:ok, :acquired} end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
      {:ok, %{"releases" => %{"1.0.0" => %{"checksum" => "abc", "manifests" => []}}}}
    end)

    stub(GitHub, :download_zipball, fn _, _, _, _ -> flunk("unexpected zipball download") end)
    stub(GitHub, :list_repository_contents, fn _, _, _ -> flunk("unexpected contents request") end)
    stub(GitHub, :get_file_content, fn _, _, _, _ -> flunk("unexpected file request") end)

    assert :ok =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end
end
