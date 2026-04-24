defmodule Tuist.Docs.RedirectsTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.Redirects

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
