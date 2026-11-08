defmodule Condukt.Context do
  @moduledoc """
  Loads project instructions and local skills from the active sandbox.

  Condukt automatically looks for local instruction files such as `AGENTS.md`
  and reusable skills under `.agents/skills/*/SKILL.md`. The discovered
  instructions are appended to the configured system prompt so agents can adapt
  to the project they are running in.

  Discovery routes through `Condukt.Sandbox`, so the files are read from
  wherever the active sandbox lives: the host filesystem for `Sandbox.Local`,
  the virtual filesystem for `Sandbox.Virtual`, a mounted guest workspace for
  `Sandbox.Microsandbox`, or inside the pod for `Sandbox.Kubernetes`.
  """

  alias Condukt.Context.Skill
  alias Condukt.Sandbox

  @context_files ["AGENTS.md", "CLAUDE.md"]
  @skills_dir ".agents/skills"

  def empty do
    %{agents_md: nil, skills: [], prompt: nil}
  end

  @doc """
  Loads project instructions and skills.

  Accepts a `Condukt.Sandbox` handle (the canonical form, used by
  `Condukt.Session`) or a host filesystem path (convenience form for tests
  and scripts: builds a transient `Sandbox.Local` rooted there and delegates).
  """
  def discover(sandbox_or_root)

  def discover(%Sandbox{} = sandbox) do
    project_root = Sandbox.cwd(sandbox)
    agents_md = read_agents_md(sandbox, project_root)
    skills = discover_skills(sandbox, project_root)

    %{
      agents_md: agents_md,
      skills: skills,
      prompt: compose_prompt(agents_md, skills)
    }
  end

  def discover(project_root) when is_binary(project_root) do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: project_root)

    try do
      discover(sandbox)
    after
      Sandbox.shutdown(sandbox)
    end
  end

  def compose_system_prompt(base_prompt, nil), do: present(base_prompt)

  def compose_system_prompt(base_prompt, project_instructions_prompt) do
    [present(base_prompt), present(project_instructions_prompt)]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "\n\n")
    end
  end

  defp read_agents_md(sandbox, project_root) do
    @context_files
    |> Enum.map(&Path.join(project_root, &1))
    |> Enum.map(&sandbox_read(sandbox, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "\n\n")
    end
  end

  defp sandbox_read(sandbox, path) do
    case Sandbox.read(sandbox, path) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp discover_skills(sandbox, project_root) do
    pattern = Path.join(@skills_dir, "*/SKILL.md")

    case Sandbox.glob(sandbox, pattern, cwd: project_root) do
      {:ok, paths} ->
        paths
        |> Enum.sort()
        |> Enum.map(&load_skill(sandbox, project_root, &1))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp load_skill(sandbox, project_root, relative_path) do
    skill_dir_name =
      relative_path
      |> Path.split()
      |> Enum.at(-2)

    absolute_path = Path.join(project_root, relative_path)

    case Sandbox.read(sandbox, absolute_path) do
      {:ok, content} ->
        {name, description} = parse_frontmatter(content, skill_dir_name)

        %Skill{
          name: name,
          description: description,
          path: relative_path
        }

      {:error, _} ->
        nil
    end
  end

  defp parse_frontmatter(content, default_name) do
    regex = ~r/\A---\s*\n(?<frontmatter>[\s\S]*?)\n---\s*\n(?<body>[\s\S]*)\z/

    case Regex.named_captures(regex, content) do
      %{"frontmatter" => frontmatter} ->
        fields = parse_frontmatter_fields(frontmatter)

        {Map.get(fields, "name", default_name), Map.get(fields, "description")}

      _ ->
        {default_name, nil}
    end
  end

  defp parse_frontmatter_fields(frontmatter) do
    frontmatter
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, &put_frontmatter_field/2)
  end

  defp put_frontmatter_field(line, acc) do
    case String.split(line, ":", parts: 2) do
      [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
      _ -> acc
    end
  end

  defp compose_prompt(nil, []), do: nil

  defp compose_prompt(agents_md, skills) do
    [agents_prompt(agents_md), skills_prompt(skills)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp agents_prompt(nil), do: nil

  defp agents_prompt(agents_md) do
    """
    ## Project Instructions

    The following instructions were discovered from `AGENTS.md` or `CLAUDE.md`
    in the project root. Treat them as project-specific operating instructions
    for this project.

    #{agents_md}
    """
    |> String.trim()
  end

  defp skills_prompt([]), do: nil

  defp skills_prompt(skills) do
    skill_lines =
      Enum.map_join(skills, "\n", fn skill ->
        description =
          case present(skill.description) do
            nil -> ""
            text -> " - #{text}"
          end

        "- `#{skill.name}` (read `#{skill.path}` before using it)#{description}"
      end)

    """
    ## Available Skills

    The following reusable skills were discovered in this project. If one
    seems relevant, read its `SKILL.md` file before following it so you have
    the full instructions.

    #{skill_lines}
    """
    |> String.trim()
  end

  defp present(nil), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
