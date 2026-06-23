defmodule TuistOps.Previews.GitHubActionsClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.Previews.GitHubActionsClient

  setup :verify_on_exit!

  test "workflow_run_name matches the workflow run-name shape" do
    assert GitHubActionsClient.workflow_run_name("deploy", %{
             slug: "demo",
             preview_id: "123"
           }) == "Preview deploy demo #123"
  end

  test "workflow_run finds the matching workflow run by display title" do
    stub(Environment, :github_repository, fn -> "tuist/tuist" end)
    stub(Environment, :preview_workflow_id, fn -> "preview-deploy.yml" end)
    stub(Environment, :github_actions_token, fn -> "token" end)

    expect(
      Req,
      :get,
      fn "https://api.github.com/repos/tuist/tuist/actions/workflows/preview-deploy.yml/runs",
         opts ->
        assert opts[:params] == [event: "workflow_dispatch", per_page: 50]

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "workflow_runs" => [
               %{
                 "display_title" => "Preview deploy other #122",
                 "status" => "completed",
                 "conclusion" => "success",
                 "html_url" => "https://github.com/other",
                 "id" => 122
               },
               %{
                 "display_title" => "Preview deploy demo #123",
                 "status" => "completed",
                 "conclusion" => "success",
                 "html_url" => "https://github.com/match",
                 "id" => 123
               }
             ]
           }
         }}
      end
    )

    assert {:ok,
            %{
              id: 123,
              status: "completed",
              conclusion: "success",
              html_url: "https://github.com/match"
            }} = GitHubActionsClient.workflow_run("Preview deploy demo #123")
  end
end
