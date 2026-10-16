defmodule TuistWeb.Runs.RanByBadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Runs.RanByBadge

  test "uses the shared CI badge independently of an account name" do
    html = render_component(&RanByBadge.run_ran_by_badge_cell/1, run: %{is_ci: true}, ran_by_name: "reporter")
    assert badge_label(html, "information") == "CI"
    refute html =~ "reporter"
  end

  test "uses the reporting account badge for known local work" do
    html = render_component(&RanByBadge.run_ran_by_badge_cell/1, run: %{is_ci: false}, ran_by_name: "reporter")
    assert badge_label(html, "primary") == "reporter"
  end

  test "missing local attribution remains Unknown" do
    for name <- [nil, ""] do
      html = render_component(&RanByBadge.run_ran_by_badge_cell/1, run: %{is_ci: false}, ran_by_name: name)
      assert badge_label(html, "neutral") == "Unknown"
    end
  end

  test "unknown environment never becomes CI or an inferred local user" do
    for name <- [nil, "reporter"] do
      html = render_component(&RanByBadge.run_ran_by_badge_cell/1, run: %{is_ci: nil}, ran_by_name: name)
      assert badge_label(html, "neutral") == "Unknown"
      refute html =~ "reporter"
    end
  end

  defp badge_label(html, color) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(".noora-badge[data-color=#{color}]")
    |> Floki.text()
    |> String.trim()
  end
end
