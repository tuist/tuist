defmodule TuistWeb.API.SelectiveTestingCoverageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")
    %{conn: conn, user: user, project: project}
  end

  describe "POST /api/projects/:account_handle/:project_handle/tests/selective-testing/coverage/baseline" do
    test "answers not_enabled when test impact analysis isn't enabled for the project", %{
      conn: conn,
      user: user,
      project: project
    } do
      stub(FeatureFlags, :test_impact_analysis_enabled?, fn _account, _project -> false end)

      response =
        conn
        |> post(~p"/api/projects/#{user.account.name}/#{project.name}/tests/selective-testing/coverage/baseline", %{
          build_system: "xcode",
          commit_sha: "merge",
          parent_shas: ["head", "base"],
          platform: "ios",
          xcode: %{scheme: "App", test_plan: "AppTests", destination: "platform=iOS Simulator,name=iPhone 17"}
        })
        |> json_response(:ok)

      assert response == %{"baseline_sha" => nil, "reason" => "not_enabled", "diff_cached" => false}
      assert_schema(response, "TestImpactBaseline", Spec.spec())
    end

    test "answers not_enabled for enabled projects until baseline resolution lands", %{
      conn: conn,
      user: user,
      project: project
    } do
      stub(FeatureFlags, :test_impact_analysis_enabled?, fn _account, _project -> true end)

      response =
        conn
        |> post(~p"/api/projects/#{user.account.name}/#{project.name}/tests/selective-testing/coverage/baseline", %{
          build_system: "xcode",
          commit_sha: "abc"
        })
        |> json_response(:ok)

      assert response["reason"] == "not_enabled"
    end

    test "requires the build system and the checked-out commit", %{conn: conn, user: user, project: project} do
      conn =
        post(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/tests/selective-testing/coverage/baseline", %{
          build_system: "xcode"
        })

      assert json_response(conn, :bad_request)
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/tests/selective-testing/coverage/runs" do
    @run_params %{
      build_system: "xcode",
      head_sha: "head",
      commit_sha: "merge",
      parent_shas: ["head", "base"],
      baseline_sha: "baseline",
      changed_files: [
        %{path: "App/Sources/Login.swift", status: "M", blob: "b1", affected_modules: ["AppTests"]},
        %{path: "README.md", status: "M", blob: "b2", affected_modules: []},
        %{path: "App/Sources/Old.swift", status: "D"}
      ],
      changed_files_count: 3,
      dirty: false,
      modules: ["AppTests"],
      platform: "ios",
      git_branch: "feature",
      xcode: %{scheme: "App"}
    }

    test "is not found when test impact analysis isn't enabled for the project", %{
      conn: conn,
      user: user,
      project: project
    } do
      stub(FeatureFlags, :test_impact_analysis_enabled?, fn _account, _project -> false end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/tests/selective-testing/coverage/runs",
          @run_params
        )

      assert json_response(conn, :not_found)["message"] == "Test impact analysis isn't enabled for this project."
    end

    test "accepts a fallback without a baseline", %{conn: conn, user: user, project: project} do
      stub(FeatureFlags, :test_impact_analysis_enabled?, fn _account, _project -> true end)

      conn =
        post(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/tests/selective-testing/coverage/runs", %{
          build_system: "xcode",
          head_sha: "head",
          fallback_reason: "history_unavailable"
        })

      assert json_response(conn, :not_implemented)
    end

    test "rejects a changed file without a path or status", %{conn: conn, user: user, project: project} do
      conn =
        post(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/tests/selective-testing/coverage/runs",
          %{@run_params | changed_files: [%{path: "App/Sources/Login.swift"}]}
        )

      assert json_response(conn, :bad_request)
    end

    test "requires the build system and the head commit", %{conn: conn, user: user, project: project} do
      conn =
        post(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/tests/selective-testing/coverage/runs", %{
          build_system: "xcode"
        })

      assert json_response(conn, :bad_request)
    end
  end

  describe "TestImpactRun" do
    test "describes a selection with its skip list and a fallback with its reason" do
      assert_schema(
        %{
          "id" => UUIDv7.generate(),
          "outcome" => "selected",
          "counts" => %{"requested" => 10, "skipped" => 7, "selected" => 3},
          "skipped_tests" => [
            %{"module" => "AppTests", "suite" => "LoginTests", "name" => "testLogout"},
            %{"module" => "CoreTests"}
          ]
        },
        "TestImpactRun",
        Spec.spec()
      )

      assert_schema(
        %{
          "id" => UUIDv7.generate(),
          "outcome" => "fallback",
          "reason" => "tracked_file_changed",
          "matched_path" => "Package.resolved"
        },
        "TestImpactRun",
        Spec.spec()
      )
    end
  end
end
