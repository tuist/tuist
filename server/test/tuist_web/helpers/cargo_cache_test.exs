defmodule TuistWeb.Helpers.CargoCacheTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.CargoCache

  test "task statuses show reuse outcomes while preserving compilation reasons in tooltips" do
    assert CargoCache.status_label("hit") == "Hit"
    assert CargoCache.statuses("cacheable-tasks") == ~w(hit miss)

    for status <- ~w(miss unconsulted verification) do
      assert CargoCache.status_label(status) == "Missed"
      assert CargoCache.color(status) == "warning"
      assert CargoCache.result(status) == "miss"
    end

    assert CargoCache.status_description("unconsulted") =~ "learn the task inputs"
    assert CargoCache.status_description("verification") =~ "verify cache correctness"
  end

  test "task breakdown uses the shared hit and miss colors without inventing cache results" do
    tasks = for status <- ~w(hit miss unconsulted verification unconsulted), do: %{status: status}
    metrics = %{hits: 1, misses: 1, unconsulted: 2, verifications: 1, details: %{tasks: tasks}}

    expected = [
      %{name: "Hit", count: 1, color: "var:hits-chart-legend-remote"},
      %{name: "Missed", count: 4, color: "var:hits-chart-legend-missed"}
    ]

    assert CargoCache.segments(metrics, "cacheable-tasks") == expected
    assert CargoCache.segments(Map.delete(metrics, :details), "cacheable-tasks") == expected

    partial = put_in(metrics, [:details, :tasks], Enum.take(tasks, 2))
    assert Enum.map(CargoCache.segments(partial, "cacheable-tasks"), & &1.count) == [1, 1]
  end

  test "miss filtering includes cold compilations and verification rebuilds without mutating records" do
    rows =
      for {status, index} <- Enum.with_index(~w(hit miss unconsulted verification)) do
        %{id: to_string(index), key: to_string(index), name: status, status: status}
      end

    assert %{rows: misses} = CargoCache.page(rows, "", "key", "miss", 1)
    assert Enum.map(misses, & &1.status) == ~w(miss unconsulted verification)
    assert %{rows: [hit]} = CargoCache.page(rows, "", "key", "hit", 1)
    assert hit.status == "hit"
  end

  test "latencies use recorded per-key samples, not aggregate cumulative phases" do
    samples = [%{read_duration_ns: 1_000_000}, %{read_duration_ns: 3_000_000}, %{}]
    assert %{value: "2ms", empty: false} = CargoCache.latency(samples, "read", "avg")
    assert %{value: "3ms", empty: false} = CargoCache.latency(samples, "read", "p99")
    assert %{value: "0ms", empty: false} = CargoCache.latency([%{write_duration_ns: 0}], "write", "avg")
    assert %{empty: true} = CargoCache.latency(samples, "write", "avg")
  end

  test "CAS breakdown counts only completed transfers using the shared download and upload colors" do
    samples = [
      %{key: "blob", status: "downloaded", operation: "download"},
      %{key: "blob", status: "downloaded", operation: "download"},
      %{key: "blob", status: "uploaded", operation: "upload"},
      %{key: "blob", status: "present", operation: "upload"},
      %{key: "blob", status: "failed", operation: "download"},
      %{key: "blob", status: "failed", operation: "upload"}
    ]

    metrics = %{details: %{cas_outputs: samples}}

    assert CargoCache.segments(metrics, "cas-outputs") == [
             %{name: "Download", count: 2, color: "var:hits-chart-legend-remote"},
             %{name: "Upload", count: 1, color: "var:hits-chart-legend-local"}
           ]

    rows = CargoCache.rows(metrics, "cas-outputs")
    assert length(rows) == 6
    assert %{rows: [%{status: "present"}]} = CargoCache.page(rows, "", "key", "present", 1)
    assert %{rows: failures} = CargoCache.page(rows, "", "key", "failed", 1)
    assert length(failures) == 2
  end

  test "presence-only and failed attempts do not fabricate completed transfers" do
    metrics = %{details: %{cas_outputs: [%{status: "present"}, %{status: "failed"}]}}
    assert Enum.map(CargoCache.segments(metrics, "cas-outputs"), & &1.count) == [0, 0]
    assert Enum.map(CargoCache.segments(%{}, "cas-outputs"), & &1.count) == [0, 0]
  end

  test "throughput excludes failed and presence-only operations" do
    samples = [
      %{status: "downloaded", operation: "download", size_bytes: 125_000, duration_ns: 1_000_000_000},
      %{status: "failed", operation: "download", size_bytes: 999_999, duration_ns: 1},
      %{status: "present", operation: "upload", size_bytes: 999_999, duration_ns: 1}
    ]

    assert %{value: "1.0 Mbps", empty: false} = CargoCache.throughput(samples, "download")
    assert %{empty: true} = CargoCache.throughput(samples, "upload")
  end

  test "task expansion shows unique recorded references independently of transfer operations" do
    task = %{cas_keys: ["sha256:empty:0", "sha256:artifact:42", "sha256:empty:0"]}
    references = CargoCache.references(task)

    assert Enum.map(references, & &1.key) == ["sha256:empty:0", "sha256:artifact:42"]
    assert Enum.all?(references, &(&1.label == "CAS object:"))
    assert Enum.all?(references, &(&1 |> Map.keys() |> Enum.sort() == [:key, :label]))
    assert CargoCache.references(%{}) == []
  end

  test "filtering preserves stable per-operation identity and bounds pages" do
    rows = for id <- 0..24, do: %{id: "#{id}", name: "crate", key: "#{id}", status: "hit"}
    assert %{rows: first, pages: 2, page: 1} = CargoCache.page(rows, "crate", "key", "all", 1)
    assert length(first) == 20
    assert %{rows: last, pages: 2, page: 2} = CargoCache.page(rows, "crate", "key", "hit", 250)
    assert length(last) == 5
    assert %{rows: [], pages: 1} = CargoCache.page(rows, "absent", "key", "all", 1)
  end
end
