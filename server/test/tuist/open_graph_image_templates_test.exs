defmodule Tuist.OpenGraphImageTemplatesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
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

  test "includes public project metrics in the content key" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    stub(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    base = %{
      "template" => "project",
      "title" => "App",
      "project" => slug,
      "metric_one_label" => "Build duration",
      "metric_one_value" => "1m 12s",
      "chart" => "12,18,16,27",
      "chart_label" => "Recent build duration"
    }

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(base)

    assert {:ok, second_spec} =
             OpenGraphImageTemplates.spec(%{base | "metric_one_value" => "48s"})

    refute first_spec.key == second_spec.key
  end

  test "accepts chart values larger than one gigabyte" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    expect(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    assert {:ok, _spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "project",
               "title" => "Bundle",
               "project" => slug,
               "chart" => "2000000000,4000000000",
               "chart_label" => "Bundle size"
             })
  end

  test "includes the locale in the project image key" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    stub(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    params = %{"template" => "project", "title" => "Builds", "project" => slug, "locale" => "en"}
    assert {:ok, english} = OpenGraphImageTemplates.spec(params)
    assert {:ok, spanish} = OpenGraphImageTemplates.spec(%{params | "locale" => "es"})

    refute english.key == spanish.key
  end

  test "rejects malformed project image variables" do
    assert OpenGraphImageTemplates.spec(%{
             "template" => "project",
             "title" => "Builds",
             "project" => "tuist/tuist",
             "chart" => "12,not-a-number"
           }) == :error

    assert OpenGraphImageTemplates.spec(%{
             "template" => "project",
             "title" => "Builds",
             "project" => "tuist/tuist",
             "logo" => "another-storage-prefix/logo.png"
           }) == :error
  end

  test "rejects unknown template variables" do
    assert OpenGraphImageTemplates.spec(%{
             "template" => "marketing",
             "title" => "About Tuist",
             "source_path" => "/arbitrary"
           }) == :error
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
        chart: [12, 18, 24],
        chart_label: "Recent test duration",
        fonts_dir: Path.join(priv_dir, "static/fonts"),
        tuist_logo_path: Path.join(priv_dir, "docs/images/logo.webp")
      )

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "data:font/woff2;base64,"
    assert html =~ "&lt;script&gt;unsafe&lt;/script&gt;"
    refute html =~ "<script>unsafe</script>"
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
