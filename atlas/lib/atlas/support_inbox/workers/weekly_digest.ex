defmodule Atlas.SupportInbox.Workers.WeeklyDigest do
  @moduledoc """
  Posts a weekly summary of silenced support inbox activity so
  emails the classifier filed away stay visible at a glance. Each
  Monday morning the digest lands in `#support` (or
  `#support-filtered` when configured) with counts by category and
  a link back to the Atlas UI to browse the underlying threads.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {6, :days}, fields: [:worker]]

  import Ecto.Query, only: [from: 2]

  alias Atlas.Repo
  alias Atlas.Slack.API
  alias Atlas.Support.Thread
  alias AtlasWeb.Endpoint

  require Logger

  @app_key :company

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    since = DateTime.utc_now() |> DateTime.add(-7, :day)

    counts = counts_by_classification(since)
    total = counts |> Map.values() |> Enum.sum()

    if total > 0 do
      post(since, counts, total)
    else
      :ok
    end
  end

  defp counts_by_classification(since) do
    from(t in Thread,
      where: t.classified_at >= ^since and t.action_needed == false,
      group_by: t.classification,
      select: {t.classification, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp post(since, counts, total) do
    channel_id = digest_channel_id() || support_channel_id()

    case channel_id do
      nil ->
        Logger.warning("Weekly support inbox digest skipped: no #support channel configured.")
        :ok

      channel_id ->
        blocks = build_blocks(since, counts, total)
        text = "#{total} inbound emails filed silently in the last week."

        case API.post_message(@app_key, channel_id, text, blocks) do
          {:ok, _response} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp build_blocks(since, counts, total) do
    since_label = since |> DateTime.to_date() |> Date.to_iso8601()

    lines =
      counts
      |> Enum.sort_by(fn {_classification, count} -> -count end)
      |> Enum.map_join("\n", fn {classification, count} ->
        "• *#{classification_label(classification)}*: #{count}"
      end)

    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => "🗂 Weekly support inbox digest", "emoji" => true}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "mrkdwn",
            "text" => "Silenced by the classifier since *#{since_label}* · #{total} emails total."
          }
        ]
      },
      %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => lines}},
      %{
        "type" => "actions",
        "elements" => [
          %{
            "type" => "button",
            "text" => %{"type" => "plain_text", "text" => "Browse silenced", "emoji" => true},
            "url" => browse_url()
          }
        ]
      }
    ]
  end

  defp browse_url do
    # Land on the same slice the counts summarise: silenced
    # threads (action_needed=false). The support LiveView reads
    # these params via Flop.
    Endpoint.url() <> "/commercial/support?filters[0][field]=action_needed&filters[0][value]=false"
  end

  defp classification_label("support"), do: "Support"
  defp classification_label("invoice"), do: "Invoice"
  defp classification_label("vendor_notice"), do: "Vendor notice"
  defp classification_label("shipping"), do: "Shipping"
  defp classification_label("publish"), do: "Publish"
  defp classification_label("registration"), do: "Registration"
  defp classification_label("ar"), do: "Accounts receivable"
  defp classification_label("spam"), do: "Spam"
  defp classification_label("other"), do: "Other"
  defp classification_label(nil), do: "Unclassified"
  defp classification_label(other), do: to_string(other)

  defp digest_channel_id do
    :atlas
    |> Application.get_env(:support, [])
    |> Keyword.get(:slack_filtered_channel_id)
    |> presence()
  end

  defp support_channel_id do
    :atlas
    |> Application.get_env(:support, [])
    |> Keyword.get(:slack_channel_id)
    |> presence()
  end

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_), do: nil
end
