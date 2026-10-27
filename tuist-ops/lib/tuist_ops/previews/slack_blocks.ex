defmodule TuistOps.Previews.SlackBlocks do
  @moduledoc """
  Slack Block Kit cards for preview environments.
  """

  alias TuistOps.Previews.Preview

  def request_modal(previews_channel_id) do
    %{
      type: "modal",
      callback_id: "preview_request",
      title: %{type: "plain_text", text: "Preview"},
      submit: %{type: "plain_text", text: "Submit"},
      close: %{type: "plain_text", text: "Cancel"},
      private_metadata: JSON.encode!(%{previews_channel_id: previews_channel_id}),
      blocks: [
        %{
          type: "input",
          block_id: "preview_action",
          label: %{type: "plain_text", text: "Action"},
          element: %{
            type: "static_select",
            action_id: "value",
            initial_option: modal_option("Create preview", "create"),
            options: [
              modal_option("Create preview", "create"),
              modal_option("Delete preview", "delete")
            ]
          }
        },
        %{
          type: "input",
          block_id: "preview_slug",
          label: %{type: "plain_text", text: "Slug"},
          hint: %{
            type: "plain_text",
            text: "Lowercase letters, numbers, and dashes. This becomes <slug>.preview.tuist.dev."
          },
          element: %{
            type: "plain_text_input",
            action_id: "value",
            placeholder: %{type: "plain_text", text: "kura-demo"},
            max_length: 40
          }
        },
        %{
          type: "input",
          block_id: "preview_duration",
          optional: true,
          label: %{type: "plain_text", text: "Duration"},
          element: %{
            type: "static_select",
            action_id: "value",
            initial_option: modal_option("1 day", "1d"),
            options: [
              modal_option("30 minutes", "30m"),
              modal_option("1 hour", "1h"),
              modal_option("2 hours", "2h"),
              modal_option("8 hours", "8h"),
              modal_option("1 day", "1d"),
              modal_option("3 days", "3d"),
              modal_option("7 days", "7d")
            ]
          }
        },
        %{
          type: "input",
          block_id: "preview_source_kind",
          optional: true,
          label: %{type: "plain_text", text: "Source"},
          element: %{
            type: "static_select",
            action_id: "value",
            initial_option: modal_option("Workflow default", "default"),
            options: [
              modal_option("Workflow default", "default"),
              modal_option("Pull request", "pr"),
              modal_option("Commit", "sha")
            ]
          }
        },
        %{
          type: "input",
          block_id: "preview_source_value",
          optional: true,
          label: %{type: "plain_text", text: "Source value"},
          hint: %{
            type: "plain_text",
            text: "Use a pull request number or a 7-40 character commit hash."
          },
          element: %{
            type: "plain_text_input",
            action_id: "value",
            placeholder: %{type: "plain_text", text: "11348"}
          }
        },
        %{
          type: "input",
          block_id: "preview_reason",
          label: %{type: "plain_text", text: "Reason"},
          element: %{
            type: "plain_text_input",
            action_id: "value",
            multiline: true,
            placeholder: %{type: "plain_text", text: "Test Kura preview flow"}
          }
        }
      ]
    }
  end

  def provisioning(%Preview{} = preview) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview requested*
          *Requester:* <@#{preview.requester_slack_id}>
          *Preview:* `#{preview.slug}`
          *URL:* https://#{preview.host}
          *Ref:* #{format_ref(preview)}
          *TTL:* #{format_seconds(preview.ttl_seconds)}
          *Reason:* #{preview.reason}
          """
        }
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text: provisioning_context(preview)
          }
        ]
      },
      %{
        type: "actions",
        block_id: "preview_actions",
        elements: [
          %{
            type: "button",
            style: "danger",
            text: %{type: "plain_text", text: "Delete"},
            action_id: "preview_delete",
            value: preview.slug
          }
        ]
      }
    ]
  end

  def deleting(%Preview{} = preview) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview deletion requested*
          *Requester:* <@#{preview.requester_slack_id}>
          *Preview:* `#{preview.slug}`
          *Reason:* #{preview.reason}
          """
        }
      }
    ]
  end

  def deployed(%Preview{} = preview) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview deployed*
          *Requester:* <@#{preview.requester_slack_id}>
          *Preview:* `#{preview.slug}`
          *URL:* <https://#{preview.host}|https://#{preview.host}>
          *Ref:* #{format_ref(preview)}
          *TTL:* #{format_seconds(preview.ttl_seconds)}
          #{workflow_line(preview.workflow_run_url)}
          """
        }
      },
      %{
        type: "actions",
        block_id: "preview_actions",
        elements: [
          %{
            type: "button",
            style: "danger",
            text: %{type: "plain_text", text: "Delete"},
            action_id: "preview_delete",
            value: preview.slug
          }
        ]
      }
    ]
  end

  def failed(%Preview{} = preview, reason) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview request failed*
          *Requester:* <@#{preview.requester_slack_id}>
          *Preview:* `#{preview.slug}`
          *Reason:* #{preview.reason}
          #{workflow_line(preview.workflow_run_url)}
          *Error:* #{inspect(reason)}
          """
        }
      }
    ]
  end

  def workflow_run_thread(url) when is_binary(url) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: "GitHub Actions run: <#{url}|follow the deployment progress>"
        }
      }
    ]
  end

  def deployed_thread(%Preview{} = preview) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: "Preview deployment completed: <https://#{preview.host}|https://#{preview.host}>"
        }
      }
    ]
  end

  def failed_thread(%Preview{} = preview) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: failed_thread_text(preview.workflow_run_url)
        }
      }
    ]
  end

  defp format_ref(%Preview{ref_kind: nil}), do: "`workflow default`"
  defp format_ref(%Preview{ref_kind: kind, ref_value: value}), do: "`#{kind}:#{value}`"

  defp modal_option(text, value) do
    %{
      text: %{type: "plain_text", text: text},
      value: value
    }
  end

  defp provisioning_context(%Preview{} = preview) do
    case preview_expiration(preview) do
      nil ->
        "GitHub Actions is provisioning it."

      expiration ->
        "GitHub Actions is provisioning it. It expires <!date^#{DateTime.to_unix(expiration)}^{date_short_pretty} at {time}|soon>."
    end
  end

  defp preview_expiration(%Preview{ttl_seconds: ttl_seconds} = preview)
       when is_integer(ttl_seconds) do
    case preview.updated_at || preview.inserted_at do
      nil -> nil
      timestamp -> DateTime.add(timestamp, ttl_seconds, :second)
    end
  end

  defp preview_expiration(%Preview{}), do: nil

  defp workflow_line(nil), do: ""
  defp workflow_line(""), do: ""
  defp workflow_line(url), do: "*Workflow:* <#{url}|GitHub Actions run>"

  defp failed_thread_text(nil), do: "Preview deployment failed."
  defp failed_thread_text(""), do: "Preview deployment failed."
  defp failed_thread_text(url), do: "Preview deployment failed: <#{url}|GitHub Actions run>"

  defp format_seconds(nil), do: "n/a"
  defp format_seconds(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min"

  defp format_seconds(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)

    cond do
      days > 0 and hours > 0 -> "#{days}d #{hours}h"
      days > 0 -> "#{days}d"
      true -> "#{hours}h"
    end
  end
end
