defmodule Atlas.Support.Workers.PostNotification do
  @moduledoc false

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args]]

  alias Atlas.Audit
  alias Atlas.Support
  alias Atlas.Support.Notifier
  alias Atlas.Users

  require Logger

  @events %{
    "inbound_received" => :inbound_received,
    "chat_received" => :chat_received,
    "reply_delivered" => :reply_delivered,
    "note_added" => :note_added,
    "status_changed" => :status_changed,
    "assigned" => :assigned
  }
  @event_values Map.values(@events)

  def enqueue(event, thread_id, opts \\ []) when event in @event_values and is_binary(thread_id) do
    %{
      "event" => Atom.to_string(event),
      "thread_id" => thread_id,
      "notification_id" => Ecto.UUID.generate()
    }
    |> maybe_put("message_id", opts[:message_id])
    |> maybe_put("actor_id", opts[:actor_id])
    |> maybe_put("status", opts[:status])
    |> maybe_put("assignee_id", opts[:assignee_id])
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Audit.with_context(%{interface: "worker"}, fn ->
      with {:ok, event} <- event(args["event"]),
           thread when not is_nil(thread) <- Support.get_thread(args["thread_id"]),
           {:ok, delivery} <- Notifier.notify(thread, Atom.to_string(event), notifier_opts(thread, event, args)) do
        audit_notification(thread, event, args, delivery)
        :ok
      else
        nil ->
          {:cancel, :support_thread_not_found}

        {:error, :missing_support_slack_channel_id} = error ->
          Logger.warning("Support Slack notification was skipped because no #support channel is configured")
          {:cancel, elem(error, 1)}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp event(event) when is_binary(event) do
    case Map.fetch(@events, event) do
      {:ok, event} -> {:ok, event}
      :error -> {:error, :invalid_support_notification_event}
    end
  end

  defp event(_event), do: {:error, :invalid_support_notification_event}

  defp notifier_opts(thread, event, args) do
    [
      notification_id: args["notification_id"],
      message: message(thread, args["message_id"]),
      actor: user(args["actor_id"]),
      status: args["status"],
      assignee: assignee(thread, args["assignee_id"])
    ]
    |> keep_required(event)
  end

  defp keep_required(opts, :status_changed), do: Keyword.update!(opts, :status, &(&1 || "open"))
  defp keep_required(opts, :assigned), do: Keyword.update!(opts, :assignee, &(&1 || Keyword.fetch!(opts, :actor)))
  defp keep_required(opts, _event), do: opts

  defp message(thread, message_id) when is_binary(message_id), do: Enum.find(thread.messages, &(&1.id == message_id))
  defp message(_thread, _message_id), do: nil

  defp user(user_id) when is_binary(user_id), do: Users.get_user(user_id)
  defp user(_user_id), do: nil

  defp assignee(thread, assignee_id) when is_binary(assignee_id), do: user(assignee_id) || thread.owner
  defp assignee(thread, _assignee_id), do: thread.owner

  defp audit_notification(thread, event, args, delivery) do
    Audit.record("support.notification_posted", %{
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/commercial/support/#{thread.id}",
        "event" => Atom.to_string(event),
        "message_id" => args["message_id"],
        "slack_channel_id" => delivery.channel_id,
        "slack_message_ts" => delivery.ts
      }
    })
  end

  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
