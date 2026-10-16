defmodule Tuist.Cargo.CacheDetailsTest do
  use ExUnit.Case, async: true

  alias Tuist.Cargo.CacheDetails
  alias Tuist.Cargo.CacheMetrics

  defp key(algorithm), do: "#{algorithm}:#{String.duplicate("a", 64)}:123"

  defp task,
    do: %{
      key: key("blake3"),
      name: "widgets",
      kind: "rust",
      status: "hit",
      cas_keys: [key("sha256")],
      read_duration_ns: 0
    }

  defp object, do: %{key: key("sha256"), operation: "download", status: "downloaded", size_bytes: 123, duration_ns: 1000}
  defp details, do: %{version: 1, tasks: [task()], cas_outputs: [object()], truncated: false}

  test "round-trips allowlisted details and recorded zero durations in the existing parent JSON" do
    assert {:ok, json} = CacheMetrics.encode(%{version: 1, hits: 1, details: details()})

    assert %{details: %{tasks: [%{read_duration_ns: 0}], cas_outputs: [%{key: key}]}} =
             CacheMetrics.read(%{cache_metrics: json})

    assert String.starts_with?(key, "sha256:")
    assert {:ok, normalized} = CacheDetails.normalize(JSON.decode!(JSON.encode!(details())))
    assert normalized == details()
  end

  test "rejects private fields, unsupported versions, mismatched statuses and fabricated SHA identities" do
    for invalid <- [
          Map.put(details(), :private_events, []),
          %{details() | version: 2},
          %{details() | truncated: 1},
          %{details() | tasks: [Map.put(task(), :compiler_arguments, ["secret"])]},
          %{details() | tasks: [%{task() | cas_keys: false}]},
          %{details() | tasks: [Map.put(task(), :write_duration_ns, -1)]},
          %{details() | cas_outputs: [%{object() | key: key("blake3")}]},
          %{details() | cas_outputs: [%{object() | status: "uploaded"}]},
          %{details() | cas_outputs: [%{object() | duration_ns: 9_000_000_000_000_001}]}
        ] do
      assert {:error, :invalid_cache_details} = CacheDetails.normalize(invalid)
    end
  end

  test "bounds records, names, references and total payload" do
    assert {:error, :invalid_cache_details} = CacheDetails.normalize(%{details() | tasks: List.duplicate(task(), 2001)})

    assert {:error, :invalid_cache_details} =
             CacheDetails.normalize(%{details() | cas_outputs: List.duplicate(object(), 5001)})

    assert {:error, :invalid_cache_details} =
             CacheDetails.normalize(%{details() | tasks: [%{task() | name: String.duplicate("x", 1025)}]})

    assert {:error, :invalid_cache_details} =
             CacheDetails.normalize(%{details() | tasks: [%{task() | cas_keys: List.duplicate(key("sha256"), 129)}]})

    large = %{task() | name: String.duplicate("x", 1024), cas_keys: List.duplicate(key("sha256"), 128)}
    assert {:error, :invalid_cache_details} = CacheDetails.normalize(%{details() | tasks: List.duplicate(large, 2000)})
  end

  test "corrupt or absent legacy details retain valid aggregate measurements without inventing rows" do
    metrics = CacheMetrics.read(%{cache_metrics: JSON.encode!(%{version: 1, hits: 7, details: %{version: 99}})})
    assert metrics.hits == 7
    refute Map.has_key?(metrics, :details)
    assert {:ok, nil} = CacheDetails.normalize(nil)
  end
end
