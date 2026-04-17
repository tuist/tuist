defmodule Tuist.Docs.RedirectsTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.Redirects

  describe "resolve/2" do
    test "returns :none when the path is outside /:locale/docs" do
      assert Redirects.resolve("/blog/2024/01/01/post") == :none
      assert Redirects.resolve("/api/graphql") == :none
    end

    test "returns :none when the docs path has no matching rule" do
      assert Redirects.resolve("/en/docs/guides/install-tuist") == :none
    end

    test "applies an exact rule for /cli" do
      assert Redirects.resolve("/en/docs/cli") == {:ok, "/en/docs/references/cli"}
    end

    test "applies the prefix rule for /cli/*" do
      assert Redirects.resolve("/en/docs/cli/debugging") ==
               {:ok, "/en/docs/references/cli/debugging"}

      assert Redirects.resolve("/en/docs/cli/cache/warm") ==
               {:ok, "/en/docs/references/cli/cache/warm"}
    end

    test "applies rules across locales" do
      assert Redirects.resolve("/ja/docs/cli/debugging") ==
               {:ok, "/ja/docs/references/cli/debugging"}

      assert Redirects.resolve("/zh_Hans/docs/cli") ==
               {:ok, "/zh_Hans/docs/references/cli"}
    end

    test "preserves query string in resolved path" do
      assert Redirects.resolve("/en/docs/cli/debugging", "foo=bar") ==
               {:ok, "/en/docs/references/cli/debugging?foo=bar"}
    end

    test "does not append a trailing ? when query string is empty" do
      assert Redirects.resolve("/en/docs/cli/debugging", "") ==
               {:ok, "/en/docs/references/cli/debugging"}
    end
  end
end
