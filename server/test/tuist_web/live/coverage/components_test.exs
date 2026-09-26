defmodule TuistWeb.Coverage.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Coverage.Components

  describe "measured_by_cell/1" do
    test "shows both of two schemes" do
      html =
        render_component(&Components.measured_by_cell/1,
          commit: %{git_commit_sha: "a", schemes: ["App", "Kit"], partial_schemes: []}
        )

      assert html =~ "App"
      assert html =~ "Kit"
      refute html =~ "+"
    end

    test "folds every scheme past the first into a count" do
      html =
        render_component(&Components.measured_by_cell/1,
          commit: %{git_commit_sha: "a", schemes: ["App", "Kit", "Core"], partial_schemes: ["Core"]}
        )

      assert html =~ "App"
      assert html =~ "+2"
      assert html =~ "coverage-schemes-a"
      assert html =~ "Kit, Core"
      refute html =~ ">Kit<"
    end
  end

  describe "brief_line_ranges/1" do
    test "shows up to two ranges and folds the rest into an ellipsis, with every range for a title" do
      assert Components.brief_line_ranges([{1, 3}, {5, 5}]) == "1–3, 5"
      assert Components.full_line_ranges([{1, 3}, {5, 5}]) == nil
      assert Components.brief_line_ranges([[1, 3], [5, 5], [8, 9]]) == "1–3, 5, …"
      assert Components.full_line_ranges([[1, 3], [5, 5], [8, 9]]) == "1–3, 5, 8–9"
      assert Components.brief_line_ranges(nil) == "—"
    end
  end

  describe "chart_points/2" do
    defp point(date, coverage), do: %{committed_at: DateTime.new!(date, ~T[12:00:00]), coverage: coverage}

    test "keeps every commit over a month, the last of each week over half a year, and of each month past it" do
      points = [
        point(~D[2026-01-05], 10.0),
        point(~D[2026-01-07], 11.0),
        point(~D[2026-01-13], 12.0),
        point(~D[2026-02-02], 13.0),
        point(~D[2026-02-20], 14.0)
      ]

      month = {~U[2026-01-01 00:00:00Z], ~U[2026-01-31 00:00:00Z]}
      half_year = {~U[2026-01-01 00:00:00Z], ~U[2026-06-30 00:00:00Z]}
      year = {~U[2026-01-01 00:00:00Z], ~U[2026-12-31 00:00:00Z]}

      assert Components.chart_points(points, month) == points
      assert Enum.map(Components.chart_points(points, half_year), & &1.coverage) == [11.0, 12.0, 13.0, 14.0]
      assert Enum.map(Components.chart_points(points, year), & &1.coverage) == [12.0, 14.0]
    end
  end

  describe "coverage_sources_card/1" do
    defp summary(attrs) do
      Map.merge(
        %{
          git_commit_sha: "abcdef0123456789",
          covered_lines: 40,
          executable_lines: 100,
          reported: nil
        },
        attrs
      )
    end

    defp reported(kind, attrs) do
      Map.merge(
        %{
          kind: kind,
          covered_lines: 55,
          executable_lines: 110,
          skipped_tests_count: 6,
          carried_tests_count: 6,
          gap_files_count: 0,
          carried_from: ["1111111aaaa"]
        },
        attrs
      )
    end

    defp card(summary, attrs \\ []) do
      render_component(
        &Components.coverage_sources_card/1,
        Keyword.merge([summary: summary, commit_href: &"/commits/#{&1}"], attrs)
      )
    end

    test "splits the covered lines into measured here and reused, and counts the skipped tests" do
      sources = Components.coverage_sources(summary(%{reported: reported("partial", %{carried_tests_count: 4})}))

      assert %{measured: 40, reused_lines: 15, uncovered: 55, executable: 110} = sources
      assert %{skipped: 6, reused: 4, unknown: 2, carried_from: ["1111111aaaa"]} = sources
    end

    test "shows a commit by its reported figure once its runs skipped tests, only its confirmed part when some were not carried" do
      measured = %{coverage: 40.0, reported: nil, reported_kind: "measured"}
      exact = %{coverage: 40.0, reported: %{kind: "reported", coverage: 50.0}, reported_kind: "reported"}
      partial = %{coverage: 40.0, reported: %{kind: "partial", coverage: 45.0}, reported_kind: "partial"}
      selective = %{coverage: 40.0, reported: nil, reported_kind: "observed", partial_schemes: ["App"]}

      assert {Components.displayed_coverage(measured), Components.confirmed?(measured)} == {40.0, true}
      assert {Components.displayed_coverage(exact), Components.confirmed?(exact)} == {50.0, true}
      assert {Components.displayed_coverage(partial), Components.confirmed?(partial)} == {45.0, false}
      assert {Components.displayed_coverage(selective), Components.confirmed?(selective)} == {40.0, false}
    end

    test "breaks a commit's coverage down when some of it was reused or some of it is unknown" do
      assert Components.coverage_breakdown?(summary(%{reported: reported("reported", %{})}))
      # Nothing reused, but some skipped tests could not be.
      assert Components.coverage_breakdown?(
               summary(%{reported: reported("partial", %{covered_lines: 40, carried_tests_count: 0})})
             )

      # A selective run that did not list the tests it could have run.
      assert Components.coverage_breakdown?(
               summary(%{reported_kind: "observed", partial_schemes: ["App"], reported: reported("observed", %{})})
             )

      refute Components.coverage_breakdown?(summary(%{}))
      refute Components.coverage_breakdown?(summary(%{reported_kind: "observed", partial_schemes: []}))
    end

    test "counts every covered line as measured when nothing was reused" do
      assert %{kind: "measured", measured: 40, reused_lines: 0, uncovered: 60, skipped: 0} =
               Components.coverage_sources(summary(%{}))
    end

    test "stacks what was measured, what was reused and the rest, with the tests behind each and where the reused came from" do
      html = card(summary(%{reported: reported("reported", %{})}), ran_tests_count: 42)

      assert html =~ "coverage-sources-chart"
      assert html =~ "Covered here"
      assert html =~ "Tests ran"
      assert html =~ "Skipped tests reused"
      assert html =~ ~s(href="/commits/1111111aaaa")
      assert html =~ "Not covered"
      refute html =~ "unknown"
      refute html =~ "coverage-sources-unknown-tooltip"
      refute html =~ "executable lines covered"
    end

    test "names the rest not covered or unknown when some skipped test could not be reused, and says why" do
      html = card(summary(%{reported: reported("partial", %{carried_tests_count: 4, gap_files_count: 1})}))

      assert html =~ "Not covered or unknown"
      assert html =~ "2 skipped tests not reused · 1 changed file no run compiled"
      assert html =~ "coverage-sources-unknown-tooltip"
    end

    test "names what is unknown when the runs ran selectively without listing their tests" do
      html = card(summary(%{reported_kind: "observed", partial_schemes: ["App"], reported: reported("observed", %{})}))

      assert html =~ "Skipped tests not listed"
    end

    test "shows only what was measured when nothing was skipped" do
      html = card(summary(%{}))

      assert html =~ "Not covered"
      refute html =~ "Reused from"
      refute html =~ "coverage-sources-unknown-tooltip"
    end
  end
end
