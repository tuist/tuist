defmodule TuistWeb.Runs.RanByBadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Accounts.Account
  alias TuistWeb.Runs.RanByBadge

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
      assert html =~ "Unverified"
      assert html =~ "Reported by the build client, not verified."

      verified = Map.put(record, :actor_account, %Account{name: "verified-person"})
      html = render_component(component, [{key, verified}])
      assert html =~ "verified-person"
      refute html =~ "developer-123"
      refute html =~ "Unverified"

      html = render_component(component, [{key, %{record | claimed_actor_id: ""}}])
      assert html =~ "Unknown"
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
end
