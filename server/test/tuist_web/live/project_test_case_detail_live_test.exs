# Temporarily disabled due to performance issues
# defmodule TuistWeb.ProjectTestCaseDetailLiveTest do
#   use TuistTestSupport.Cases.ConnCase, async: false
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
#     # Given
#     test_case_identifier = "test_case_identifier"
#     now = Timex.now()

#     test_case = CommandEventsFixtures.test_case_fixture(identifier: test_case_identifier)

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case.id,
#       flaky: true,
#       inserted_at: now
#     )

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case.id,
#       inserted_at: now |> Timex.shift(seconds: -10)
#     )

#     # When
#     {:ok, _lv, html} =
#       conn
#       |> live(
#         ~p"/#{organization.account.name}/#{project.name}/tests/cases/#{Base.encode64(test_case_identifier)}"
#       )

#     assert html =~ "Test case #{test_case_identifier} · tuist-org/tuist · Tuist"
#   end

#   test "renders rows with their status", %{
#     conn: conn,
#     organization: organization,
#     project: project
#   } do
#     test_case_identifier = "test_case_identifier"
#     now = Timex.now()

#     test_case = CommandEventsFixtures.test_case_fixture(identifier: test_case_identifier)

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case.id,
#       flaky: true,
#       inserted_at: now
#     )

#     CommandEventsFixtures.test_case_run_fixture(
#       test_case_id: test_case.id,
#       inserted_at: now |> Timex.shift(seconds: -10)
#     )

#     {:ok, lv, _html} =
#       conn
#       |> live(
#         ~p"/#{organization.account.name}/#{project.name}/tests/cases/#{Base.encode64(test_case_identifier)}"
#       )

#     assert has_element?(lv, "table tbody tr:nth-child(1) *", "flaky")
#     assert has_element?(lv, "table tbody tr:nth-child(2) *", "success")
#     refute has_element?(lv, "table tbody tr:nth-child(2) *", "flaky")
#   end

#   test "raises not found error when decoding the base64 identifier fails", %{
#     conn: conn,
#     organization: organization,
#     project: project
#   } do
#     # When / Then
#     assert_raise TuistWeb.Errors.NotFoundError, fn ->
#       conn
#       |> live(~p"/#{organization.account.name}/#{project.name}/tests/cases/invalid-identifier")
#     end
#   end
# end
