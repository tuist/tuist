defmodule TuistWeb.AgentSkillsDiscovery do
  @moduledoc false

  @schema_uri "https://schemas.agentskills.io/discovery/0.2.0/schema.json"
  @skills_url_base "/skills"

  def index do
    %{
      "$schema" => @schema_uri,
      "skills" => skills()
    }
  end

  def skills do
    skills_root()
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(&skill/1)
  end

  defp skill(skill_name) do
    skill_path = skill_path(skill_name)
    contents = File.read!(skill_path)
    frontmatter = skill_frontmatter(contents)

    %{
      "name" => frontmatter["name"],
      "type" => "skill-md",
      "description" => frontmatter["description"],
      "url" => Path.join([@skills_url_base, skill_name, "SKILL.md"]),
      "digest" => "sha256:" <> digest(contents)
    }
  end

  defp skill_frontmatter(contents) do
    [frontmatter, _body] =
      contents
      |> String.replace(~r/^---\n/, "")
      |> String.split(["\n---\n"], parts: 2)

    YamlElixir.read_from_string!(frontmatter)
  end

  defp digest(contents) do
    :sha256
    |> :crypto.hash(contents)
    |> Base.encode16(case: :lower)
  end

  defp skills_root do
    Application.app_dir(:tuist, ["priv", "static", "skills"])
  end

  defp skill_path(skill_name) do
    Path.join([skills_root(), skill_name, "SKILL.md"])
  end
end
