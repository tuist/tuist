defmodule Atlas.Tasks.SlackNotifier do
  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Slack.API
  alias Atlas.Slack.User, as: SlackUser
  alias Atlas.Tasks.Task
  alias Atlas.Users.User

  @snooze_action_prefix "task_reminder_snooze:"
  @snooze_options [tomorrow: "Tomorrow", end_of_week: "End of week", next_week: "Next week"]

  def send(%Task{} = task, kind, opts \\ []) when kind in [:reminder, :due_date] do
    with {:ok, slack_user_id} <- slack_user_id(task.assignee, opts) do
      poster = Keyword.get(opts, :poster, &API.post_message/5)
      url = AtlasWeb.Endpoint.url() <> "/tasks"
      {heading, text} = message(kind, task)
      notification_id = notification_id(task, kind)

      blocks = [
        %{
          "type" => "section",
          "text" => %{
            "type" => "mrkdwn",
            "text" => "*#{heading}*\n#{escape(task.title)}#{account_label(task)}#{description(task)}"
          }
        },
        %{
          "type" => "actions",
          "elements" => action_elements(kind, task, url)
        }
      ]

      poster.(:company, slack_user_id, text, blocks, client_msg_id: notification_id)
    end
  end

  def snooze_action_id(option) when is_atom(option), do: @snooze_action_prefix <> Atom.to_string(option)

  def parse_snooze_action_id(@snooze_action_prefix <> option) do
    case option do
      "tomorrow" -> {:ok, :tomorrow}
      "end_of_week" -> {:ok, :end_of_week}
      "next_week" -> {:ok, :next_week}
      _other -> :error
    end
  end

  def parse_snooze_action_id(_action_id), do: :error

  defp action_elements(:reminder, %Task{id: task_id}, url) do
    snooze_buttons =
      Enum.map(@snooze_options, fn {option, label} ->
        %{
          "type" => "button",
          "text" => %{"type" => "plain_text", "text" => label},
          "action_id" => snooze_action_id(option),
          "value" => task_id
        }
      end)

    snooze_buttons ++
      [%{"type" => "button", "text" => %{"type" => "plain_text", "text" => "View tasks"}, "url" => url}]
  end

  defp action_elements(:due_date, _task, url) do
    [%{"type" => "button", "text" => %{"type" => "plain_text", "text" => "View tasks"}, "url" => url}]
  end

  defp notification_id(task, :reminder), do: "atlas-task-reminder-#{task.id}-#{task.reminder_version}"
  defp notification_id(task, :due_date), do: "atlas-task-due-#{task.id}-#{task.due_version}"

  defp message(:reminder, task), do: {"Task reminder", "Reminder: #{task.title}"}

  defp message(:due_date, task) do
    if Date.before?(task.due_on, Date.utc_today()) do
      {"Task overdue", "Overdue: #{task.title}"}
    else
      {"Task due today", "Due today: #{task.title}"}
    end
  end

  defp slack_user_id(%User{email: email}, opts) when is_binary(email) do
    resolver = Keyword.get(opts, :resolver, &API.lookup_user_by_email/2)

    case Repo.one(
           from(user in SlackUser,
             where: user.slack_app == :company and fragment("lower(?)", user.email) == ^String.downcase(email),
             where: user.is_bot == false and user.is_external == false,
             select: user.slack_user_id,
             limit: 1
           )
         ) do
      nil -> resolver.(:company, email)
      user_id -> {:ok, user_id}
    end
  end

  defp slack_user_id(_, _opts), do: {:error, :assignee_email_missing}

  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp account_label(%Task{account: %{name: name}}), do: "\nAccount: #{escape(name)}"
  defp account_label(_task), do: ""

  defp description(%Task{description: description}) when is_binary(description), do: "\n#{escape(description)}"
  defp description(_task), do: ""
end
