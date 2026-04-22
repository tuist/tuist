defmodule Tuist.CacheTest do
  use TuistTestSupport.Cases.DataCase, clickhouse: true
  use Mimic

  alias Tuist.Cache

  describe "last_24h_artifacts_count/0" do
    test "returns the count from the daily stats view" do
      # Given
      stub(Tuist.IngestRepo, :query, fn _query, _params ->
        {:ok, %{rows: [[42]]}}
      end)

      # When
      count = Cache.last_24h_artifacts_count()

      # Then
      assert count == 42
    end

    test "returns 0 when the query returns nil" do
      # Given
      stub(Tuist.IngestRepo, :query, fn _query, _params ->
        {:ok, %{rows: [[nil]]}}
      end)

      # When
      count = Cache.last_24h_artifacts_count()

      # Then
      assert count == 0
    end

    test "returns 0 when the query fails" do
      # Given
      stub(Tuist.IngestRepo, :query, fn _query, _params ->
        {:error, :timeout}
      end)

      # When
      count = Cache.last_24h_artifacts_count()

      # Then
      assert count == 0
    end
  end
end
