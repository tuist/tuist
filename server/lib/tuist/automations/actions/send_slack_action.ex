defmodule Tuist.Automations.Actions.SendSlackAction do
  @moduledoc false
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation
  alias Tuist.Tests

  require Logger

  def execute(automation, %{type: :test_case, id: test_case_id}, %{"channel" => channel} = action) do
    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         project = Projects.get_project_by_id(automation.project_id),
         false <- is_nil(project),
         project = Repo.preload(project, account: :slack_installation),
         %Installation{access_token: access_token} <- project.account.slack_installation do
      message = interpolate(action["message"], automation, project, test_case)
      blocks = build_blocks(automation, message)
      Client.post_message(access_token, channel, blocks)
    else
      {:error, :not_found} ->
        Logger.warning("Automation #{automation.id} send_slack skipped: test case #{test_case_id} not found")

        :ok

      true ->
        Logger.warning("Automation #{automation.id} send_slack skipped: project #{automation.project_id} not found")

        :ok

      nil ->
        Logger.warning(
          "Automation #{automation.id} send_slack skipped: Slack installation missing for project #{automation.project_id}"
        )

        :ok

      other ->
        Logger.warning("Automation #{automation.id} send_slack skipped for test case #{test_case_id}: #{inspect(other)}")

        :ok
    end
  end

  defp interpolate(template, automation, project, test_case) do
    base_url = Environment.app_url()
    account_name = project.account.name
    project_name = project.name
    test_case_url = "#{base_url}/#{account_name}/#{project_name}/tests/test-cases/#{test_case.id}"

    template
    |> String.replace("{{test_case.name}}", test_case.name || "")
    |> String.replace("{{test_case.module_name}}", test_case.module_name || "")
    |> String.replace("{{test_case.suite_name}}", test_case.suite_name || "")
    |> String.replace("{{test_case.url}}", test_case_url)
    |> String.replace("{{automation.name}}", automation.name || "")
  end

  defp build_blocks(automation, message) do
    [
      %{
        type: "header",
        text: %{type: "plain_text", text: ":robot_face: #{automation.name}"}
      },
      %{
        type: "section",
        text: %{type: "mrkdwn", text: message}
      }
    ]
  end
end
