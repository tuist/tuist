defmodule Tuist.Marketing.Workers.CacheGlobeRefreshWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.KeyValueStore
  alias Tuist.Marketing.CacheGlobe
  alias Tuist.Marketing.Workers.CacheGlobeRefreshWorker

  setup :verify_on_exit!

  describe "perform/1" do
    test "writes a CacheGlobe snapshot into the shared key-value store" do
      snapshot = %{CacheGlobe.empty() | downloads: 42, status: :available}

      expect(CacheGlobe, :snapshot, fn -> snapshot end)

      expect(KeyValueStore, :put, fn [:marketing, :cache_globe], ^snapshot, opts ->
        assert opts[:persist_across_deployments]
        assert opts[:ttl] >= 60_000
        {:ok, true}
      end)

      assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
