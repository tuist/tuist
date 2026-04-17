defmodule Tuist.Docs.CLI.Renderer do
  @moduledoc """
  Renders CLI spec JSON into documentation pages and sidebar items.
  """

  alias Tuist.Docs.HTML
  alias Tuist.Docs.Page
  alias Tuist.Docs.Sidebar.Group
  alias Tuist.Docs.Sidebar.Item

  @env_var_regex ~r/\(env:\s*([^)]+)\)/
  @deprecated_regex ~r/\[(?:D|d)eprecated\]/
  @angle_bracket_regex ~r/<([^>]+)>/

  def build_pages(spec) do
    spec
    |> get_in(["command", "subcommands"])
    |> List.wrap()
    |> Enum.flat_map(&traverse_commands(&1, "tuist"))
  end

  def build_sidebar(spec) do
    commands =
      spec
      |> get_in(["command", "subcommands"])
      |> List.wrap()
      |> Enum.filter(&(&1["shouldDisplay"] != false))
      |> Enum.map(&command_to_sidebar_item(&1, "/en/references/cli/commands/"))
      |> Enum.sort_by(& &1.label)

    [
      %Group{
        label: "CLI",
        items: [
          %Item{label: "Debugging", slug: "/en/references/cli/debugging"},
          %Item{label: "Directories", slug: "/en/references/cli/directories"},
          %Item{label: "Shell completions", slug: "/en/references/cli/shell-completions"},
          %Item{label: "Commands", items: commands}
        ]
      }
    ]
  end

  defp command_to_sidebar_item(command, parent_path) do
    name = command["commandName"]
    slug = "#{parent_path}#{name}"

    children =
      command
      |> Map.get("subcommands", [])
      |> Enum.filter(&(&1["shouldDisplay"] != false))
      |> Enum.map(&command_to_sidebar_item(&1, "#{slug}/"))

    %Item{label: name, slug: slug, items: children}
  end

  defp traverse_commands(command, parent_command) do
    if command["shouldDisplay"] == false do
      []
    else
      name = command["commandName"]
      full_command = "#{parent_command} #{name}"
      slug = command_slug(full_command)

      page = build_command_page(command, full_command, slug)

      child_pages =
        command
        |> Map.get("subcommands", [])
        |> Enum.flat_map(&traverse_commands(&1, full_command))

      [page | child_pages]
    end
  end

  defp command_slug(full_command) do
    path =
      full_command
      |> String.split()
      |> Enum.drop(1)
      |> Enum.join("/")

    "/en/references/cli/commands/#{path}"
  end

  defp build_command_page(command, full_command, slug) do
    arguments = process_arguments(command["arguments"] || [])

    subcommands =
      command
      |> Map.get("subcommands", [])
      |> Enum.filter(&(&1["shouldDisplay"] != false))

    markdown = render_markdown(full_command, command["abstract"], arguments, subcommands)

    html =
      [markdown: markdown]
      |> MDEx.new()
      |> MDEx.to_html!(
        extension: [header_ids: "", table: true],
        syntax_highlight: [formatter: {:html_inline, theme: "github_light"}]
      )
      |> HTML.wrap_code_blocks()
      |> HTML.add_heading_anchors()
      |> wrap_tables()

    headings = extract_headings_from_html(html)

    %Page{
      slug: slug,
      title: full_command,
      title_template: ":title · CLI · References · Tuist",
      description: command["abstract"],
      body: html,
      markdown: markdown,
      source_path: "references/cli/commands/#{slug}",
      headings: headings
    }
  end

  defp process_arguments(arguments) do
    arguments
    |> Enum.filter(&(&1["shouldDisplay"] != false and &1["abstract"] != nil and &1["abstract"] != ""))
    |> Enum.reject(&help_argument?/1)
    |> Enum.map(fn arg ->
      abstract = arg["abstract"] || ""
      env_match = Regex.run(@env_var_regex, abstract)

      clean_abstract =
        abstract
        |> String.replace(@env_var_regex, "")
        |> String.replace(@deprecated_regex, "")
        |> String.trim()
        |> String.replace(@angle_bracket_regex, "\\<\\1\\>")

      %{
        value_name: arg["valueName"],
        kind: arg["kind"],
        names: arg["names"] || [],
        is_optional: arg["isOptional"] || false,
        is_deprecated: String.contains?(abstract, "Deprecated") or String.contains?(abstract, "deprecated"),
        env_var: if(env_match, do: Enum.at(env_match, 1)),
        abstract: clean_abstract
      }
    end)
  end

  defp help_argument?(arg) do
    names = arg["names"] || []
    Enum.any?(names, fn n -> n["name"] == "help" end)
  end

  defp render_markdown(full_command, abstract, arguments, subcommands) do
    header = "# #{full_command}\n\n#{abstract || ""}\n"

    subcommands_section =
      if subcommands == [] do
        ""
      else
        rows =
          subcommands
          |> Enum.sort_by(& &1["commandName"])
          |> Enum.map_join("\n", fn sub ->
            name = sub["commandName"]
            desc = sub["abstract"] || ""
            "| `#{full_command} #{name}` | #{desc} |"
          end)

        "\n## Subcommands\n\n| Command | Description |\n| --- | --- |\n#{rows}\n"
      end

    args_section =
      if arguments == [] do
        ""
      else
        args =
          Enum.map_join(arguments, "\n", fn arg ->
            badges = render_badges(arg)
            env_line = if arg.env_var, do: "\n**Environment variable** `#{arg.env_var}`\n", else: ""
            usage = render_usage(full_command, arg)

            "### #{arg.value_name}#{badges}\n#{env_line}\n#{arg.abstract}\n\n#{usage}"
          end)

        "\n## Arguments\n\n#{args}"
      end

    header <> subcommands_section <> args_section
  end

  defp render_badges(arg) do
    optional = if arg.is_optional, do: " `Optional`", else: ""
    deprecated = if arg.is_deprecated, do: " `Deprecated`", else: ""
    optional <> deprecated
  end

  defp render_usage(full_command, %{kind: "positional", value_name: name}) do
    "```bash\n#{full_command} [#{name}]\n```\n"
  end

  defp render_usage(full_command, %{kind: "flag", names: names}) do
    lines =
      Enum.map_join(names, "\n", fn name ->
        prefix = if name["kind"] == "long", do: "--", else: "-"
        "#{full_command} #{prefix}#{name["name"]}"
      end)

    "```bash\n#{lines}\n```\n"
  end

  defp render_usage(full_command, %{kind: "option", names: names, value_name: value_name}) do
    lines =
      Enum.map_join(names, "\n", fn name ->
        prefix = if name["kind"] == "long", do: "--", else: "-"
        "#{full_command} #{prefix}#{name["name"]} [#{value_name}]"
      end)

    "```bash\n#{lines}\n```\n"
  end

  defp render_usage(_full_command, _arg), do: ""

  defp wrap_tables(html) do
    html
    |> String.replace("<table>", ~s(<div class="noora-table"><table>))
    |> String.replace("</table>", "</table></div>")
  end

  @heading_extract_from_html_regex ~r/<h([2-4])>.*?class="heading-anchor"\s+id="([^"]+)"[^>]*>.*?data-part="heading-text"[^>]*>(.*?)<\/span>/s

  defp extract_headings_from_html(html) do
    @heading_extract_from_html_regex
    |> Regex.scan(html)
    |> Enum.map(fn [_, level, id, text] ->
      plain_text = ~r/<[^>]+>/ |> Regex.replace(text, "") |> String.trim()
      %{level: String.to_integer(level), text: plain_text, id: id}
    end)
  end
end
