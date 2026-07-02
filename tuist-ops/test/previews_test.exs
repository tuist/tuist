defmodule TuistOps.PreviewsTest do
  use TuistOps.DataCase, async: true
  use Mimic

  alias TuistOps.JIT.SlackClient
  alias TuistOps.Previews
  alias TuistOps.Previews.GitHubActionsClient
  alias TuistOps.Previews.Workers.MonitorWorkflowWorker

  setup :verify_on_exit!

  describe "create/1" do
    test "dispatches the preview workflow with the preview id and schedules monitoring" do
      stub(SlackClient, :post_message, fn "C_PREVIEWS", _blocks, _opts ->
        {:ok, "1710000000.000001"}
      end)

      expect(GitHubActionsClient, :dispatch, fn "deploy", inputs ->
        assert inputs.slug == "demo"
        assert inputs.preview_id =~ ~r/^\d+$/

        {:ok, %{run_name: "Preview deploy demo ##{inputs.preview_id}"}}
      end)

      assert {:ok, preview} =
               Previews.create(%{
                 slug: "demo",
                 requester_email: "marek@tuist.dev",
                 requester_slack_id: "U_MAREK",
                 slack_channel_id: "C_PREVIEWS",
                 reason: "test branch with Kura"
               })

      assert preview.workflow_run_name == "Preview deploy demo ##{preview.id}"

      job =
        Repo.one!(
          from job in Oban.Job,
            where: job.worker == ^inspect(MonitorWorkflowWorker)
        )

      assert job.args == %{
               "preview_id" => preview.id,
               "run_name" => preview.workflow_run_name
             }
    end
  end
end
