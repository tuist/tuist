defmodule TuistWeb.PublicProjectOverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.Builds.Analytics
  alias Tuist.Bundles
  alias Tuist.CommandEvents
  alias Tuist.FeatureFlags
  alias Tuist.KeyValueStore.LoadLimiter
  alias Tuist.Mix, as: TuistMix
  alias Tuist.Mix.Build.Buffer, as: MixBuildBuffer
  alias Tuist.OnceEvents
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    stub(FeatureFlags, :public_page_challenge_enabled?, fn -> true end)
    stub(Tuist.Environment, :prod?, fn -> true end)
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    %{user: AccountsFixtures.user_fixture(preload: [:account])}
  end

  for build_system <- [:xcode, :gradle, :bazel, :mix, :once] do
    @build_system build_system
    test "#{build_system} public overview serves populated HTML and sharing metadata without JavaScript", %{
      conn: conn,
      user: user
    } do
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public, build_system: @build_system)

      insert_build(@build_system, project, user)
      path = "/#{user.account.name}/#{project.name}"
      conn = get(conn, path)
      html = html_response(conn, 200)
      document = Floki.parse_document!(html)

      widget =
        case @build_system do
          :bazel -> "#bazel-average-build-time"
          :once -> "#once-average-build-time"
          _ -> "#widget-average-build-time"
        end

      assert document |> Floki.find(widget) |> Floki.text() =~ "5.0s"

      assert document |> Floki.find("meta[property='og:image']") |> Floki.attribute("content") |> hd() =~
               "/open-graph-images/"

      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
      refute get_session(conn, "public_page_challenge_verified_at")
    end
  end

  for build_system <- [:xcode, :gradle, :bazel, :mix, :once] do
    @build_system build_system
    test "signed-in users get fresh #{@build_system} analytics instead of the anonymous cache", %{
      conn: conn,
      user: user
    } do
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public, build_system: @build_system)

      path = "/#{user.account.name}/#{project.name}"
      insert_build(@build_system, project, user)
      assert conn |> get(path) |> html_response(200) =~ "5.0s"
      insert_build(@build_system, project, user, 15_000)

      reject(LoadLimiter, :run, 4)
      reject(&Bundles.project_app_bundle_options/1)
      {:ok, view, _html} = live(log_in_user(conn, user), path)
      html = render_async(view, 5_000)

      widget =
        case @build_system do
          :bazel -> "#bazel-average-build-time"
          :once -> "#once-average-build-time"
          _ -> "#widget-average-build-time"
        end

      assert html |> Floki.parse_document!() |> Floki.find(widget) |> Floki.text() =~ "10.0s"
    end
  end

  test "tracking variants reuse the cached default overview", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    insert_build(:xcode, project, user)
    path = "/#{user.account.name}/#{project.name}"
    assert conn |> get(path) |> html_response(200) =~ "5.0s"

    stub(Bundles, :project_app_bundle_options, fn _ -> flunk("app options should be cached") end)
    stub(Analytics, :build_duration_analytics, fn _, _ -> flunk("analytics should be cached") end)

    for tracking <- ["utm_source=slack", "utm_source=google&gclid=123", "ref=share&fbclid=456"] do
      html = conn |> get(path <> "?" <> tracking) |> html_response(200)
      assert html =~ "5.0s"
      [canonical] = html |> Floki.parse_document!() |> Floki.find("link[rel='canonical']") |> Floki.attribute("href")
      assert URI.parse(canonical).path == path
      refute URI.parse(canonical).query
    end
  end

  test "filtered and deeper dashboard requests remain challenged", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    path = "/#{user.account.name}/#{project.name}"

    for suffix <- [
          "?analytics-environment=ci",
          "?builds-date-range=custom",
          "?bundle-size-app=Other",
          "?unknown=1",
          "/analytics",
          "/builds",
          "/tests"
        ] do
      response = get(conn, path <> suffix)
      assert redirected_to(response) == "/turnstile-challenge"
      assert get_resp_header(response, "x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "an anonymous root LiveView cannot patch into uncached exploration", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    path = "/#{user.account.name}/#{project.name}"
    {:ok, view, _html} = live(conn, path)
    render_async(view, 2_000)

    target = path <> "?analytics-environment=ci"
    assert {:error, {:redirect, %{to: to}}} = render_patch(view, target)
    assert to == "/turnstile-challenge?return_to=" <> URI.encode_www_form(target)
  end

  for {event, parameter} <- [
        {"analytics_period_changed", "analytics-date-range"},
        {"bundle_size_period_changed", "bundle-size-date-range"},
        {"builds_period_changed", "builds-date-range"}
      ] do
    @event event
    @parameter parameter
    test "applying #{@parameter} through the UI challenges before filtered queries", %{conn: conn, user: user} do
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
      path = "/#{user.account.name}/#{project.name}"
      conn = put_req_header(conn, "user-agent", "Example automated browser")
      {:ok, view, _html} = live(conn, path)
      render_async(view, 2_000)
      reject(&Analytics.build_duration_analytics/2)
      reject(&Bundles.project_app_bundle_options/1)
      reject(&CommandEvents.get_command_event_by_id/1)
      target = path <> "?#{@parameter}=last-7-days"

      assert {:error, {:redirect, %{to: to}}} =
               render_hook(view, @event, %{
                 "value" => %{"start" => "2026-01-01", "end" => "2026-01-07"},
                 "preset" => "last-7-days"
               })

      assert to == "/turnstile-challenge?return_to=" <> URI.encode_www_form(target)
    end
  end

  test "a dropdown filter challenges even when it explicitly selects the default", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    path = "/#{user.account.name}/#{project.name}"
    {:ok, view, _html} = live(conn, path)
    render_async(view, 2_000)
    reject(&Analytics.build_duration_analytics/2)
    target = path <> "?analytics-environment=any"

    [href] =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("a[href='?analytics-environment=any']")
      |> Floki.attribute("href")

    assert target == path <> href
    assert {:error, {:redirect, %{to: to}}} = render_patch(view, target)

    assert to == "/turnstile-challenge?return_to=" <> URI.encode_www_form(target)
  end

  test "an unverified join rejects selected-run parameters before layout lookup", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    path = "/#{user.account.name}/#{project.name}"
    {:ok, view, _html} = live(conn, path)
    render_async(view, 2_000)
    reject(&CommandEvents.get_command_event_by_id/1)
    target = path <> "/analytics?run_id=" <> Ecto.UUID.generate()
    assert {:error, {:redirect, %{to: "/turnstile-challenge"}}} = live_redirect(view, to: target)
  end

  test "making a warmed public project private prevents subsequent anonymous reads", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    insert_build(:xcode, project, user)
    path = "/#{user.account.name}/#{project.name}"
    assert conn |> get(path) |> html_response(200) =~ "5.0s"

    project |> Ecto.Changeset.change(visibility: :private) |> Repo.update!()
    response = get(conn, path)
    assert redirected_to(response) =~ "/users/log_in"
    refute response.resp_body =~ "5.0s"
    refute get_resp_header(response, "x-robots-tag") == ["index, follow"]
  end

  test "anonymous live navigation cannot expose a warmed SSO-gated public root", %{conn: conn, user: user} do
    organization =
      AccountsFixtures.organization_fixture(
        creator: user,
        sso_provider: :okta,
        sso_organization_id: "example.okta.com",
        oauth2_client_id: "client",
        oauth2_client_secret: "secret"
      )

    organization |> Ecto.Changeset.change(sso_enforced: true) |> Repo.update!()
    account = organization.account |> Ecto.Changeset.change(visibility: :public) |> Repo.update!()
    protected = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    protected_path = "/#{account.name}/#{protected.name}"
    insert_build(:xcode, protected, user)
    assert conn |> get(protected_path) |> html_response(200) =~ "5.0s"
    {:ok, protected_view, _html} = live(conn, protected_path)
    render_async(protected_view, 2_000)
    account |> Ecto.Changeset.change(visibility: :private) |> Repo.update!()

    patch_path = protected_path <> "?utm_source=share"
    assert {:error, {:redirect, %{to: patch_to}}} = render_patch(protected_view, patch_path)
    assert patch_to == "/turnstile-challenge?return_to=" <> URI.encode_www_form(patch_path)

    source = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    {:ok, view, _html} = live(conn, "/#{user.account.name}/#{source.name}")
    assert {:error, {:redirect, %{to: to}}} = live_redirect(view, to: protected_path)
    assert to == "/turnstile-challenge?return_to=" <> URI.encode_www_form(protected_path)
    assert conn |> get(protected_path) |> redirected_to() =~ "/users/auth/okta"
  end

  @tag capture_log: true
  test "a connected public overview cannot read warmed data after the project turns private", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public)
    path = "/#{user.account.name}/#{project.name}"
    {:ok, view, _html} = live(conn, path)
    render_async(view, 2_000)
    project |> Ecto.Changeset.change(visibility: :private) |> Repo.update!()
    Process.flag(:trap_exit, true)

    assert {{%TuistWeb.Errors.NotFoundError{}, _stacktrace}, _call} =
             catch_exit(render_patch(view, path <> "?utm_source=share"))
  end

  defp insert_build(build_system, project, user, duration \\ 5_000)

  defp insert_build(:xcode, project, _user, duration) do
    RunsFixtures.build_fixture(
      project_id: project.id,
      duration: duration,
      inserted_at: DateTime.add(DateTime.utc_now(), -60, :second)
    )
  end

  defp insert_build(:gradle, project, user, duration) do
    GradleFixtures.build_fixture(project_id: project.id, account_id: user.account.id, duration_ms: duration)
  end

  defp insert_build(:bazel, project, _user, duration) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(-60, :second)

    Bazel.create_invocations([
      %{
        invocation_id: UUIDv7.generate(),
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        command: "build",
        status: "success",
        exit_code: 0,
        started_at: NaiveDateTime.add(now, -div(duration, 1_000), :second),
        finished_at: now,
        duration_ms: duration,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end

  defp insert_build(:mix, project, user, duration) do
    {:ok, _id} =
      TuistMix.create_build(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: duration,
        status: "success"
      })

    MixBuildBuffer.flush()
  end

  defp insert_build(:once, project, _user, duration) do
    now = DateTime.add(DateTime.utc_now(), -60, :second)

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        command_display: "once build",
        started_at: now
      })

    OnceEvents.finalize_run(run, %{finalization: "finalized", exit_status: 0, wall_ms: duration, finalized_at: now})
  end
end
