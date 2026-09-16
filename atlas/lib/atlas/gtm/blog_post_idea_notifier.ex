defmodule Atlas.GTM.BlogPostIdeaNotifier do
  @moduledoc """
  Announces new blog post ideas to the company Slack #marketing channel with a
  rich Block Kit message. The returned thread reference is stored on the idea so
  replies in the thread can be captured back as follow-up comments.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.GTM.BlogPostIdea
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @marketing_channel_id "C0AGV3YU8ET"
  @purpose_text "New blog post idea captured in Atlas. Reply in this thread to add context."

  @doc """
  Posts the idea announcement to the company #marketing channel. Returns
  `{:ok, thread_ts}` with the new thread's timestamp, or `{:error, reason}` on
  a Slack API failure.
  """
  def announce(%BlogPostIdea{} = idea) do
    case API.post_message(@app_key, @marketing_channel_id, fallback_text(idea), build_blocks(idea)) do
      {:ok, %{"ts" => ts}} ->
        {:ok, ts}

      {:error, reason} ->
        Logger.warning("Failed to post blog post idea to Slack: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Builds the Block Kit payload used for the idea announcement.
  """
  def build_blocks(%BlogPostIdea{} = idea) do
    [
      header_block(idea),
      branding_block(),
      status_block(idea),
      description_block(idea),
      action_block(idea),
      footer_block(idea)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp header_block(%BlogPostIdea{title: title}) do
    %{
      "type" => "header",
      "text" => %{"type" => "plain_text", "text" => truncate(title, 150), "emoji" => true}
    }
  end

  defp branding_block do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "image",
          "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png",
          "alt_text" => "Atlas"
        },
        %{"type" => "mrkdwn", "text" => "*Atlas* | #{@purpose_text}"}
      ]
    }
  end

  defp status_block(%BlogPostIdea{} = idea) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "mrkdwn", "text" => "*Status:* #{status_label(idea.status)}"},
        %{"type" => "mrkdwn", "text" => "*Captured by:* #{escape_mrkdwn(captured_by(idea))}"}
      ]
    }
  end

  defp description_block(%BlogPostIdea{description: description}) when is_binary(description) and description != "" do
    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => escape_mrkdwn(description)}
    }
  end

  defp description_block(_idea), do: nil

  defp action_block(%BlogPostIdea{} = idea) do
    %{
      "type" => "actions",
      "elements" => [
        %{
          "type" => "button",
          "text" => %{"type" => "plain_text", "text" => "Open in Atlas", "emoji" => true},
          "url" => idea_url(idea),
          "style" => "primary"
        }
      ]
    }
  end

  defp footer_block(%BlogPostIdea{} = idea) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "mrkdwn", "text" => "GTM content backlog | Idea ID: #{idea.id}"}
      ]
    }
  end

  defp fallback_text(%BlogPostIdea{} = idea) do
    [
      "New blog post idea: #{idea.title}",
      "Status: #{status_label(idea.status)}",
      "Captured by: #{captured_by(idea)}",
      idea.description && "Description: #{idea.description}",
      "Open in Atlas: #{idea_url(idea)}",
      "Reply in this thread to add context. Atlas captures replies as follow-up comments on the idea."
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp idea_url(%BlogPostIdea{id: id}), do: url(~p"/gtm/content/#{id}")

  defp status_label("idea"), do: "Idea"
  defp status_label("in_progress"), do: "In progress"
  defp status_label("published"), do: "Published"
  defp status_label(status), do: to_string(status)

  defp captured_by(%BlogPostIdea{author: %{name: name}}) when is_binary(name) and name != "", do: name
  defp captured_by(%BlogPostIdea{author: %{email: email}}) when is_binary(email) and email != "", do: email
  defp captured_by(%BlogPostIdea{created_by_agent: agent}) when is_binary(agent) and agent != "", do: agent
  defp captured_by(_idea), do: "Atlas"

  defp truncate(value, max) when is_binary(value) and byte_size(value) > max do
    String.slice(value, 0, max - 1) <> "…"
  end

  defp truncate(value, _max) when is_binary(value), do: value
  defp truncate(_value, _max), do: ""

  defp escape_mrkdwn(nil), do: ""

  defp escape_mrkdwn(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_mrkdwn(value), do: value |> to_string() |> escape_mrkdwn()
end
