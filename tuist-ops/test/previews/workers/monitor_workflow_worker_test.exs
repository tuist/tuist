defmodule TuistOps.Previews.Workers.MonitorWorkflowWorkerTest do
  use TuistOps.DataCase, async: true
  use Mimic

  alias TuistOps.JIT.SlackClient
  alias TuistOps.Previews.GitHubActionsClient
  alias TuistOps.Previews.Preview
  alias TuistOps.Previews.Workers.MonitorWorkflowWorker

  setup :verify_on_exit!

  defp insert_preview!(overrides \\ %{}) do
    attrs =
      %{
        slug: "demo",
        status: "creating",
        requester_email: "marek@tuist.dev",
        requester_slack_id: "U_MAREK",
        reason: "test branch with Kura",
        ttl_seconds: 7200,
        host: "demo.preview.tuist.dev",
        slack_channel_id: "C_PREVIEWS",
        slack_message_ts: "1710000000.000001",
        workflow_run_name: "Preview deploy demo #1"
      }
      |> Map.merge(overrides)

    attrs
    |> Preview.create_changeset()
    |> Repo.insert!()
  end

  defp perform(preview) do
    %Oban.Job{args: %{"preview_id" => preview.id, "run_name" => preview.workflow_run_name}}
    |> MonitorWorkflowWorker.perform()
  end

  test "snoozes while the workflow run is still in progress" do
    preview = insert_preview!()

    expect(GitHubActionsClient, :workflow_run, fn "Preview deploy demo #1" ->
      {:ok, %{status: "in_progress", conclusion: nil, html_url: "https://github.com/run"}}
    end)

    assert {:snooze, 30} = perform(preview)
  end

  test "marks the preview active and updates Slack when the workflow succeeds" do
    preview = insert_preview!()

    expect(GitHubActionsClient, :workflow_run, fn "Preview deploy demo #1" ->
      {:ok,
       %{
         status: "completed",
         conclusion: "success",
         html_url: "https://github.com/tuist/tuist/actions/runs/1"
       }}
    end)

    expect(SlackClient, :update_message, fn "C_PREVIEWS", "1710000000.000001", blocks, opts ->
      text = blocks |> List.first() |> get_in([:text, :text])

      assert text =~ "Preview deployed"
      assert text =~ "https://demo.preview.tuist.dev"
      assert text =~ "https://github.com/tuist/tuist/actions/runs/1"
      assert opts[:fallback_text] == "Preview deployed"

      :ok
    end)

    assert :ok = perform(preview)

    preview = Repo.reload!(preview)
    assert preview.status == "active"
    assert preview.workflow_run_url == "https://github.com/tuist/tuist/actions/runs/1"
  end

  test "marks the preview failed and updates Slack when the workflow fails" do
    preview = insert_preview!()

    expect(GitHubActionsClient, :workflow_run, fn "Preview deploy demo #1" ->
      {:ok,
       %{
         status: "completed",
         conclusion: "failure",
         html_url: "https://github.com/tuist/tuist/actions/runs/2"
       }}
    end)

    expect(SlackClient, :update_message, fn "C_PREVIEWS", "1710000000.000001", blocks, opts ->
      text = blocks |> List.first() |> get_in([:text, :text])

      assert text =~ "Preview request failed"
      assert text =~ "workflow_failed"
      assert text =~ "https://github.com/tuist/tuist/actions/runs/2"
      assert opts[:fallback_text] == "Preview request failed"

      :ok
    end)

    assert :ok = perform(preview)

    preview = Repo.reload!(preview)
    assert preview.status == "failed"
    assert preview.failure_reason == ~s({:workflow_failed, "failure"})
    assert preview.workflow_run_url == "https://github.com/tuist/tuist/actions/runs/2"
  end

  test "ignores stale jobs for previews that no longer match the workflow run name" do
    preview = insert_preview!(%{workflow_run_name: "Preview deploy demo #2"})

    assert :ok =
             %Oban.Job{
               args: %{"preview_id" => preview.id, "run_name" => "Preview deploy demo #1"}
             }
             |> MonitorWorkflowWorker.perform()
  end
end
