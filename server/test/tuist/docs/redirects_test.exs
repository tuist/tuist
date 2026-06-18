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

    test "redirects old SSO guide to authentication SSO guide" do
      assert Redirects.resolve("/en/docs/guides/integrations/sso") ==
               {:ok, "/en/docs/guides/integrations/authentication/sso"}
    end

    test "redirects the old self-host installation route to server" do
      assert Redirects.resolve("/en/docs/guides/server/self-host/install") ==
               {:ok, "/en/docs/guides/server/self-host/server"}
    end

    test "redirects the old self-host control plane route to server" do
      assert Redirects.resolve("/en/docs/guides/server/self-host/control-plane") ==
               {:ok, "/en/docs/guides/server/self-host/server"}
    end

    test "redirects the old Kura self-hosting route to cache self-hosting" do
      assert Redirects.resolve("/en/docs/guides/server/self-host/kura") ==
               {:ok, "/en/docs/guides/features/cache/self-hosting"}
    end

    test "redirects the old translation guide slug to languages" do
      assert Redirects.resolve("/en/docs/contributors/translate") ==
               {:ok, "/en/docs/contributors/languages"}
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
