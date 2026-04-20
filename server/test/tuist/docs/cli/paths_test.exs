defmodule Tuist.Docs.CLI.PathsTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.CLI.Paths

  describe "page_slug/1" do
    test "builds English slugs for hand-written CLI pages" do
      assert Paths.page_slug("debugging") == "/en/references/cli/debugging"
    end
  end

  describe "command_slug/1" do
    test "builds English slugs for generated command pages" do
      assert Paths.command_slug("cache/warm") == "/en/references/cli/commands/cache/warm"
    end
  end

  describe "redirect_rules/0" do
    test "keeps hand-written pages out of the commands namespace" do
      assert {:prefix, "/references/cli/", "/references/cli/commands/", except_starts_with: except_starts_with} =
               Enum.at(Paths.redirect_rules(), 2)

      assert "debugging" in except_starts_with
      assert "directories" in except_starts_with
      assert "shell-completions" in except_starts_with
      assert "commands/" in except_starts_with
    end
  end
end
