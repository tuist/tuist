defmodule TuistWeb.Docs.ReleaseStatusTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias TuistWeb.Docs.ReleaseStatus

  test "channel summaries show current versions and a calendar link without history or scheduled windows" do
    html =
      render_component(&ReleaseStatus.panel/1,
        status: AsyncResult.ok(%{cli: snapshot()}),
        components: [:cli],
        calendar_url: "/en/docs/cli/release/calendar"
      )

    document = Floki.parse_document!(html)
    assert html =~ "4.215.0"
    assert html =~ "4.216.0-rc.2"
    assert html =~ "4.217.0-canary.10"
    assert html =~ "Last checked"
    assert Floki.attribute(document, "time", "datetime") == ["2026-11-06T08:00:00Z"]
    assert Floki.attribute(document, ~s(a[href="/en/docs/cli/release/calendar"]), "href") != []
    assert Floki.find(document, "table") == []
    refute html =~ "Past releases"
    refute html =~ "Upcoming release windows"
  end

  test "links published versions and only targets the pending RC in the first window" do
    html = panel(snapshot())
    document = Floki.parse_document!(html)

    assert Floki.attribute(document, ~s([data-channel="stable"] a), "href") ==
             ["https://github.com/tuist/tuist/releases/tag/4.215.0"]

    assert length(Floki.find(document, ~s([data-part="release-calendar"] tbody > tr))) == 3
    assert html =~ "Target: 4.216.0 stable"
    refute html =~ "Target: 4.217.0"
    assert html =~ "Scheduled"
    assert html =~ "not guaranteed"
    assert html =~ ~s(datetime="2026-11-09T06:00:00Z")
  end

  test "past releases use published dates and notes, with earlier history collapsed and a Today divider" do
    document = snapshot() |> panel() |> Floki.parse_document!()

    assert Floki.attribute(document, "#docs-recent-history-cli a", "href") == [
             "https://github.com/tuist/tuist/releases/tag/4.215.0",
             "https://github.com/tuist/tuist/releases/tag/4.214.1",
             "https://github.com/tuist/tuist/releases/tag/4.216.0-rc.2"
           ]

    assert Floki.text(Floki.find(document, "#docs-recent-history-cli")) =~ "Patch"
    refute Floki.text(Floki.find(document, "#docs-recent-history-cli")) =~ "canary"
    assert Floki.attribute(document, "#docs-earlier-releases-cli", "open") == []
    assert Floki.text(Floki.find(document, "#docs-earlier-releases-cli summary")) == "Show earlier releases"
    assert Floki.text(Floki.find(document, ".noora-line-divider")) =~ "Today"
    assert Floki.attribute(document, "#docs-earlier-history-cli time", "datetime") == ["2026-10-01T12:00:00Z"]
    assert Floki.text(document) =~ "not the full release history"
    assert Floki.text(document) =~ "backports"
  end

  test "unavailable history does not hide channels or future windows" do
    html = panel(%{snapshot() | history: nil})
    assert html =~ "Release history could not be loaded"
    assert html =~ "4.215.0"
    assert html =~ "Target: 4.216.0 stable"
    assert html =~ "Full release history on GitHub"
  end

  test "stale data retains versions but never presents a stale RC as the next release target" do
    html = panel(%{snapshot() | state: :stale})
    assert html =~ "Outdated data"
    assert html =~ "last successfully checked"
    assert html =~ "4.216.0-rc.2"
    refute html =~ "Target:"
  end

  test "missing data and missing schedule do not invent versions or dates" do
    data = %{snapshot() | rc: nil, schedule: []}
    html = panel(data)
    assert html =~ "No pending candidate"
    assert html =~ "schedule could not be verified"
    refute html =~ "Target:"

    unavailable = panel(%{data | state: :unavailable, stable: nil, canary: nil, checked_at: nil, promotion: nil})
    assert unavailable =~ "No release dates or versions have been inferred"
    refute unavailable =~ "release-calendar"
    refute unavailable =~ "Last checked"
    assert unavailable =~ "View release workflow"
  end

  test "loading and failed loads retain a usable GitHub link" do
    for status <- [
          AsyncResult.loading(),
          AsyncResult.failed(AsyncResult.loading(), :timeout),
          AsyncResult.failed(AsyncResult.ok(%{cli: snapshot()}), :timeout)
        ] do
      html =
        render_component(&ReleaseStatus.panel/1,
          status: status,
          components: [:cli],
          calendar_url: "/en/docs/cli/release/calendar"
        )

      assert html =~ "View releases on GitHub"
      assert html =~ "View release calendar"
      refute html =~ "release-calendar"
      refute html =~ "Up to date"
    end
  end

  defp panel(data) do
    render_component(&ReleaseStatus.panel/1, status: AsyncResult.ok(%{cli: data}), components: [:cli])
  end

  defp snapshot do
    %{
      state: :fresh,
      checked_at: ~U[2026-11-06 08:00:00Z],
      stable: release("4.215.0"),
      rc: release("4.216.0-rc.2"),
      canary: release("4.217.0-canary.10"),
      history: %{
        recent: [
          Map.put(release("4.215.0"), :kind, :stable),
          Map.put(release("4.214.1"), :kind, :patch),
          Map.put(release("4.216.0-rc.2"), :kind, :rc)
        ],
        earlier: [%{Map.put(release("4.213.0"), :kind, :stable) | published_at: ~U[2026-10-01 12:00:00Z]}],
        limited?: true
      },
      promotion: %{status: "completed", conclusion: "failure", url: "https://github.com/tuist/tuist/actions/runs/123"},
      schedule: Enum.map([9, 16, 23, 30], &DateTime.new!(Date.new!(2026, 11, &1), ~T[06:00:00])),
      workflow_url: "https://github.com/tuist/tuist/actions/workflows/cli-promote.yml"
    }
  end

  defp release(version) do
    %{
      version: version,
      url: "https://github.com/tuist/tuist/releases/tag/#{version}",
      published_at: ~U[2026-11-03 12:00:00Z]
    }
  end
end
