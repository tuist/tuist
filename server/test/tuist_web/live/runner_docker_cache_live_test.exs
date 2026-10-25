defmodule TuistWeb.RunnerDockerCacheLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias TuistWeb.RunnerDockerCacheLive

  @activity %{uses: 4, hits: 3, hit_rate: 75.0, hit_step_ms: 3_200, miss_step_ms: 47_000}

  defp repository(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        repository: "org/android",
        status: :ready,
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
        hit_rate: 75.0,
        activity: @activity
      },
      attrs
    )
  end

  defp assigns(attrs) do
    Map.merge(
      %{
        selected_account: %{id: 1, name: "org"},
        selected_id: nil,
        enabled: true,
        can_manage: true,
        analytics_preset: "last-7-days",
        analytics_period: {~U[2026-10-18 00:00:00Z], ~U[2026-10-25 00:00:00Z]},
        params: %{}
      },
      attrs
    )
  end

  test "the overview shows what reusing data roots saved and every repository" do
    overview = %{
      repositories: [repository()],
      saved_repositories: 1,
      images: 1,
      saved_bytes: 6_000_000_000,
      activity: @activity
    }

    html = render_component(&RunnerDockerCacheLive.render/1, assigns(%{overview: AsyncResult.ok(overview)}))

    assert html =~ "Docker cache"
    assert html =~ "75.0%"
    assert html =~ "3.2 s"
    assert html =~ "47.0 s"
    assert html =~ "org/android"
    assert html =~ "Saved"
    assert html =~ "/org/runners/docker-cache/"
    assert html =~ "not billed"
  end

  test "the overview explains how a repository starts using the cache" do
    overview = %{
      repositories: [],
      saved_repositories: 0,
      images: 0,
      saved_bytes: 0,
      activity: %{@activity | hit_rate: nil, hit_step_ms: nil, miss_step_ms: nil}
    }

    html =
      render_component(&RunnerDockerCacheLive.render/1, assigns(%{overview: AsyncResult.ok(overview), enabled: false}))

    assert html =~ "No repository uses the Docker cache yet"
    assert html =~ "Not enabled"
  end

  test "a repository's page lists the images its data root keeps" do
    selected = repository()
    html = render_component(&RunnerDockerCacheLive.render/1, assigns(%{selected_id: selected.id, repository: selected}))

    assert html =~ "ghcr.io/org/build:jdk-21"
    assert html =~ "ghcr.io/org/build:latest"
    assert html =~ "/org/runners/volumes/#{selected.id}"
  end

  test "a repository waiting for its first save says so" do
    selected = repository(%{status: :waiting, images: [], image_count: 0, saved_bytes: nil, last_saved_at: nil})
    html = render_component(&RunnerDockerCacheLive.render/1, assigns(%{selected_id: selected.id, repository: selected}))

    assert html =~ "Waiting for a save"
    assert html =~ "No images saved yet"
  end
end
