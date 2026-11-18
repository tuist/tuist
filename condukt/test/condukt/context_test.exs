defmodule Condukt.ContextTest do
  use ExUnit.Case, async: true

  alias Condukt.Context

  @tag :tmp_dir
  test "discovers agents instructions and local skills from a project root", %{tmp_dir: project_root} do
    File.write!(Path.join(project_root, "AGENTS.md"), "Follow the project instructions.")
    File.write!(Path.join(project_root, "CLAUDE.md"), "Prefer concise responses.")

    skill_dir = Path.join(project_root, ".agents/skills/review")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: review
      description: Review a change for risks and regressions.
      ---

      Inspect the diff and call out the highest-risk issues first.
      """
    )

    context = Context.discover(project_root)

    assert context.agents_md =~ "Follow the project instructions."
    assert context.agents_md =~ "Prefer concise responses."

    assert context.skills == [
             %Context.Skill{
               name: "review",
               path: ".agents/skills/review/SKILL.md",
               description: "Review a change for risks and regressions."
             }
           ]

    assert context.prompt =~ "## Project Instructions"
    assert context.prompt =~ "## Available Skills"
    assert context.prompt =~ "read `.agents/skills/review/SKILL.md` before using it"
  end

  @tag :tmp_dir
  test "deduplicates AGENTS.md and a symlinked CLAUDE.md", %{tmp_dir: project_root} do
    File.write!(Path.join(project_root, "AGENTS.md"), "Follow the project instructions.")
    assert :ok = File.ln_s("AGENTS.md", Path.join(project_root, "CLAUDE.md"))

    context = Context.discover(project_root)

    assert context.agents_md == "Follow the project instructions."
  end

  test "composes base and discovered prompts" do
    composed =
      Context.compose_system_prompt(
        "You are a helpful assistant.",
        "## Project Instructions\n\nUse mix test."
      )

    assert composed ==
             "You are a helpful assistant.\n\n## Project Instructions\n\nUse mix test."
  end

  @tag :tmp_dir
  test "discovers via a sandbox handle rooted elsewhere than the host cwd", %{tmp_dir: project_root} do
    File.write!(Path.join(project_root, "AGENTS.md"), "Sandbox-routed instruction.")

    {:ok, sandbox} = Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: project_root)

    try do
      context = Context.discover(sandbox)
      assert context.agents_md == "Sandbox-routed instruction."
      assert context.prompt =~ "Sandbox-routed instruction."
    after
      Condukt.Sandbox.shutdown(sandbox)
    end
  end
end
