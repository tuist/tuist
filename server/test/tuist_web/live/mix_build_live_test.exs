defmodule TuistWeb.MixBuildLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Mix
  alias Tuist.Mix.Build.Buffer
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "mixbuild#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(name: "mix-build-org", creator: user, preload: [:account])

    project = ProjectsFixtures.project_fixture(name: "phoenix-app", account_id: account.id, build_system: :mix)

    conn =
      conn
      |> assign(:selected_project, project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    build_id = UUIDv7.generate()

    {:ok, ^build_id} =
      Mix.create_build(%{
        id: build_id,
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 2_000,
        status: "success",
        elixir_version: "1.19.1",
        otp_version: "28",
        mix_env: "dev",
        diagnostics: [
          %{severity: "warning", file: "lib/greeter.ex", module: "Demo.Greeter", message: "unused variable", line: 4},
          %{severity: "warning", file: "lib/greeter.ex", module: "Demo.Greeter", message: "unused alias <b>", line: 9}
        ],
        files: [
          %{
            path: "lib/macros.ex",
            start_offset_ms: 10,
            compile_duration_ms: 1_500,
            wait_duration_ms: 0,
            modules: ["Demo.Macros"],
            waits: []
          },
          %{
            path: "lib/greeter.ex",
            start_offset_ms: 20,
            compile_duration_ms: 70,
            wait_duration_ms: 333,
            modules: ["Demo.Greeter"],
            dependencies: [%{path: "lib/macros.ex", kind: "compile"}],
            waits: [
              %{module: "Demo.Macros", path: "lib/macros.ex", kind: "module", duration_ms: 333, start_offset_ms: 30}
            ]
          }
        ],
        steps: [
          %{
            category: "type_check",
            title: "Type checking Demo.Greeter",
            path: "lib/greeter.ex",
            start_offset_ms: 1_600,
            duration_ms: 25
          }
        ]
      })

    for buffer <- [Buffer, Mix.Diagnostic.Buffer, Mix.CompiledFile.Buffer, Mix.Step.Buffer], do: buffer.flush()

    %{
      conn: conn,
      user: user,
      project: project,
      path: ~p"/#{organization.account.name}/#{project.name}/builds/mix-builds/#{build_id}",
      timeline_path: ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}/timeline.json"
    }
  end

  test "has a Timeline tab backed by the shared build timeline", %{conn: conn, path: path, timeline_path: timeline_path} do
    {:ok, lv, _html} = live(conn, path <> "?tab=timeline")
    render_async(lv)

    assert has_element?(lv, "#build-timeline[data-source=mix]")
    assert has_element?(lv, "#build-timeline[data-url='#{timeline_path}']")
    assert has_element?(lv, "[data-part=legend] button[data-kind=setup]", "Type checking")
    assert has_element?(lv, "[data-part=legend] button[data-kind=resource]", "Writing to disk")
    assert has_element?(lv, "[data-part=legend] button[data-kind=script]", "Other compilers")
    refute has_element?(lv, "[data-part=legend] button[data-kind=link]")
    refute has_element?(lv, "[data-part=build-details]")

    tabs =
      lv
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("a.noora-tab-menu-horizontal-item")
      |> Enum.map(&Floki.text/1)

    assert tabs == ["Overview", "Timeline", "Warnings", "Errors"]

    [version] = lv |> render() |> Floki.parse_document!() |> Floki.attribute("#build-timeline", "data-version")
    render_hook(lv, "load-timeline", %{version: String.to_integer(version)})
    assert has_element?(lv, "#build-timeline")
  end

  test "serves the timeline steps as JSON, without a step for the time a file waited", %{
    conn: conn,
    timeline_path: timeline_path
  } do
    response = conn |> get(timeline_path) |> json_response(200)

    assert Enum.map(response["events"], & &1["category"]) == ["compile", "compile", "compile", "type_check"]
    assert %{"title" => "Type checking Demo.Greeter", "target" => "lib/greeter.ex"} = List.last(response["events"])
    refute Map.has_key?(response, "machine_metrics")
  end

  test "hides the Timeline tab when no file has a recorded start", %{conn: conn, user: user, project: project} do
    build_id = UUIDv7.generate()

    {:ok, ^build_id} =
      Mix.create_build(%{
        id: build_id,
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 500,
        status: "success",
        files: [%{path: "lib/a.ex", compile_duration_ms: 40, modules: ["A"]}]
      })

    for buffer <- [Buffer, Mix.CompiledFile.Buffer], do: buffer.flush()

    {:ok, lv, html} = live(conn, ~p"/mix-build-org/#{project.name}/builds/mix-builds/#{build_id}?tab=timeline")

    refute html =~ "Timeline"
    assert has_element?(lv, "[data-part=build-details]")
  end

  test "shows build details, diagnostics and the file breakdown with the dependency graph", %{conn: conn, path: path} do
    {:ok, lv, html} = live(conn, path)

    assert html =~ "mix compile · Elixir 1.19.1"
    assert html =~ "unused variable"
    assert has_element?(lv, "#mix-breakdown-table")
    assert html =~ "File Breakdown"
    assert html =~ "1.5s"
    # greeter.ex needs macros.ex to compile: one dependency, one dependent.
    table = lv |> element("#mix-breakdown-table") |> render()
    assert table =~ "Compile-time dependencies"
    assert table =~ "Compile-time dependents"

    assert table
           |> Floki.parse_document!()
           |> Floki.find("td")
           |> Enum.count(&(&1 |> Floki.text() |> String.trim() == "1 file")) == 2

    refute table =~ "Waited on"
    refute table =~ "Blocked"
  end

  test "sorts by the dependency graph and switches to modules", %{conn: conn, path: path} do
    # By compile time and by dependents macros.ex leads; by dependencies greeter.ex does.
    {:ok, lv, _html} = live(conn, path)
    table = lv |> element("#mix-breakdown-table") |> render()
    assert position(table, "lib/macros.ex") < position(table, "lib/greeter.ex")

    {:ok, lv, _html} = live(conn, path <> "?breakdown-sort-by=dependents")
    table = lv |> element("#mix-breakdown-table") |> render()
    assert position(table, "lib/macros.ex") < position(table, "lib/greeter.ex")

    {:ok, lv, _html} = live(conn, path <> "?breakdown-sort-by=dependencies")
    table = lv |> element("#mix-breakdown-table") |> render()
    assert position(table, "lib/greeter.ex") < position(table, "lib/macros.ex")

    {:ok, lv, _html} = live(conn, path <> "?breakdown-tab=module")
    table = lv |> element("#mix-breakdown-table") |> render()
    assert table =~ "Demo.Greeter"
    assert table =~ "Demo.Macros"
  end

  defp position(html, text), do: html |> :binary.match(text) |> elem(0)

  test "groups diagnostics into collapsible issue cards on the overview", %{conn: conn, path: path} do
    {:ok, lv, html} = live(conn, path)

    assert has_element?(lv, "#build-run [data-part=errors-and-warnings-card] .issue-card[data-type=warning]")
    assert html =~ "Warning when compiling Elixir file lib/greeter.ex"
    assert html =~ "unused variable in lib/greeter.ex#L4"
    # Client-supplied text is escaped, never rendered as markup.
    assert html =~ "unused alias &lt;b&gt;"
    refute has_element?(lv, ".issue-card[data-type=error]")
  end

  test "leaves the breakdown alone on the tabs that do not show it", %{conn: conn, path: path} do
    reject(&Mix.compiled_files_page/2)

    {:ok, _lv, html} = live(conn, path <> "?tab=warnings")

    assert html =~ "Warnings"
  end

  test "has Warnings and Errors tabs like the Xcode build page", %{conn: conn, path: path} do
    {:ok, lv, _html} = live(conn, path <> "?tab=warnings")
    assert has_element?(lv, "[data-part=warnings-card] .issue-card[data-type=warning]")
    refute has_element?(lv, "[data-part=build-details]")

    {:ok, lv, html} = live(conn, path <> "?tab=errors")
    assert has_element?(lv, "[data-part=errors-card] [data-part=empty-state]")
    assert html =~ "No errors detected"
  end

  test "filters the breakdown by search", %{conn: conn, path: path} do
    {:ok, lv, _html} = live(conn, path <> "?breakdown-search=greeter")

    assert lv |> element("#mix-breakdown-table") |> render() =~ "lib/greeter.ex"
    refute lv |> element("#mix-breakdown-table") |> render() =~ ">lib/macros.ex<"
  end

  test "treats a malformed page number as the first page", %{conn: conn, path: path} do
    {:ok, lv, _html} = live(conn, path <> "?breakdown-page=nope")
    assert lv |> element("#mix-breakdown-table") |> render() =~ "lib/macros.ex"

    {:ok, lv, _html} = live(conn, path <> "?breakdown-page=-3")
    assert lv |> element("#mix-breakdown-table") |> render() =~ "lib/macros.ex"
  end
end
