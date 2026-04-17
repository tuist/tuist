defmodule Tuist.Docs.CLITest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Docs.CLI

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
            }
          ],
          "subcommands" => []
        },
        %{
          "commandName" => "build",
          "abstract" => "Builds a project.",
          "shouldDisplay" => true,
          "arguments" => [],
          "subcommands" => [
            %{
              "commandName" => "start",
              "abstract" => "Starts a build.",
              "shouldDisplay" => true,
              "arguments" => [],
              "subcommands" => []
            }
          ]
        }
      ]
    }
  }

  setup do
    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)
    {:ok, cache: cache}
  end

  describe "get_pages/1" do
    test "returns pages when spec is fetched successfully", %{cache: cache} do
      stub(Req, :get, fn url, _opts ->
        cond do
          String.contains?(url, "api.github.com") ->
            {:ok, %{status: 200, body: [%{"tag_name" => "4.167.0"}]}}

          String.contains?(url, "tuist.spec.json") ->
            {:ok, %{status: 200, body: @spec_fixture}}
        end
      end)

      pages = CLI.get_pages(cache: cache)

      assert length(pages) == 3
      slugs = Enum.map(pages, & &1.slug)
      assert "/en/references/cli/generate" in slugs
      assert "/en/references/cli/build" in slugs
      assert "/en/references/cli/build/start" in slugs
    end

    test "returns empty list when GitHub API fails", %{cache: cache} do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 500}}
      end)

      assert CLI.get_pages(cache: cache) == []
    end

    test "returns empty list when no CLI release is found", %{cache: cache} do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: [%{"tag_name" => "server@1.0.0"}]}}
      end)

      assert CLI.get_pages(cache: cache) == []
    end

    test "caches the result after first fetch", %{cache: cache} do
      call_count = :counters.new(1, [:atomics])

      stub(Req, :get, fn url, _opts ->
        :counters.add(call_count, 1, 1)

        cond do
          String.contains?(url, "api.github.com") ->
            {:ok, %{status: 200, body: [%{"tag_name" => "4.167.0"}]}}

          String.contains?(url, "tuist.spec.json") ->
            {:ok, %{status: 200, body: @spec_fixture}}
        end
      end)

      CLI.get_pages(cache: cache)
      CLI.get_pages(cache: cache)

      assert :counters.get(call_count, 1) == 2
    end
  end

  describe "get_page/2" do
    test "returns a specific page by slug", %{cache: cache} do
      stub(Req, :get, fn url, _opts ->
        cond do
          String.contains?(url, "api.github.com") ->
            {:ok, %{status: 200, body: [%{"tag_name" => "4.167.0"}]}}

          String.contains?(url, "tuist.spec.json") ->
            {:ok, %{status: 200, body: @spec_fixture}}
        end
      end)

      page = CLI.get_page("/en/references/cli/generate", cache: cache)

      assert page.slug == "/en/references/cli/generate"
      assert page.title == "tuist generate"
      assert page.body =~ "Generates an Xcode workspace"
    end

    test "returns nil for unknown slug", %{cache: cache} do
      stub(Req, :get, fn url, _opts ->
        cond do
          String.contains?(url, "api.github.com") ->
            {:ok, %{status: 200, body: [%{"tag_name" => "4.167.0"}]}}

          String.contains?(url, "tuist.spec.json") ->
            {:ok, %{status: 200, body: @spec_fixture}}
        end
      end)

      assert is_nil(CLI.get_page("/en/references/cli/nonexistent", cache: cache))
    end
  end

  describe "sidebar_items/1" do
    test "returns sidebar groups with static pages and commands", %{cache: cache} do
      stub(Req, :get, fn url, _opts ->
        cond do
          String.contains?(url, "api.github.com") ->
            {:ok, %{status: 200, body: [%{"tag_name" => "4.167.0"}]}}

          String.contains?(url, "tuist.spec.json") ->
            {:ok, %{status: 200, body: @spec_fixture}}
        end
      end)

      [cli_group, commands_group] = CLI.sidebar_items(cache: cache)

      assert cli_group.label == "CLI"
      assert length(cli_group.items) == 3

      assert commands_group.label == "Commands"
      command_labels = Enum.map(commands_group.items, & &1.label)
      assert "build" in command_labels
      assert "generate" in command_labels
    end

    test "returns empty list when fetch fails", %{cache: cache} do
      stub(Req, :get, fn _url, _opts -> {:error, :timeout} end)

      assert CLI.sidebar_items(cache: cache) == []
    end
  end
end
