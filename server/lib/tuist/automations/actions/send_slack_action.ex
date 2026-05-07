defmodule Tuist.Automations.Actions.SendSlackAction do
  @moduledoc false
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation
  alias Tuist.Tests

  require Logger

  def execute(automation, %{type: :test_case, id: test_case_id}, action) do
    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         project = Projects.get_project_by_id(automation.project_id),
         false <- is_nil(project) do
      project = Repo.preload(project, account: :slack_installation)
      message = interpolate(action["message"], automation, project, test_case)
      blocks = build_blocks(automation, message)
      deliver(action, project, blocks, automation, test_case_id)
    else
      {:error, :not_found} ->
        Logger.warning("Automation #{automation.id} send_slack skipped: test case #{test_case_id} not found")
        :ok

      true ->
        Logger.warning("Automation #{automation.id} send_slack skipped: project #{automation.project_id} not found")

        :ok

      other ->
        Logger.warning("Automation #{automation.id} send_slack skipped for test case #{test_case_id}: #{inspect(other)}")

        :ok
    end
  end

  # Prefer the action's encrypted webhook URL (captured the next time the
  # user picks the channel). Fall back to the account-level bot token +
  # channel id for actions configured before the webhook flow existed.
  defp deliver(%{"webhook_url_encrypted" => encrypted}, _project, blocks, automation, _test_case_id)
       when is_binary(encrypted) and encrypted != "" do
    case Slack.decrypt_webhook_url(encrypted) do
      {:ok, webhook_url} ->
        Client.post_to_webhook(webhook_url, blocks)

      {:error, _reason} ->
        Logger.warning(
          "Automation #{automation.id} send_slack skipped: webhook URL failed to decrypt"
        )

        :ok
    end
  end

  defp deliver(%{"channel" => channel}, project, blocks, automation, _test_case_id)
       when is_binary(channel) and channel != "" do
    case project.account.slack_installation do
      %Installation{access_token: token} ->
        Client.post_message(token, channel, blocks)

      _ ->
        Logger.warning(
          "Automation #{automation.id} send_slack skipped: missing Slack credentials for project #{project.id}"
        )

        :ok
    end
  end

  defp deliver(_action, project, _blocks, automation, _test_case_id) do
    Logger.warning(
      "Automation #{automation.id} send_slack skipped: missing channel/webhook configuration for project #{project.id}"
    )

    :ok
  end

  defp interpolate(template, automation, project, test_case) do
    base_url = Environment.app_url()
    account_name = project.account.name
    project_name = project.name
    test_case_url = "#{base_url}/#{account_name}/#{project_name}/tests/test-cases/#{test_case.id}"

    template
    |> String.replace("{{test_case.name}}", escape_mrkdwn(test_case.name))
    |> String.replace("{{test_case.module_name}}", escape_mrkdwn(test_case.module_name))
    |> String.replace("{{test_case.suite_name}}", escape_mrkdwn(test_case.suite_name))
    |> String.replace("{{test_case.url}}", test_case_url)
    |> String.replace("{{automation.name}}", escape_mrkdwn(automation.name))
  end

  # Escape `&`, `<`, `>` per Slack mrkdwn rules so user-controlled test-case
  # names, module names, and automation names can't break out of the message
  # envelope or inject <@channel>-style mentions.
  # https://api.slack.com/reference/surfaces/formatting#escaping
  defp escape_mrkdwn(nil), do: ""

  defp escape_mrkdwn(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp build_blocks(automation, message) do
    [
      %{
        type: "header",
        # Header uses plain_text (Slack renders it literally), so only the
        # emoji prefix needs to be preserved; automation.name cannot leak
        # mrkdwn from this block.
        text: %{type: "plain_text", text: ":robot_face: #{automation.name || ""}"}
      },
      %{
        type: "section",
        text: %{type: "mrkdwn", text: message}
      }
    ]
  end
end
