defmodule Tuist.DocsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Docs
  alias Tuist.Docs.CLI
  alias Tuist.Docs.Page

  describe "get_page/1" do
    test "loads an English documentation page" do
      page = Docs.get_page("/en/guides/install-tuist")

      assert page.slug == "/en/guides/install-tuist"
      assert page.title == "Install Tuist"
      assert page.body =~ "Install Tuist"
    end

    test "supports index aliases" do
      root_page = Docs.get_page("/en/index")
      selective_testing_page = Docs.get_page("/en/guides/features/selective-testing/index")

      assert root_page.slug == "/en"
      assert selective_testing_page.slug == "/en/guides/features/selective-testing"
    end

    test "loads static CLI documentation pages" do
      stub(CLI, :get_page, fn
        "/en/cli/debugging" ->
          %Page{
            slug: "/en/cli/debugging",
            title: "Debugging",
            body: "Debugging",
            source_path: "test://cli/debugging"
          }

        _slug ->
          nil
      end)

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
      assert [_ | _] = page.headings

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

    test "wraps Markdown tables in a scroll container" do
      page = Docs.get_page("/en/guides/server/self-host/server")

      assert page.body =~ ~s(<div id="docs-markdown-table-0" class="noora-table" phx-hook="NooraTable">)
      assert page.body =~ ~s(<div data-part="scroll-container"><table>)

      assert page.body =~
               ~s(<div data-part="scrollbar" aria-hidden="true"><div data-part="scrollbar-content"></div></div>)

      assert page.body =~
               ~s(<div data-part="overlay-scrollbar" aria-hidden="true"><div data-part="overlay-thumb"></div></div>)
    end
  end

  describe "get_page/2" do
    test "loads an English documentation page from locale and path segments" do
      page = Docs.get_page("en", ["guides", "install-tuist"])

      assert page.slug == "/en/guides/install-tuist"
      assert page.title == "Install Tuist"
      assert page.markdown =~ "# Install Tuist"
    end

    test "returns nil when the docs page does not exist" do
      assert Docs.get_page("en", ["guides", "does-not-exist"]) == nil
    end
  end
end
