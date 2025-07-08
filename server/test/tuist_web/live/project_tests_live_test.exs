# Temporarily disabled due to performance issues
# defmodule TuistWeb.ProjectTestsLiveTest do
#   use TuistTestSupport.Cases.ConnCase
#   use TuistTestSupport.Cases.LiveCase
#   use Mimic

#   import Phoenix.LiveViewTest
#   alias TuistTestSupport.Fixtures.CommandEventsFixtures
#   alias TuistTestSupport.Fixtures.ProjectsFixtures
#   alias TuistTestSupport.Fixtures.AccountsFixtures

#   setup %{conn: conn} do
#     user = AccountsFixtures.user_fixture()

#     %{account: account} =
#       organization =
#       AccountsFixtures.organization_fixture(
#         name: "tuist-org",
#         creator: user,
#         preload: [:account]
#       )

#     selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

#     conn =
#       conn
#       |> assign(:selected_project, selected_project)
#       |> assign(:selected_account, account)
#       |> log_in_user(user)

#     %{conn: conn, user: user, project: selected_project, organization: organization}
#   end

#   test "sets the right title", %{conn: conn, organization: organization, project: project} do
#     # When
#     {:ok, _lv, html} =
#       conn
#       |> live(~p"/#{organization.account.name}/#{project.name}/tests")

#     assert html =~ "Tests · tuist-org/tuist · Tuist"
#   end

#   test "renders flaky tests", %{conn: conn, project: project} do
#     test_case_one =
#       CommandEventsFixtures.test_case_fixture(
#         name: "testExample()",
#         project_id: project.id,
#         flaky: true
#       )

#     test_case_two =
#       CommandEventsFixtures.test_case_fixture(
#         name: "testExampleTwo()",
#         project_id: project.id,
#         flaky: true
#       )

#     test_case_three =
#       CommandEventsFixtures.test_case_fixture(
#         name: "testExampleThree()",
#         project_id: project.id,
#         flaky: false
#       )

#     test_case_four =
#       CommandEventsFixtures.test_case_fixture(
#         name: "testExampleFour()",
#         flaky: true
#       )

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case_one.id,
#       flaky: true,
#       inserted_at: ~N[2021-01-01 01:00:00]
#     )

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case_two.id,
#       flaky: true,
#       inserted_at: ~N[2021-01-01 02:00:00]
#     )

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case_three.id,
#       flaky: false,
#       inserted_at: ~N[2021-01-01 03:00:00]
#     )

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case_four.id,
#       flaky: true,
#       inserted_at: ~N[2021-01-01 04:00:00]
#     )

#     {:ok, lv, _html} =
#       conn
#       |> live(~p"/tuist-org/tuist/tests")

#     assert has_element?(lv, "table tbody tr:nth-child(1) *", "testExampleTwo()")
#     assert has_element?(lv, "table tbody tr:nth-child(2) *", "testExample()")
#   end
# end
