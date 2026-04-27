defmodule TuistWeb.AgentSkillsDiscoveryTest do
  use ExUnit.Case, async: true

  alias TuistWeb.AgentSkillsDiscovery

  @schema_uri "https://schemas.agentskills.io/discovery/0.2.0/schema.json"
  @skills_url_base "/skills"

  test "builds the published skills discovery index" do
    assert AgentSkillsDiscovery.index() == %{
             "$schema" => @schema_uri,
             "skills" => expected_skills()
           }
  end

  defp expected_skills do
    skills_root()
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(&expected_skill/1)
  end

  defp expected_skill(skill_name) do
    skill_path = Path.join([skills_root(), skill_name, "SKILL.md"])
    contents = File.read!(skill_path)
    attributes = skill_attributes(contents)

    %{
      "name" => attributes["name"],
      "type" => "skill-md",
      "description" => attributes["description"],
      "url" => Path.join([@skills_url_base, skill_name, "SKILL.md"]),
      "digest" => "sha256:" <> digest(contents)
    }
  end

  defp skill_attributes(contents) do
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
end
