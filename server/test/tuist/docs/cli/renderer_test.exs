defmodule Tuist.Docs.CLI.RendererTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.CLI.Renderer
  alias Tuist.Docs.Page
  alias Tuist.Docs.Sidebar.Group
  alias Tuist.Docs.Sidebar.Item

  @spec_fixture %{
    "command" => %{
      "commandName" => "tuist",
      "abstract" => "Build better apps faster.",
      "subcommands" => [
        %{
          "commandName" => "generate",
          "abstract" => "Generates an Xcode workspace.",
          "shouldDisplay" => true,
          "arguments" => [
            %{
              "valueName" => "path",
              "kind" => "option",
              "abstract" => "The path to the directory. (env: TUIST_GENERATE_PATH)",
              "isOptional" => true,
              "shouldDisplay" => true,
              "names" => [
                %{"kind" => "long", "name" => "path"},
                %{"kind" => "short", "name" => "p"}
              ]
            },
            %{
              "valueName" => "no-open",
              "kind" => "flag",
              "abstract" => "Don't open the project.",
              "isOptional" => true,
              "shouldDisplay" => true,
              "names" => [%{"kind" => "long", "name" => "no-open"}]
            },
            %{
              "valueName" => "help",
              "kind" => "flag",
              "abstract" => "Show help information.",
              "isOptional" => true,
              "shouldDisplay" => true,
              "names" => [%{"kind" => "long", "name" => "help"}, %{"kind" => "short", "name" => "h"}]
            }
          ],
          "subcommands" => []
        },
        %{
          "commandName" => "hidden-cmd",
          "abstract" => "Hidden command.",
          "shouldDisplay" => false,
          "arguments" => [],
          "subcommands" => []
        },
        %{
          "commandName" => "cache",
          "abstract" => "Cache operations.",
          "shouldDisplay" => true,
          "arguments" => [],
          "subcommands" => [
            %{
              "commandName" => "warm",
              "abstract" => "Warms the cache.",
              "shouldDisplay" => true,
              "arguments" => [],
              "subcommands" => []
            }
          ]
        }
      ]
    }
  }

  describe "build_pages/1" do
    test "generates pages for visible commands" do
      pages = Renderer.build_pages(@spec_fixture)

      slugs = Enum.map(pages, & &1.slug)
      assert "/en/references/cli/generate" in slugs
      assert "/en/references/cli/cache" in slugs
      assert "/en/references/cli/cache/warm" in slugs
    end

    test "excludes hidden commands" do
      pages = Renderer.build_pages(@spec_fixture)

      slugs = Enum.map(pages, & &1.slug)
      refute "/en/references/cli/hidden-cmd" in slugs
    end

    test "generates valid Page structs" do
      [page | _] = Renderer.build_pages(@spec_fixture)

      assert %Page{} = page
      assert is_binary(page.slug)
      assert is_binary(page.title)
      assert is_binary(page.body)
      assert is_binary(page.markdown)
      assert is_list(page.headings)
    end

    test "includes command abstract in page body" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/generate"))

      assert generate_page.body =~ "Generates an Xcode workspace"
    end

    test "renders arguments with usage examples" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/generate"))

      assert generate_page.body =~ "--path"
      assert generate_page.body =~ "-p"
      assert generate_page.body =~ "--no-open"
    end

    test "extracts environment variables from argument abstracts" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/generate"))

      assert generate_page.body =~ "TUIST_GENERATE_PATH"
    end

    test "excludes help arguments" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/generate"))

      refute generate_page.markdown =~ "### help"
    end

    test "extracts headings from rendered HTML" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/generate"))

      heading_texts = Enum.map(generate_page.headings, & &1.text)
      assert "Arguments" in heading_texts
      assert Enum.any?(heading_texts, &String.starts_with?(&1, "path"))
      assert Enum.any?(heading_texts, &String.starts_with?(&1, "no-open"))
      refute Enum.any?(heading_texts, &String.starts_with?(&1, "help"))
    end

    test "heading IDs match the anchor IDs in the HTML" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/generate"))

      for heading <- generate_page.headings do
        assert generate_page.body =~ ~s(id="#{heading.id}")
      end
    end

    test "sets title_template for CLI pages" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/generate"))

      assert generate_page.title_template == ":title · CLI · References · Tuist"
    end
  end

  describe "build_sidebar/1" do
    test "returns CLI static pages and command groups" do
      [cli_group, commands_group] = Renderer.build_sidebar(@spec_fixture)

      assert %Group{label: "CLI"} = cli_group
      assert %Group{label: "Commands"} = commands_group
    end

    test "includes static CLI pages" do
      [cli_group, _] = Renderer.build_sidebar(@spec_fixture)

      labels = Enum.map(cli_group.items, & &1.label)
      assert "Debugging" in labels
      assert "Directories" in labels
      assert "Shell completions" in labels
    end

    test "excludes hidden commands from sidebar" do
      [_, commands_group] = Renderer.build_sidebar(@spec_fixture)

      labels = Enum.map(commands_group.items, & &1.label)
      refute "hidden-cmd" in labels
    end

    test "sorts commands alphabetically" do
      [_, commands_group] = Renderer.build_sidebar(@spec_fixture)

      labels = Enum.map(commands_group.items, & &1.label)
      assert labels == Enum.sort(labels)
    end

    test "includes subcommands as nested items" do
      [_, commands_group] = Renderer.build_sidebar(@spec_fixture)

      cache_item = Enum.find(commands_group.items, &(&1.label == "cache"))
      assert %Item{} = cache_item
      assert length(cache_item.items) == 1
      assert hd(cache_item.items).label == "warm"
    end
  end
end
