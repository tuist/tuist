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

    test "applies the prefix rule for hand-written /cli/* pages" do
      assert Redirects.resolve("/en/docs/cli/debugging") ==
               {:ok, "/en/docs/references/cli/debugging"}
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

    test "nests auto-generated command pages under /references/cli/commands/" do
      assert Redirects.resolve("/en/docs/references/cli/generate") ==
               {:ok, "/en/docs/references/cli/commands/generate"}

      assert Redirects.resolve("/en/docs/references/cli/cache/warm") ==
               {:ok, "/en/docs/references/cli/commands/cache/warm"}
    end

    test "keeps hand-written CLI pages flat" do
      assert Redirects.resolve("/en/docs/references/cli/debugging") == :none
      assert Redirects.resolve("/en/docs/references/cli/directories") == :none
      assert Redirects.resolve("/en/docs/references/cli/shell-completions") == :none
    end

    test "does not loop when the path is already under /commands/" do
      assert Redirects.resolve("/en/docs/references/cli/commands/generate") == :none
    end

    test "chains the CLI-move and commands-nesting rules in one hop" do
      assert Redirects.resolve("/en/docs/cli/generate") ==
               {:ok, "/en/docs/references/cli/commands/generate"}

      assert Redirects.resolve("/en/docs/cli/cache/warm") ==
               {:ok, "/en/docs/references/cli/commands/cache/warm"}
    end

    test "chains without pushing static CLI pages into /commands/" do
      assert Redirects.resolve("/en/docs/cli/debugging") ==
               {:ok, "/en/docs/references/cli/debugging"}
    end
  end
end
