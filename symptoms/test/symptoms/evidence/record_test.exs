defmodule Symptoms.Evidence.RecordTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.Record

  @valid %{
    entity: %{service: "tuist-server", kind: "route", key: "POST /api/runs"},
    phenomenon: :request_errors,
    source: "trace.error_betabinomial",
    window_start: ~U[2026-11-16 10:00:00Z],
    window_seconds: 60,
    statistic: 2.5,
    e: 3.2,
    impact: %{unit: "failed_requests_per_min", rate: 12.0},
    examples: ["trace-1", "trace-2"]
  }

  test "builds a valid record" do
    assert {:ok, %Record{e: 3.2, examples: ["trace-1", "trace-2"]}} = Record.new(@valid)
  end

  test "rejects invalid fields" do
    assert {:error, {:phenomenon, :invalid}} = Record.new(%{@valid | phenomenon: :errors})
    assert {:error, {:e, :invalid}} = Record.new(%{@valid | e: 20.5})
    assert {:error, {:examples, :invalid}} = Record.new(%{@valid | examples: ["1", "2", "3", "4"]})
    assert {:error, {:impact, :invalid}} = Record.new(%{@valid | impact: %{unit: "x", rate: -1}})
    assert {:error, {:window_seconds, :invalid}} = Record.new(%{@valid | window_seconds: 0})
  end
end
