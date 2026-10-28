defmodule TuistWeb.Helpers.BuildEntityParamsTest do
  use ExUnit.Case, async: true

  alias Tuist.BuildEntities.Params, as: BuildEntityParams

  @now ~U[2026-10-09 12:00:00Z]

  test "bounds default queries and accepts both transport key forms" do
    assert {:ok, opts} = BuildEntityParams.parse(%{}, @now)
    assert opts[:page_size] == 20
    assert opts[:environment] == "any"
    assert DateTime.diff(@now, opts[:start_datetime], :day) == 30

    assert {:ok, opts} =
             BuildEntityParams.parse(%{"page" => "2", "environment" => "ci", "branch" => "feature/a"}, @now)

    assert opts[:page] == 2
    assert opts[:branch] == "feature/a"
    assert opts[:environment] == "ci"
  end

  test "rejects unbounded, invalid and reversed queries" do
    for params <- [
          %{page: 0},
          %{page: "1 OR 1"},
          %{page_size: 101},
          %{environment: "unknown"},
          %{start_at: "2020-01-01T00:00:00Z"},
          %{end_at: "2027-01-01T00:00:00Z"},
          %{start_at: "2026-10-08T00:00:00Z", end_at: "2026-10-07T00:00:00Z"},
          %{start_at: "invalid"}
        ] do
      assert {:error, _} = BuildEntityParams.parse(params, @now)
    end
  end
end
