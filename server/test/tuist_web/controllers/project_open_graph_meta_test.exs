defmodule TuistWeb.ProjectOpenGraphMetaTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "all public dashboard pages include dynamic OG image URLs without authentication", %{conn: conn} do
    {account, project} = public_project_fixture()
    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
    test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
    [test_case_run | _] = test_run.test_case_runs
    {:ok, build_run} = RunsFixtures.build_fixture(project_id: project.id, user_id: account.id)
    bundle = BundlesFixtures.bundle_fixture(project: project)
    preview = AppBuildsFixtures.preview_fixture(project: project, supported_platforms: [:ios], visibility: :public)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    qa_run = QAFixtures.qa_run_fixture(app_build: app_build)
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "build")

    paths = [
      ~p"/#{account.name}/#{project.name}",
      ~p"/#{account.name}/#{project.name}/analytics",
      ~p"/#{account.name}/#{project.name}/tests",
      ~p"/#{account.name}/#{project.name}/tests/test-runs",
      ~p"/#{account.name}/#{project.name}/tests/test-runs/#{test_run.id}",
      ~p"/#{account.name}/#{project.name}/tests/test-cases",
      ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}",
      ~p"/#{account.name}/#{project.name}/tests/flaky-tests",
      ~p"/#{account.name}/#{project.name}/tests/quarantined-tests",
      ~p"/#{account.name}/#{project.name}/module-cache",
      ~p"/#{account.name}/#{project.name}/module-cache/cache-runs",
      ~p"/#{account.name}/#{project.name}/module-cache/generate-runs",
      ~p"/#{account.name}/#{project.name}/xcode-cache",
      ~p"/#{account.name}/#{project.name}/gradle-cache",
      ~p"/#{account.name}/#{project.name}/connect",
      ~p"/#{account.name}/#{project.name}/bundles",
      ~p"/#{account.name}/#{project.name}/bundles/#{bundle.id}",
      ~p"/#{account.name}/#{project.name}/builds",
      ~p"/#{account.name}/#{project.name}/builds/build-runs",
      ~p"/#{account.name}/#{project.name}/builds/build-runs/#{build_run.id}",
      ~p"/#{account.name}/#{project.name}/previews",
      ~p"/#{account.name}/#{project.name}/previews/#{preview.id}",
      ~p"/#{account.name}/#{project.name}/qa",
      ~p"/#{account.name}/#{project.name}/qa/#{qa_run.id}",
      ~p"/#{account.name}/#{project.name}/qa/#{qa_run.id}/logs",
      ~p"/#{account.name}/#{project.name}/runs/#{command_event.id}"
    ]

    Enum.each(paths, fn path ->
      html =
        conn
        |> recycle()
        |> get(path)
        |> html_response(200)

      assert_dynamic_og_meta_tags(html, account, project, path)
    end)
  end

  test "authenticated settings pages include semantic OG image URLs", %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    account = user.account
    project = ProjectsFixtures.project_fixture(account: account, visibility: :public, preload: [:account])

    paths = [
      ~p"/#{account.name}/#{project.name}/settings",
      ~p"/#{account.name}/#{project.name}/settings/automations",
      ~p"/#{account.name}/#{project.name}/settings/notifications",
      ~p"/#{account.name}/#{project.name}/settings/qa"
    ]

    Enum.each(paths, fn path ->
      html =
        conn
        |> recycle()
        |> log_in_user(user)
        |> get(path)
        |> html_response(200)

      assert_dynamic_og_meta_tags(html, account, project, path)
    end)
  end

  test "public run detail pages include command key values in OG image URL", %{conn: conn} do
    {account, project} = public_project_fixture()

    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "build",
        duration: 4_200
      )

    html =
      conn
      |> get(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
      |> html_response(200)

    og_image = meta_content(html, "property", "og:image")
    assert_dynamic_og_meta_tags(html, account, project, ~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")

    query = og_image |> URI.parse() |> Map.get(:query) |> URI.decode_query()
    assert query["k1"] == "Command"
    assert query["v1"] == "build"
    assert query["k2"] == "Duration"
    assert is_binary(query["v2"]) and query["v2"] != ""
    assert query["k3"] == "Status"
    assert query["v3"] == "Success"
  end

  test "public bundle detail pages include bundle key values in OG image URL", %{conn: conn} do
    {account, project} = public_project_fixture()
    bundle = BundlesFixtures.bundle_fixture(project: project, install_size: 12_300, git_branch: "main")

    html =
      conn
      |> get(~p"/#{account.name}/#{project.name}/bundles/#{bundle.id}")
      |> html_response(200)

    og_image = meta_content(html, "property", "og:image")
    query = og_image |> URI.parse() |> Map.get(:query) |> URI.decode_query()

    assert query["k1"] == "Bundle Size"
    assert query["v1"] == "12.3 KB"
    assert query["k2"] == "Type"
    assert query["v2"] == "App bundle"
    assert query["k3"] == "Branch"
    assert query["v3"] == "main"
  end

  test "public previews pages include preview key values in OG image URL", %{conn: conn} do
    {account, project} = public_project_fixture()

    preview =
      AppBuildsFixtures.preview_fixture(
        project: project,
        visibility: :public,
        display_name: "MyApp",
        track: "beta",
        git_branch: "feature/caching",
        version: "1.2.3",
        supported_platforms: [:ios]
      )

    _app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

    previews_html =
      conn
      |> get(~p"/#{account.name}/#{project.name}/previews")
      |> html_response(200)

    previews_query = previews_html |> meta_content("property", "og:image") |> og_query_params()

    assert previews_query["k1"] == "Latest Preview"
    assert previews_query["v1"] == "MyApp"
    assert previews_query["k2"] == "Track"
    assert previews_query["v2"] == "Beta"
    assert previews_query["k3"] == "Branch"
    assert previews_query["v3"] == "feature/caching"

    preview_html =
      conn
      |> recycle()
      |> get(~p"/#{account.name}/#{project.name}/previews/#{preview.id}")
      |> html_response(200)

    preview_query = preview_html |> meta_content("property", "og:image") |> og_query_params()

    assert preview_query["k1"] == "Version"
    assert preview_query["v1"] == "1.2.3"
    assert preview_query["k2"] == "Track"
    assert preview_query["v2"] == "Beta"
    assert preview_query["k3"] == "Branch"
    assert preview_query["v3"] == "feature/caching"
  end

  test "public qa pages include QA key values in OG image URL", %{conn: conn} do
    {account, project} = public_project_fixture()

    preview =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "MyApp",
        git_branch: "feature/caching",
        supported_platforms: [:ios]
      )

    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    qa_run = QAFixtures.qa_run_fixture(app_build: app_build, status: "completed")
    _step = QAFixtures.qa_step_fixture(qa_run: qa_run, issues: ["Login button missing", "Text overlaps"])

    qa_html =
      conn
      |> get(~p"/#{account.name}/#{project.name}/qa")
      |> html_response(200)

    qa_query = qa_html |> meta_content("property", "og:image") |> og_query_params()

    assert qa_query["k1"] == "Run Status"
    assert qa_query["v1"] == "Completed"
    assert qa_query["k2"] == "Latest App"
    assert qa_query["v2"] == "MyApp"
    assert qa_query["k3"] == "Apps Tracked"
    assert qa_query["v3"] == "1"

    qa_run_html =
      conn
      |> recycle()
      |> get(~p"/#{account.name}/#{project.name}/qa/#{qa_run.id}")
      |> html_response(200)

    qa_run_query = qa_run_html |> meta_content("property", "og:image") |> og_query_params()

    assert qa_run_query["k1"] == "App"
    assert qa_run_query["v1"] == "MyApp"
    assert qa_run_query["k2"] == "Status"
    assert qa_run_query["v2"] == "Completed"
    assert qa_run_query["k3"] == "Issues"
    assert qa_run_query["v3"] == "2"
  end

  defp public_project_fixture do
    account = AccountsFixtures.account_fixture()

    project =
      ProjectsFixtures.project_fixture(
        account: account,
        visibility: :public,
        preload: [:account]
      )

    {account, project}
  end

  defp assert_dynamic_og_meta_tags(html, account, project, path) do
    og_image = meta_content(html, "property", "og:image")
    twitter_image = meta_content(html, "name", "twitter:image")
    twitter_card = meta_content(html, "name", "twitter:card")

    assert is_binary(og_image) and og_image != "",
           "missing og:image content for path #{path}"

    assert og_image =~ "/#{account.name}/#{project.name}/og/",
           "expected dynamic og:image for path #{path}, got #{inspect(og_image)}"

    assert twitter_image == og_image,
           "expected twitter:image to match og:image for path #{path}"

    assert twitter_card == "summary_large_image",
           "expected twitter:card summary_large_image for path #{path}"

    query =
      og_image
      |> URI.parse()
      |> Map.get(:query, "")
      |> URI.decode_query()

    assert is_binary(query["title"]) and query["title"] != "",
           "expected OG image query title for path #{path}"

    assert is_binary(query["k2"]) and query["k2"] != "",
           "expected semantic key in k2 for path #{path}"

    assert is_binary(query["v2"]) and query["v2"] != "",
           "expected semantic value in v2 for path #{path}"

    assert is_binary(query["k3"]) and query["k3"] != "",
           "expected semantic key in k3 for path #{path}"

    assert is_binary(query["v3"]) and query["v3"] != "",
           "expected semantic value in v3 for path #{path}"

    refute query["k2"] == "Build System",
           "expected page-specific metadata in k2 for path #{path}"

    refute query["k3"] == "Access",
           "expected page-specific metadata in k3 for path #{path}"
  end

  defp meta_content(html, attr_name, attr_value) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(meta[#{attr_name}="#{attr_value}"]))
    |> Floki.attribute("content")
    |> List.first()
  end

  defp og_query_params(og_image) do
    og_image
    |> URI.parse()
    |> Map.get(:query)
    |> URI.decode_query()
  end
end
