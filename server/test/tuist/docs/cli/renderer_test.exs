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
    test "builds pages for the visible command tree" do
      assert @spec_fixture
             |> Renderer.build_pages()
             |> Enum.map(&{&1.title, &1.slug}) == [
               {"tuist generate", "/en/references/cli/commands/generate"},
               {"tuist cache", "/en/references/cli/commands/cache"},
               {"tuist cache warm", "/en/references/cli/commands/cache/warm"}
             ]
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
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/commands/generate"))

      assert generate_page.body =~ "Generates an Xcode workspace"
    end

    test "renders arguments with usage examples" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/commands/generate"))

      assert generate_page.body =~ "--path"
      assert generate_page.body =~ "-p"
      assert generate_page.body =~ "--no-open"
    end

    test "extracts environment variables from argument abstracts" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/commands/generate"))

      assert generate_page.body =~ "TUIST_GENERATE_PATH"
    end

    test "excludes help arguments" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/commands/generate"))

      refute generate_page.markdown =~ "### help"
    end

    test "extracts headings from rendered HTML" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/commands/generate"))

      heading_texts = Enum.map(generate_page.headings, & &1.text)
      assert "Arguments" in heading_texts
      assert Enum.any?(heading_texts, &String.starts_with?(&1, "path"))
      assert Enum.any?(heading_texts, &String.starts_with?(&1, "no-open"))
      refute Enum.any?(heading_texts, &String.starts_with?(&1, "help"))
    end

    test "heading IDs match the anchor IDs in the HTML" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/commands/generate"))

      for heading <- generate_page.headings do
        assert generate_page.body =~ ~s(id="#{heading.id}")
      end
    end

    test "sets title_template for CLI pages" do
      pages = Renderer.build_pages(@spec_fixture)
      generate_page = Enum.find(pages, &(&1.slug == "/en/references/cli/commands/generate"))

      assert generate_page.title_template == ":title · CLI · References · Tuist"
    end
  end

  describe "build_sidebar/1" do
    test "builds the CLI sidebar tree with static pages and nested commands" do
      assert @spec_fixture
             |> Renderer.build_sidebar()
             |> simplify_groups() == [
               {"CLI",
                [
                  {"Debugging", "/en/references/cli/debugging", []},
                  {"Directories", "/en/references/cli/directories", []},
                  {"Shell completions", "/en/references/cli/shell-completions", []},
                  {"Commands", nil,
                   [
                     {"cache", "/en/references/cli/commands/cache",
                      [{"warm", "/en/references/cli/commands/cache/warm", []}]},
                     {"generate", "/en/references/cli/commands/generate", []}
                   ]}
                ]}
             ]
    end
  end

  defp simplify_groups(groups) do
    Enum.map(groups, fn %Group{label: label, items: items} ->
      {label, Enum.map(items, &simplify_item/1)}
    end)
  end

  defp simplify_item(%Item{label: label, slug: slug, items: items}) do
    {label, slug, Enum.map(items, &simplify_item/1)}
  end
end
