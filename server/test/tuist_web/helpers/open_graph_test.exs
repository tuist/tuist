defmodule TuistWeb.Helpers.OpenGraphTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Phoenix.Token
  alias Tuist.Accounts.Account
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias TuistWeb.Helpers.OpenGraph

  test "builds a deterministic path with compact signed template variables" do
    first_path =
      OpenGraph.image_path(:marketing,
        title: "About Tuist"
      )

    second_path =
      OpenGraph.image_path(:marketing,
        title: "About Tuist"
      )

    assert first_path == second_path

    uri = URI.parse(first_path)
    %{"token" => token} = URI.decode_query(uri.query)

    assert uri.path =~ ~r|\A/open-graph-images/[0-9a-f]{64}\.jpg\z|

    assert OpenGraph.verify_image_token(token) ==
             {:ok,
              %{
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

  test "keeps marketing tokens stable and non-expiring" do
    params = %{"template" => "marketing", "title" => "About Tuist"}
    token = Token.sign(TuistWeb.Endpoint, "open_graph_image", Enum.sort(params), signed_at: 0)
    path = OpenGraph.image_path(:marketing, title: "About Tuist")
    assert URI.decode_query(URI.parse(path).query) == %{"token" => token}
    assert OpenGraph.verify_image_token(token) == {:ok, params}
  end

  test "keeps existing docs text limits without crashing the page" do
    path =
      OpenGraph.image_path(:docs,
        title: String.duplicate("t", 500),
        description: String.duplicate("d", 1_000),
        category: String.duplicate("c", 500)
      )

    %{"token" => token} = URI.decode_query(URI.parse(path).query)
    assert {:ok, params} = OpenGraph.verify_image_token(token)
    assert String.length(params["description"]) == 1_000
  end

  test "expires project tokens but accepts images referenced by year-old HTML" do
    params = %{"template" => "project", "title" => "Builds", "project" => "tuist/tuist"}
    now = System.system_time(:second)

    valid = Token.sign(TuistWeb.Endpoint, "open_graph_image", Enum.sort(params), signed_at: now - 372 * 86_400)
    expired = Token.sign(TuistWeb.Endpoint, "open_graph_image", Enum.sort(params), signed_at: now - 401 * 86_400)

    assert OpenGraph.verify_image_token(valid) == {:ok, params}
    assert OpenGraph.verify_image_token(expired) == :error
  end

  test "does not accept legacy non-expiring signatures for project cards" do
    params = %{"template" => "project", "title" => "Builds", "project" => "tuist/tuist"}
    signature = Token.sign(TuistWeb.Endpoint, "open_graph_image", Enum.sort(params), signed_at: 0)

    assert OpenGraph.verify_image_params(params, signature) == :error
  end

  test "falls back when multibyte project text exceeds the request-line budget" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    stub(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    assigns =
      OpenGraph.project_image_assigns(project,
        title: String.duplicate("😀", 160),
        subtitle: String.duplicate("😀", 200),
        badge: String.duplicate("😀", 60)
      )

    assert assigns[:head_image] == Tuist.Environment.app_url(path: "/images/open-graph/dashboard/overview.png")
  end

  test "builds a dynamic image for a public project" do
    project = public_project()
    slug = "#{project.account.name}/#{project.name}"
    expect(Projects, :get_project_by_slug, fn ^slug -> {:ok, project} end)

    assigns =
      OpenGraph.project_image_assigns(project,
        title: "Builds",
        subtitle: "main · Release",
        badge: "Success"
      )

    uri = URI.parse(assigns[:head_image])
    %{"token" => token} = URI.decode_query(uri.query)
    assert {:ok, params} = OpenGraph.verify_image_token(token)

    assert uri.path =~ ~r|\A/open-graph-images/[0-9a-f]{64}\.jpg\z|
    assert params["template"] == "project"
    assert params["project"] == "#{project.account.name}/#{project.name}"
    refute Map.has_key?(params, "logo")
    assert params["title"] == "Builds"
    assert params["subtitle"] == "main · Release"
    assert params["badge"] == "Success"
    assert params["locale"] == "en"
    assert assigns[:head_twitter_card] == "summary_large_image"
    assert byte_size(uri.path <> "?" <> uri.query) <= 2_000
  end

  test "keeps private project data out of the image URL" do
    project = %{public_project() | name: "secret-project", visibility: :private}

    assigns = OpenGraph.project_image_assigns(project, title: "Secret build", fallback: "builds")

    assert assigns[:head_image] == Tuist.Environment.app_url(path: "/images/open-graph/dashboard/builds.png")
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
        badge: ""
      )

    uri = URI.parse(assigns[:head_image])
    %{"token" => token} = URI.decode_query(uri.query)
    assert {:ok, params} = OpenGraph.verify_image_token(token)
    refute Map.has_key?(params, "subtitle")
    refute Map.has_key?(params, "badge")
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
