defmodule TuistWeb.Helpers.OpenGraphTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias TuistWeb.Helpers.OpenGraph

  test "builds a deterministic path with compact signed template variables" do
    first_path =
      OpenGraph.image_path(:marketing,
        title: "About Tuist",
        icon: "static/marketing/images/about/logo.webp"
      )

    second_path =
      OpenGraph.image_path(:marketing,
        icon: "static/marketing/images/about/logo.webp",
        title: "About Tuist"
      )

    assert first_path == second_path

    uri = URI.parse(first_path)
    %{"token" => token} = URI.decode_query(uri.query)

    assert uri.path =~ ~r|\A/open-graph-images/[0-9a-f]{64}\.jpg\z|

    assert OpenGraph.verify_image_token(token) ==
             {:ok,
              %{
                "icon" => "static/marketing/images/about/logo.webp",
                "template" => "marketing",
                "title" => "About Tuist"
              }}
  end

  test "rejects a modified image token" do
    path = OpenGraph.image_path(:marketing, title: "About Tuist")
    %{"token" => token} = path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert OpenGraph.verify_image_token(token <> "tampered") == :error
  end

  test "rejects a non-binary signature" do
    assert OpenGraph.verify_image_token(["invalid"]) == :error
  end

  test "keeps the largest accepted image request below common request-line limits" do
    path =
      OpenGraph.image_path(:docs,
        title: String.duplicate("t", 240),
        description: String.duplicate("d", 500),
        category: String.duplicate("c", 240)
      )

    assert byte_size(path) <= 2_000
  end

  test "builds a dynamic image for a public project" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    expect(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    assigns =
      OpenGraph.project_image_assigns(project,
        title: "Builds",
        metric_one_label: "Build duration",
        metric_one_value: "42s",
        chart: [12, 18, 24],
        chart_label: "Recent build duration"
      )

    uri = URI.parse(assigns[:head_image])
    %{"token" => token} = URI.decode_query(uri.query)
    assert {:ok, params} = OpenGraph.verify_image_token(token)

    assert uri.path =~ ~r|\A/open-graph-images/[0-9a-f]{64}\.jpg\z|
    assert params["template"] == "project"
    assert params["project"] == "#{project.account.name}/#{project.name}"
    refute Map.has_key?(params, "logo")
    assert params["chart"] == "12,18,24"
    assert params["chart_label"] == "Recent build duration"
    assert params["locale"] == "en"
    assert assigns[:head_twitter_card] == "summary_large_image"
    assert byte_size(uri.path <> "?" <> uri.query) <= 2_000
  end

  test "keeps private project data out of the image URL" do
    project = %{public_project() | name: "secret-project", visibility: :private}

    assigns = OpenGraph.project_image_assigns(project, title: "Secret build", fallback: "builds")

    assert assigns[:head_image] == Tuist.Environment.app_url(path: "/images/open-graph/dashboard/builds.jpg")
    refute assigns[:head_image] =~ "secret"
  end

  test "omits blank optional values instead of crashing the page mount" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    expect(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    assigns =
      OpenGraph.project_image_assigns(project,
        title: "Build Run",
        subtitle: "",
        metric_two_label: "Branch",
        metric_two_value: ""
      )

    uri = URI.parse(assigns[:head_image])
    %{"token" => token} = URI.decode_query(uri.query)
    assert {:ok, params} = OpenGraph.verify_image_token(token)
    refute Map.has_key?(params, "subtitle")
    refute Map.has_key?(params, "metric_two_value")
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
