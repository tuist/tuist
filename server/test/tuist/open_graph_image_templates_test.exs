defmodule Tuist.OpenGraphImageTemplatesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Marketing.Blog.CoverArtwork, as: BlogCoverArtwork
  alias Tuist.OpenGraph.ProjectImage
  alias Tuist.OpenGraphImageTemplates
  alias Tuist.Projects
  alias Tuist.Projects.Project

  test "builds deterministic specs from template variables" do
    params = %{
      "template" => "docs",
      "title" => "Install Tuist",
      "description" => "Install the command-line interface.",
      "category" => "Guides"
    }

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(params)
    assert {:ok, second_spec} = OpenGraphImageTemplates.spec(params)
    assert first_spec.key == second_spec.key
    assert first_spec.params == params
  end

  test "changes the content key when a template variable changes" do
    assert {:ok, first_spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "marketing",
               "title" => "About Tuist"
             })

    assert {:ok, second_spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "marketing",
               "title" => "Pricing"
             })

    refute first_spec.key == second_spec.key
  end

  test "includes public project variables in the content key" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    stub(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    base = %{
      "template" => "project",
      "title" => "App",
      "project" => slug,
      "project_id" => to_string(project.id),
      "subtitle" => "main · Release",
      "badge" => "Success"
    }

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(base)

    assert {:ok, second_spec} =
             OpenGraphImageTemplates.spec(%{base | "badge" => "Failed"})

    refute first_spec.key == second_spec.key
  end

  test "includes the locale in the project image key" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    stub(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    params = %{
      "template" => "project",
      "title" => "Builds",
      "project" => slug,
      "project_id" => to_string(project.id),
      "locale" => "en"
    }

    assert {:ok, english} = OpenGraphImageTemplates.spec(params)
    assert {:ok, spanish} = OpenGraphImageTemplates.spec(%{params | "locale" => "es"})

    refute english.key == spanish.key
  end

  test "rejects cards for a different project reusing the same handle" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    stub(Projects, :get_project_by_slug, fn ^slug -> {:ok, %{project | id: 43}} end)

    assert OpenGraphImageTemplates.spec(%{
             "template" => "project",
             "title" => "Builds",
             "project" => slug,
             "project_id" => to_string(project.id)
           }) == :error
  end

  test "rejects malformed project image variables" do
    assert OpenGraphImageTemplates.spec(%{
             "template" => "project",
             "title" => "Builds",
             "project" => "tuist/tuist",
             "logo" => "another-storage-prefix/logo.png"
           }) == :error

    assert OpenGraphImageTemplates.spec(%{
             "template" => "project",
             "title" => "Builds",
             "project" => "tuist/tuist",
             "chart" => "12,24"
           }) == :error
  end

  test "rejects unknown template variables" do
    assert OpenGraphImageTemplates.spec(%{
             "template" => "marketing",
             "title" => "About Tuist",
             "source_path" => "/arbitrary"
           }) == :error
  end

  test "builds deterministic case study specs from the cover artwork" do
    params = %{"template" => "marketing_case_study", "slug" => "monzo"}

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(params)
    assert {:ok, second_spec} = OpenGraphImageTemplates.spec(params)
    assert first_spec.key == second_spec.key

    assert {:ok, other_spec} =
             OpenGraphImageTemplates.spec(%{"template" => "marketing_case_study", "slug" => "trendyol"})

    refute first_spec.key == other_spec.key
  end

  test "rejects case studies without cover artwork and unsafe slugs" do
    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_case_study", "slug" => "unknown-company"}) ==
             :error

    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_case_study", "slug" => "../secrets"}) ==
             :error
  end

  test "rejects blog covers without artwork and unsafe slugs" do
    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "no-such-post"}) ==
             :error

    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "../secrets"}) ==
             :error
  end

  test "keys blog cover images by the artwork" do
    stub(BlogCoverArtwork, :available?, fn slug -> slug in ["one", "two"] end)
    stub(BlogCoverArtwork, :svg, fn slug, :og -> ~s(<svg data-part="artwork">#{slug}</svg>) end)

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "one"})
    assert {:ok, again_spec} = OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "one"})
    assert {:ok, other_spec} = OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "two"})

    assert first_spec.key == again_spec.key
    refute first_spec.key == other_spec.key
  end

  test "renders text-only images as JPEG data" do
    assert {:ok, spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "marketing_text",
               "title" => "A runtime-generated image"
             })

    assert {:ok, <<0xFF, 0xD8, _rest::binary>>} = spec.render.()
  end

  test "renders a self-contained project card and escapes project data" do
    priv_dir = Application.app_dir(:tuist, "priv")

    html =
      ProjectImage.render_html(
        title: "<script>unsafe</script>",
        project: "tuist/tuist",
        subtitle: "main branch",
        badge: "Success",
        fonts_dir: Path.join(priv_dir, "static/fonts")
      )

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "data:font/woff2;base64,"
    assert html =~ "&lt;script&gt;unsafe&lt;/script&gt;"
    refute html =~ "<script>unsafe</script>"
    assert html =~ ~s(data-status="success")
  end

  test "renders status badges only for status-like badges" do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")

    for {badge, status} <- [
          {"Failed_processing", "error"},
          {"Flaky", "warning"},
          {"Skipped", "disabled"},
          {"Processing", "in_progress"}
        ] do
      html = ProjectImage.render_html(title: "Build", project: "tuist/tuist", badge: badge, fonts_dir: fonts_dir)
      assert html =~ ~s(data-status="#{status}")
    end

    html =
      ProjectImage.render_html(title: "Build", project: "tuist/tuist", badge: "Failed_processing", fonts_dir: fonts_dir)

    assert html =~ "Failed processing"

    html = ProjectImage.render_html(title: "Bundle", project: "tuist/tuist", badge: "IPA", fonts_dir: fonts_dir)
    refute html =~ ~r/<div class="badge" data-status=/
    assert html =~ "IPA"
  end

  defp public_project do
    %Project{
      id: 42,
      name: "tuist",
      visibility: :public,
      account: %Account{name: "tuist"}
    }
  end
end
