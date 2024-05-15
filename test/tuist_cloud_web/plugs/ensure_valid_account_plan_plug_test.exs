defmodule TuistCloudWeb.EnsureValidAccountPlanPlugTest do
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  alias TuistCloud.Accounts
  use TuistCloudWeb.ConnCase
  use Plug.Test
  alias TuistCloudWeb.EnsureValidAccountPlanPlug
  alias TuistCloud.ProjectsFixtures
  alias TuistCloudWeb.WarningsHeaderPlug

  test "returns the same connection if the account already has a plan" do
    # Given
    project = ProjectsFixtures.project_fixture()

    account =
      Accounts.get_account_by_id(project.account_id)
      |> Accounts.upgrade_to_enterprise()

    opts = EnsureValidAccountPlanPlug.init([])

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> EnsureValidAccountPlanPlug.call(opts)

    # Then
    assert got == conn
  end

  test "includes a warning when the uploads count is above 80% and under 100%" do
    # Given
    project = ProjectsFixtures.project_fixture()

    account =
      Accounts.get_account_by_id(project.account_id)
      |> Accounts.update_account_cache_upload_event_count(
        trunc(EnsureValidAccountPlanPlug.upload_count_threshold() * 0.9)
      )

    opts = EnsureValidAccountPlanPlug.init([])

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> EnsureValidAccountPlanPlug.call(opts)

    # Then
    warnings = WarningsHeaderPlug.get_warnings(got)

    assert warnings == [
             "Your account is nearing the 30-day free limit of #{EnsureValidAccountPlanPlug.formatted_upload_count_threshold()} cache uploads on Tuist Cloud. Once this limit is reached, you won't be able to use Tuist Cloud's remote caching feature. To continue enjoying this service, please reach out to us at contact@tuist.io for a quote on a Tuist Cloud plan."
           ]
  end

  test "fails the request if the upload count of the account is above the threshold" do
    # Given
    project = ProjectsFixtures.project_fixture()

    account =
      Accounts.get_account_by_id(project.account_id)
      |> Accounts.update_account_cache_upload_event_count(
        trunc(EnsureValidAccountPlanPlug.upload_count_threshold() * 1.1)
      )

    opts = EnsureValidAccountPlanPlug.init([])

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> EnsureValidAccountPlanPlug.call(opts)

    # Then
    assert json_response(got, 402) == %{
             "message" =>
               "Your account is over the 30-day free limit of #{EnsureValidAccountPlanPlug.formatted_upload_count_threshold()} cache uploads on Tuist Cloud. To continue enjoying this service, please reach out to us at contact@tuist.io for a quote on a Tuist Cloud plan."
           }
  end
end
