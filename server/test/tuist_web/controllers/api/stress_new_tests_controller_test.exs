defmodule TuistWeb.API.StressNewTestsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")
    %{conn: conn, user: user, project: project}
  end

  describe "POST /api/projects/:account_handle/:project_handle/tests with a stress block" do
    test "records the gate's verdict and candidates on the run", %{conn: conn, user: user, project: project} do
      conn =
        post(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/tests", %{
          duration: 100,
          is_ci: true,
          status: "success",
          git_branch: "feature",
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 10,
              test_cases: [%{name: "testNew", test_suite_name: "CheckoutTests", status: "success", duration: 5}]
            }
          ],
          stress_new_tests: %{
            mode: "enforce",
            outcome: "disagreed",
            new_count: 1,
            stressed_count: 1,
            excluded_count: 0,
            inventory_count: 12,
            test_cases: [
              %{
                name: "testNew",
                suite_name: "CheckoutTests",
                module_name: "AppTests",
                repetitions: 10,
                failed_repetitions: 3,
                outcome: "disagreed",
                is_quarantined: false
              }
            ]
          }
        })

      response = json_response(conn, :ok)
      {:ok, test_run} = Tests.get_test(response["id"])
      assert test_run.stress_mode == "enforce"
      assert test_run.stress_outcome == "disagreed"
      assert test_run.stress_new_count == 1
      assert test_run.stress_inventory_count == 12

      [candidate] = Tuist.Tests.StressNewTests.list_candidates(test_run.id)
      assert candidate.name == "testNew"
      assert candidate.failed_repetitions == 3
      assert candidate.outcome == "disagreed"
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/tests/stress-new-tests/verdict" do
    test "returns the new test cases priced from the project's curve", %{conn: conn, user: user, project: project} do
      {:ok, _} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: user.account.id,
          duration: 1000,
          status: "success",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "testOld", test_suite_name: "CheckoutTests", status: "success", duration: 10}]
            }
          ]
        })

      conn =
        post(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/tests/stress-new-tests/verdict", %{
          test_cases: [
            %{name: "testOld", suite_name: "CheckoutTests", module_name: "AppTests", duration: 10},
            %{name: "testNew", suite_name: "CheckoutTests", module_name: "AppTests", duration: 7_000}
          ]
        })

      response = json_response(conn, :ok)
      assert response["enabled"] == true
      assert response["guard"] == nil
      assert response["inventory_count"] == 1

      assert response["candidates"] == [
               %{
                 "name" => "testNew",
                 "suite_name" => "CheckoutTests",
                 "module_name" => "AppTests",
                 "repetitions" => 5,
                 "excluded_reason" => nil
               }
             ]

      assert response["parameters"]["candidate_cap"] == 200
      assert response["parameters"]["wall_clock_ceiling_ms"] == 600_000
      assert response["parameters"]["bulk_change_ratio"] == 0.3
      assert response["parameters"]["bulk_change_floor"] == 50
      assert length(response["parameters"]["repetition_curve"]) == 4
    end

    test "reports the guard that fired", %{conn: conn, user: user, project: project} do
      conn =
        post(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/tests/stress-new-tests/verdict", %{
          test_cases: [%{name: "testNew", module_name: "AppTests"}]
        })

      response = json_response(conn, :ok)
      assert response["candidates"] == []
      assert response["guard"] == %{"kind" => "no_default_branch_history", "new_count" => 1, "inventory_count" => 0}
    end

    test "rejects a body without test cases", %{conn: conn, user: user, project: project} do
      conn = post(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/tests/stress-new-tests/verdict", %{})

      assert json_response(conn, :bad_request)
    end

    test "returns forbidden for a project the user cannot read", %{conn: conn} do
      other_project = ProjectsFixtures.project_fixture(preload: [:account])

      conn =
        post(
          conn,
          ~p"/api/projects/#{other_project.account.name}/#{other_project.name}/tests/stress-new-tests/verdict",
          %{
            test_cases: []
          }
        )

      assert json_response(conn, :forbidden)
    end
  end
end
