defmodule TuistWeb.RunnerImageCacheLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.RunnerImageCacheLive

  @period {~U[2026-10-18 00:00:00Z], ~U[2026-10-25 00:00:00Z]}

  defp analytics(attrs \\ %{}) do
    Map.merge(
      %{
        activity: %{uses: 4, hit_rate: 75.0, points: [%{at: ~U[2026-10-24 00:00:00Z], uses: 4, hit_rate: 75.0}]},
        steps: %{
          reused: %{avg: 3_200, p50: 3_100, p90: 4_400, p99: 6_100},
          cold: %{avg: 47_000, p50: 46_000, p90: 52_000, p99: 58_000},
          points: [%{at: ~U[2026-10-24 00:00:00Z], avg: 3_200, p50: 3_100, p90: 4_400, p99: 6_100}]
        }
      },
      attrs
    )
  end

  defp repository(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        repository: "org/android",
        provider: "github",
        platform: "linux",
        architecture: "amd64",
        images: [
          %{
            id: "sha256:" <> String.duplicate("a", 64),
            reference: "ghcr.io/org/build:jdk-21",
            other_references: ["ghcr.io/org/build:latest"],
            size_bytes: 5_000_000_000,
            last_used_at: ~U[2026-10-24 08:00:00Z]
          }
        ],
        image_count: 1,
        saved_bytes: 6_000_000_000,
        build_cache_bytes: 1_000,
        last_saved_at: ~U[2026-10-24 09:00:00Z],
        last_used_at: ~U[2026-10-24 10:00:00Z],
        uses: 4,
        hits: 3,
        hit_rate: 75.0
      },
      attrs
    )
  end

  defp assigns(attrs) do
    Map.merge(
      %{
        selected_account: %{id: 1, name: "org"},
        selected: nil,
        enabled: true,
        metric: "hit_rate",
        initialize_percentile: "avg",
        analytics_preset: "last-7-days",
        analytics_period: @period,
        params: %{},
        search: "",
        sort_by: "last_used",
        sort_order: "desc",
        page: 1
      },
      attrs
    )
  end

  defp data(repositories, attrs \\ %{}) do
    AsyncResult.ok(Map.merge(%{repositories: repositories, analytics: analytics(), previous: analytics()}, attrs))
  end

  test "the overview shows how jobs reused saved images and every repository" do
    html = render_component(&RunnerImageCacheLive.render/1, assigns(%{data: data([repository()])}))

    assert html =~ "Image cache"
    assert html =~ "75.0%"
    assert html =~ "Avg. Initialize containers"
    assert html =~ DateFormatter.format_duration_from_milliseconds(3_200)
    assert html =~ DateFormatter.format_duration_from_milliseconds(47_000)
    assert html =~ DateFormatter.format_duration_from_milliseconds(6_100)
    assert html =~ "org/android"
    assert html =~ "/org/runners/images/"
    assert html =~ "image-repository-search"
  end

  test "the Initialize containers chart follows jobs that started from saved images" do
    html = render_component(&RunnerImageCacheLive.render/1, assigns(%{data: data([repository()]), metric: "initialize"}))

    assert html =~ "Initialize containers"
    assert html =~ "formatMilliseconds"
  end

  test "the overview filters repositories by the search" do
    rows = [repository(), repository(%{repository: "org/web"})]
    html = render_component(&RunnerImageCacheLive.render/1, assigns(%{data: data(rows), search: "web"}))

    assert html =~ "org/web"
    refute html =~ "org/android"
  end

  test "the overview says when the cache is not enabled and no repository uses it" do
    html =
      render_component(
        &RunnerImageCacheLive.render/1,
        assigns(%{
          data:
            data([], %{
              analytics:
                analytics(%{
                  steps: %{
                    reused: %{avg: nil, p50: nil, p90: nil, p99: nil},
                    cold: %{avg: nil, p50: nil, p90: nil, p99: nil},
                    points: []
                  }
                })
            }),
          enabled: false
        })
      )

    assert html =~ "No repositories found"
    assert html =~ "not enabled"
  end

  test "a repository's page lists the images its data root keeps" do
    selected = repository()
    html = render_component(&RunnerImageCacheLive.render/1, assigns(%{selected: selected, data: data([])}))

    assert html =~ "ghcr.io/org/build:jdk-21"
    assert html =~ "ghcr.io/org/build:latest"
    assert html =~ "/org/runners/volumes/#{selected.id}"
    assert html =~ "Image cache details"
  end

  test "a repository with nothing saved yet says so" do
    selected = repository(%{images: [], image_count: 0, saved_bytes: nil, last_saved_at: nil})
    html = render_component(&RunnerImageCacheLive.render/1, assigns(%{selected: selected, data: data([])}))

    assert html =~ "No images saved yet"
  end
end
