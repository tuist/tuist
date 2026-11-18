defmodule Tuist.DashboardSearchQueryTest do
  use ExUnit.Case, async: true

  alias Tuist.DashboardSearchQuery

  test "quoted values, phrases, literal colons and escaped quotes retain their boundaries" do
    assert {:ok,
            %{terms: ["hello world", "suite::test", "a \"quote\""], filters: %{"branch" => "release branch", "pr" => 12}}} =
             DashboardSearchQuery.parse(~s(branch:"release branch" "hello world" "Suite::test" "a \\"quote\\"" pr:#12))
  end

  test "calendar dates are UTC and ranges include both named days" do
    today = Date.utc_today()
    assert {:ok, %{filters: %{"date" => {first, last}}}} = DashboardSearchQuery.parse("date:today")
    assert first == "#{today}T00:00:00Z"
    assert last == "#{Date.add(today, 1)}T00:00:00Z"

    assert {:ok, %{filters: %{"date" => {"2026-01-01T00:00:00Z", "2026-01-04T00:00:00Z"}}}} =
             DashboardSearchQuery.parse("date:2026-01-01..2026-01-03")

    assert {:ok, %{filters: %{"date" => {"2026-01-02T00:00:00Z", nil}}}} = DashboardSearchQuery.parse("date:>2026-01-01")
    assert {:ok, %{filters: %{"date" => {nil, "2026-01-01T00:00:00Z"}}}} = DashboardSearchQuery.parse("date:<2026-01-01")
  end

  test "all documented resource types parse and unknown or duplicate filters never become text" do
    for type <- ~w(page project test-case test-run build preview) do
      assert {:ok, %{filters: %{"is" => parsed}}} = DashboardSearchQuery.parse("is:#{type}")
      assert parsed == String.replace(type, "-", "_")
    end

    for query <- [
          "is:",
          "is:build is:build",
          "PR:1",
          "pr:+1",
          "pr:4294967296",
          "commit:",
          "date:2026-1-1",
          ~s(branch:"missing),
          ~s("")
        ] do
      assert {:error, message} = DashboardSearchQuery.parse(query)
      assert is_binary(message)
    end
  end
end
