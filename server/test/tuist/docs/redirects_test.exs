defmodule Tuist.Docs.RedirectsTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.Redirects

  describe "legacy_host_path/1" do
    test "maps the legacy docs host root to the current docs root" do
      assert Redirects.legacy_host_path("/") == "/en/docs"
    end

    test "maps locale-prefixed docs host paths to current docs paths" do
      assert Redirects.legacy_host_path("/en/guides/features/insights") ==
               "/en/docs/guides/features/insights"
    end

    test "falls back unsupported legacy locales to english" do
      assert Redirects.legacy_host_path("/pt/guides/features/cache") ==
               "/en/docs/guides/features/cache"
    end
  end

  describe "resolve/2" do
    test "redirects renamed insights pages" do
      assert Redirects.resolve("/en/docs/guides/features/insights") ==
               {:ok, "/en/docs/guides/features/build-insights"}
    end

    test "redirects legacy guide paths to current feature docs" do
      assert Redirects.resolve("/en/docs/guide/project/dependencies") ==
               {:ok, "/en/docs/guides/features/projects/dependencies"}
    end

    test "resolves chained VitePress redirects to the live destination" do
      assert Redirects.resolve("/en/docs/guides/develop/build/cache") ==
               {:ok, "/en/docs/guides/features/cache"}
    end

    test "preserves dynamic suffixes for example redirects" do
      assert Redirects.resolve("/en/docs/guides/examples/generated-projects/app_with_airship_sdk") ==
               {:ok, "/en/docs/references/examples/generated-projects/app_with_airship_sdk"}
    end

    test "redirects project description references to the external docs" do
      assert Redirects.resolve(
               "/en/docs/reference/project-description/structs/project",
               "tab=api"
             ) ==
               {:ok, "https://projectdescription.tuist.dev/documentation/projectdescription?tab=api"}
    end

    test "returns none when there is no matching redirect" do
      assert Redirects.resolve("/en/docs/guides/features/cache") == :none
    end
  end
end
