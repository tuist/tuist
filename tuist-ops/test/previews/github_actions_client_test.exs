defmodule TuistOps.Previews.GitHubActionsClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.GitHub.AppToken
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
    stub(AppToken, :token, fn -> {:ok, "installation-token"} end)

    expect(
      Req,
      :get,
      fn "https://api.github.com/repos/tuist/tuist/actions/workflows/preview-deploy.yml/runs",
         opts ->
        assert opts[:params] == [event: "workflow_dispatch", per_page: 50]
        assert Enum.member?(opts[:headers], {"Authorization", "Bearer installation-token"})

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

  test "dispatch triggers the preview workflow with an installation token" do
    stub(Environment, :github_repository, fn -> "tuist/tuist" end)
    stub(Environment, :preview_workflow_id, fn -> "preview-deploy.yml" end)
    stub(Environment, :github_workflow_ref, fn -> "main" end)
    stub(AppToken, :token, fn -> {:ok, "installation-token"} end)

    expect(
      Req,
      :post,
      fn "https://api.github.com/repos/tuist/tuist/actions/workflows/preview-deploy.yml/dispatches",
         opts ->
        assert Enum.member?(opts[:headers], {"Authorization", "Bearer installation-token"})

        assert JSON.decode!(opts[:body]) == %{
                 "ref" => "main",
                 "inputs" => %{
                   "action" => "deploy",
                   "preview_id" => "123",
                   "slug" => "demo"
                 }
               }

        {:ok, %Req.Response{status: 204, body: ""}}
      end
    )

    assert {:ok,
            %{
              workflow_id: "preview-deploy.yml",
              workflow_ref: "main",
              run_name: "Preview deploy demo #123"
            }} = GitHubActionsClient.dispatch("deploy", %{slug: "demo", preview_id: "123"})
  end

  test "returns token errors before calling GitHub" do
    stub(Environment, :github_repository, fn -> "tuist/tuist" end)
    stub(Environment, :preview_workflow_id, fn -> "preview-deploy.yml" end)
    stub(AppToken, :token, fn -> {:error, {:missing_env, "GITHUB_APP_ID"}} end)

    assert {:error, {:github_app_token, {:missing_env, "GITHUB_APP_ID"}}} =
             GitHubActionsClient.workflow_run("Preview deploy demo #123")
  end
end
