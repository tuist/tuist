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

  # A group message previews a few test cases and links to the automation for
  # the rest. Slack rejects section text longer than 3,000 characters, so names
  # are truncated and the lines are packed into as many sections as they need.
  @max_listed_test_cases 10
  @max_section_length 3000
  @max_listed_name_length 150
  @max_listed_module_name_length 60

  def execute(automation, %{type: :test_case, id: test_case_id}, action) do
    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         project = Projects.get_project_by_id(automation.project_id),
         false <- is_nil(project) do
      project = Repo.preload(project, account: :slack_installation)
      message = interpolate(action["message"], automation, project, test_case)
      blocks = [header_block(automation), section_block(message)]
      deliver(action, project, blocks, automation)
    else
      {:error, :not_found} ->
        Logger.warning("Automation #{automation.id} send_slack skipped: test case #{test_case_id} not found")
        :ok

      true ->
        Logger.warning("Automation #{automation.id} send_slack skipped: project #{automation.project_id} not found")

        :ok
    end
  end

  # The message template describes a single test case, so a group summarizes
  # its test cases instead of repeating the template for each of them.
  def execute_group(automation, test_case_ids, action, phase) do
    case Projects.get_project_by_id(automation.project_id) do
      nil ->
        Logger.warning("Automation #{automation.id} send_slack skipped: project #{automation.project_id} not found")

        :ok

      project ->
        project = Repo.preload(project, account: :slack_installation)
        listed_ids = Enum.take(test_case_ids, @max_listed_test_cases)
        identities = Tests.get_test_case_identities(project.id, listed_ids)

        case listed_ids |> Enum.map(&Map.get(identities, &1)) |> Enum.reject(&is_nil/1) do
          [] ->
            Logger.warning("Automation #{automation.id} send_slack skipped: none of the listed test cases were found")

            :ok

          listed_test_cases ->
            blocks = build_group_blocks(automation, project, listed_test_cases, length(test_case_ids), phase)
            deliver(action, project, blocks, automation)
        end
    end
  end

  # Prefer the action's encrypted webhook URL (captured the next time the
  # user picks the channel). Fall back to the account-level bot token +
  # channel id for actions configured before the webhook flow existed.
  defp deliver(%{"webhook_url_encrypted" => encrypted}, _project, blocks, automation)
       when is_binary(encrypted) and encrypted != "" do
    case Slack.decrypt_webhook_url(encrypted) do
      {:ok, webhook_url} ->
        Client.post_to_webhook(webhook_url, blocks)

      {:error, _reason} ->
        Logger.warning("Automation #{automation.id} send_slack skipped: webhook URL failed to decrypt")

        :ok
    end
  end

  defp deliver(%{"channel" => channel}, project, blocks, automation) when is_binary(channel) and channel != "" do
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

  defp deliver(_action, project, _blocks, automation) do
    Logger.warning(
      "Automation #{automation.id} send_slack skipped: missing channel/webhook configuration for project #{project.id}"
    )

    :ok
  end

  defp interpolate(template, automation, project, test_case) do
    template
    |> String.replace("{{test_case.name}}", escape_mrkdwn(test_case.name))
    |> String.replace("{{test_case.module_name}}", escape_mrkdwn(test_case.module_name))
    |> String.replace("{{test_case.suite_name}}", escape_mrkdwn(test_case.suite_name))
    |> String.replace("{{test_case.url}}", test_case_url(project, test_case))
    |> String.replace("{{automation.name}}", escape_mrkdwn(automation.name))
  end

  defp test_case_url(project, test_case) do
    "#{project_url(project)}/tests/test-cases/#{test_case.id}"
  end

  defp automation_url(project, automation) do
    "#{project_url(project)}/settings/automations/#{automation.id}"
  end

  defp project_url(project) do
    "#{Environment.app_url()}/#{project.account.name}/#{project.name}"
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

  defp build_group_blocks(automation, project, listed_test_cases, total_count, phase) do
    unlisted_count = total_count - length(listed_test_cases)

    lines =
      [group_summary(total_count, phase)] ++
        Enum.map(listed_test_cases, &group_line(&1, project)) ++
        unlisted_line(unlisted_count, automation, project, phase)

    [header_block(automation) | Enum.map(section_texts(lines), &section_block/1)]
  end

  defp group_summary(1, :trigger), do: "*1 test* matched this automation:"
  defp group_summary(count, :trigger), do: "*#{count} tests* matched this automation:"
  defp group_summary(1, :recovery), do: "*1 test* recovered:"
  defp group_summary(count, :recovery), do: "*#{count} tests* recovered:"

  defp group_line(test_case, project) do
    name = test_case.name |> truncate(@max_listed_name_length) |> escape_mrkdwn()
    module_name = test_case.module_name |> truncate(@max_listed_module_name_length) |> escape_mrkdwn()

    "• <#{test_case_url(project, test_case)}|#{name}> in `#{module_name}`"
  end

  defp unlisted_line(0, _automation, _project, _phase), do: []

  defp unlisted_line(count, automation, project, :trigger) do
    ["…and #{count} more. <#{automation_url(project, automation)}#matched-tests|View all matched tests>"]
  end

  defp unlisted_line(count, automation, project, :recovery) do
    ["…and #{count} more. <#{automation_url(project, automation)}|View automation>"]
  end

  defp truncate(nil, _max_length), do: nil

  defp truncate(value, max_length) do
    if String.length(value) > max_length, do: String.slice(value, 0, max_length - 1) <> "…", else: value
  end

  defp section_texts(lines) do
    Enum.chunk_while(
      lines,
      nil,
      fn
        line, nil ->
          {:cont, line}

        line, text ->
          if String.length(text) + String.length(line) < @max_section_length,
            do: {:cont, text <> "\n" <> line},
            else: {:cont, text, line}
      end,
      fn
        nil -> {:cont, nil}
        text -> {:cont, text, nil}
      end
    )
  end

  defp header_block(automation) do
    %{
      type: "header",
      # Header uses plain_text (Slack renders it literally), so only the
      # emoji prefix needs to be preserved; automation.name cannot leak
      # mrkdwn from this block.
      text: %{type: "plain_text", text: ":robot_face: #{automation.name || ""}"}
    }
  end

  defp section_block(text) do
    %{type: "section", text: %{type: "mrkdwn", text: text}}
  end
end
