defmodule TuistWeb.Runs.RanByBadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Accounts.Account
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

  test "all build and test pages share verified, reported, and unknown presentation" do
    for {component, key} <- [
          {&RanByBadge.build_ran_by_badge_cell/1, :build},
          {&RanByBadge.gradle_build_ran_by_badge_cell/1, :build},
          {&RanByBadge.test_ran_by_badge_cell/1, :test},
          {&RanByBadge.run_ran_by_badge_cell/1, :run}
        ] do
      record = %{is_ci: false, submission_auth: "token", claimed_actor_id: "developer-123"}
      html = render_component(component, [{key, record}])
      assert html =~ "developer-123"
      assert badge_label(html, "neutral") == "developer-123"
      assert html =~ "icon-tabler-device-laptop"
      refute html =~ "Unverified"
      refute html =~ "title="

      verified = Map.put(record, :actor_account, %Account{name: "verified-person"})
      html = render_component(component, [{key, verified}])
      assert badge_label(html, "primary") == "verified-person"
      assert html =~ "icon-tabler-user"
      refute html =~ "icon-tabler-device-laptop"
      refute html =~ "developer-123"
      refute html =~ "Unverified"

      html = render_component(component, [{key, %{record | claimed_actor_id: ""}}])
      assert html =~ "Unknown"

      html = render_component(component, [{key, %{verified | is_ci: nil}}])
      assert badge_label(html, "neutral") == "Unknown"
      refute html =~ "verified-person"
      refute html =~ "developer-123"
    end
  end

  test "reported strings are escaped rather than interpreted as HTML" do
    html =
      render_component(&RanByBadge.gradle_build_ran_by_badge_cell/1,
        build: %{is_ci: false, submission_auth: "network_trusted", claimed_actor_id: "<script>alert(1)</script>"}
      )

    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end

  test "historical rows preserve their account badge and CI remains execution metadata" do
    html =
      render_component(&RanByBadge.build_ran_by_badge_cell/1,
        build: %{is_ci: false, ran_by_account: %Account{name: "historical"}}
      )

    assert html =~ "historical"
    refute html =~ "Unverified"

    html =
      render_component(&RanByBadge.gradle_build_ran_by_badge_cell/1,
        build: %{is_ci: true, submission_auth: "network_trusted", claimed_actor_id: "claimed"}
      )

    assert html =~ "CI"
    refute html =~ "claimed"
  end

  defp badge_label(html, color) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(".noora-badge[data-color=#{color}]")
    |> Floki.text()
    |> String.trim()
  end
end
