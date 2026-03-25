defmodule Tuist.Docs.CLI.Renderer do
  @moduledoc """
  Renders CLI spec JSON into documentation pages and sidebar items.
  """

  alias Tuist.Docs.Page
  alias Tuist.Docs.Sidebar.{Group, Item}

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
      |> Enum.map(&command_to_sidebar_item(&1, "/en/cli/"))
      |> Enum.sort_by(& &1.label)

    [
      %Group{
        label: "CLI",
        items: [
          %Item{label: "Debugging", slug: "/en/cli/debugging"},
          %Item{label: "Directories", slug: "/en/cli/directories"},
          %Item{label: "Shell completions", slug: "/en/cli/shell-completions"}
        ]
      },
      %Group{
        label: "Commands",
        items: commands
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

    "/en/cli/#{path}"
  end

  defp build_command_page(command, full_command, slug) do
    arguments = process_arguments(command["arguments"] || [])
    markdown = render_markdown(full_command, command["abstract"], arguments)

    html =
      [markdown: markdown]
      |> MDEx.new()
      |> MDEx.to_html!(
        extension: [header_ids: "", table: true],
        syntax_highlight: [formatter: {:html_inline, theme: "github_light"}]
      )
      |> wrap_code_blocks()

    headings = extract_headings(arguments)

    %Page{
      slug: slug,
      title: full_command,
      title_template: ":title · CLI · Tuist",
      description: command["abstract"],
      body: html,
      markdown: markdown,
      source_path: "cli/#{slug}",
      headings: headings
    }
  end

  defp process_arguments(arguments) do
    arguments
    |> Enum.filter(&(&1["shouldDisplay"] != false))
    |> Enum.filter(&(&1["abstract"] != nil and &1["abstract"] != ""))
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

  defp render_markdown(full_command, abstract, arguments) do
    header = "# #{full_command}\n\n#{abstract || ""}\n"

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

    header <> args_section
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

  defp extract_headings(arguments) do
    base = if arguments != [], do: [%{level: 2, text: "Arguments", id: "arguments"}], else: []

    arg_headings =
      Enum.map(arguments, fn arg ->
        id =
          arg.value_name
          |> String.downcase()
          |> String.replace(~r/[^\w\s-]/u, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        %{level: 3, text: arg.value_name, id: id}
      end)

    base ++ arg_headings
  end

  @noora_icons_path Path.expand("../noora/lib/noora/icons", File.cwd!())
  @copy_icon @noora_icons_path |> Path.join("copy.svg") |> File.read!() |> String.trim()
  @copy_check_icon @noora_icons_path |> Path.join("copy-check.svg") |> File.read!() |> String.trim()

  @code_block_regex ~r/<pre[^>]*><code(?:[^>]*class="language-(\w+)")?[^>]*>(.*?)<\/code><\/pre>/s

  @code_block_template """
  <div class="code-window">\
  <div data-part="bar">\
  <div data-part="language"><%= language %></div>\
  <div data-part="copy"><span data-part="copy-icon"><%= copy_icon %></span><span data-part="copy-check-icon"><%= copy_check_icon %></span></div>\
  </div>\
  <div data-part="code"><code><%= code %></code>\
  </div>\
  </div>\
  """

  defp wrap_code_blocks(html) do
    Regex.replace(@code_block_regex, html, fn _, language, code ->
      language = if language == "", do: "", else: language

      EEx.eval_string(@code_block_template,
        language: language,
        code: code,
        copy_icon: @copy_icon,
        copy_check_icon: @copy_check_icon
      )
    end)
  end
end
