defmodule Tuist.DocsTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs

  describe "get_page/1" do
    test "loads an English documentation page" do
      page = Docs.get_page("/en/guides/install-tuist")

      assert page.slug == "/en/guides/install-tuist"
      assert page.title == "Install Tuist"
      assert page.body =~ "Install Tuist"
    end

    test "loads a Korean documentation page" do
      page = Docs.get_page("/ko/guides/install-tuist")

      assert page.slug == "/ko/guides/install-tuist"
      assert page.title == "Tuist 설치"
      assert page.body =~ "Tuist 설치"
    end

    test "supports index aliases" do
      root_page = Docs.get_page("/en/index")
      selective_testing_page = Docs.get_page("/en/guides/features/selective-testing/index")

      assert root_page.slug == "/en"
      assert selective_testing_page.slug == "/en/guides/features/selective-testing"
    end

    test "loads static CLI documentation pages" do
      page = Docs.get_page("/en/cli/debugging")
      assert page.slug == "/en/cli/debugging"
      assert page.title == "Debugging"
    end

    test "excludes manifest reference generated docs" do
      assert is_nil(Docs.get_page("/en/references/project-description/structs/project"))
    end

    test "extracts headings from documentation pages" do
      page = Docs.get_page("/en/guides/install-tuist")

      assert is_list(page.headings)
      assert length(page.headings) > 0

      assert Enum.all?(page.headings, fn h ->
               Map.has_key?(h, :level) and Map.has_key?(h, :text) and Map.has_key?(h, :id)
             end)

      assert Enum.all?(page.headings, fn h -> h.level in [2, 3, 4] end)
    end

    test "compiles localized_link components into body template" do
      migration_page = Docs.get_page("/en/references/migrations/from-v3-to-v4")

      assert migration_page.body_template
      assert migration_page.body =~ "localized_link"
    end
  end
end
