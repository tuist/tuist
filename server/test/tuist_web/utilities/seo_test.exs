defmodule TuistWeb.Utilities.SEOTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias TuistWeb.LayoutComponents
  alias TuistWeb.Utilities.SEO

  test "canonical URLs strip tracking, filters, fragments, and trailing slashes" do
    for path <- ["/cache?utm_source=search", "/cache/?demo=true#top", "/cache"] do
      assert SEO.canonical_url(path) == Environment.app_url(path: "/cache")
    end

    assert SEO.canonical_url("/es/blog?page=2") == Environment.app_url(path: "/es/blog")
    assert SEO.canonical_url(nil) == Environment.app_url(path: "/")
    assert SEO.canonical_url("/tuist/tuist/analytics?tab=builds") == Environment.app_url(path: "/tuist/tuist")

    assert SEO.canonical_url("/tuist/tuist/invocations/123") ==
             Environment.app_url(path: "/tuist/tuist/builds/invocations/123")
  end

  test "project metadata has a page-specific description and canonical social URL" do
    html =
      render_component(&LayoutComponents.head_meta_meta_tags/1,
        selected_project: %{name: "tuist"},
        selected_account: %{name: "tuist-org"},
        head_title: "Builds · tuist-org/tuist · Tuist",
        current_path: "/tuist-org/tuist/builds?utm_source=search"
      )

    document = Floki.parse_document!(html)
    assert [description] = Floki.attribute(document, "meta[name=description]", "content")
    assert description =~ "Builds for tuist-org/tuist"
    assert Floki.attribute(document, "meta[property='og:description']", "content") == [description]

    assert Floki.attribute(document, "meta[property='og:url']", "content") ==
             [Environment.app_url(path: "/tuist-org/tuist/builds")]

    html =
      render_component(&LayoutComponents.head_meta_meta_tags/1,
        selected_project: %{name: "tuist"},
        selected_account: %{name: "tuist-org"},
        head_description: "A specific page description"
      )

    assert html =~ "A specific page description"
    refute html =~ "Explore the project's"
  end

  test "only informational project pages opt into indexing" do
    for path <- ["/tuist/tuist", "/tuist/tuist/builds", "/tuist/tuist/tests/test-runs/123", "/tuist/tuist/previews/123"] do
      assert SEO.public_project_route?(path)
    end

    for path <- [
          "/tuist/tuist/settings",
          "/tuist/tuist/settings/automations",
          "/tuist/tuist/connect",
          "/tuist/tuist/runs/123/download",
          "/tuist/tuist/builds/build-runs/123/timeline.json",
          "/tuist/tuist/previews/123/download",
          "/users/log_in"
        ] do
      refute SEO.public_project_route?(path)
    end
  end
end
