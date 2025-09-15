defmodule TuistWeb.QAControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures
  alias TuistWeb.Errors.NotFoundError

  setup do
    user = AccountsFixtures.user_fixture()
    account = user.account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    preview = AppBuildsFixtures.preview_fixture(project: project)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    qa_run = QAFixtures.qa_run_fixture(app_build: app_build)
    screenshot = QAFixtures.screenshot_fixture(qa_run: qa_run, file_name: "test_screenshot.png")

    %{
      account: account,
      project: project,
      preview: preview,
      app_build: app_build,
      qa_run: qa_run,
      screenshot: screenshot
    }
  end

  describe "download_screenshot/2" do
    test "returns streamed PNG when screenshot exists in storage", %{
      conn: conn,
      account: account,
      project: project,
      qa_run: qa_run,
      screenshot: screenshot
    } do
      # Given
      expected_key =
        "#{String.downcase(account.name)}/#{String.downcase(project.name)}/qa/#{qa_run.id}/screenshots/#{screenshot.id}.png"

      stub(Storage, :stream_object, fn ^expected_key, _actor ->
        ["chunk1", "chunk2", "chunk3"]
      end)

      # When
      conn =
        get(
          conn,
          ~p"/#{account.name}/#{project.name}/qa/runs/#{qa_run.id}/screenshots/#{screenshot.id}"
        )

      # Then
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert conn.state == :chunked
    end

    test "raises NotFoundError when screenshot ID doesn't exist", %{
      conn: conn,
      account: account,
      project: project,
      qa_run: qa_run
    } do
      # Given
      nonexistent_screenshot_id = UUIDv7.generate()

      # When / Then
      assert_raise NotFoundError, "QA screenshot not found.", fn ->
        get(
          conn,
          ~p"/#{account.name}/#{project.name}/qa/runs/#{qa_run.id}/screenshots/#{nonexistent_screenshot_id}"
        )
      end
    end
  end
end
