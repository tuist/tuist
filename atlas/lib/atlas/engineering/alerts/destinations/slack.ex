defmodule Atlas.Engineering.Alerts.Destinations.Slack do
  @moduledoc """
  Sends an alert to a Slack channel via the Atlas `:company` Slack app
  installation.

  The message is a Block Kit payload assembled to answer one question
  first: how bad is this? The header carries the tier's emoji and the
  reason; the fields row shows the numeric signals that separate
  "one-off transient" from "on fire right now" — environment, event
  count, level, and freshness (first / last seen).
  """

  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Slack.API, as: SlackAPI
  alias AtlasWeb.Endpoint

  @app_key :company

  def deliver(%Rule{} = rule, %Issue{} = issue, reason, opts \\ []) do
    environment = Keyword.get(opts, :environment)
    fallback = fallback_text(rule, issue, reason, environment)
    blocks = blocks(rule, issue, reason, environment)

    case SlackAPI.post_message(@app_key, rule.slack_channel_id, fallback, blocks) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, err}
    end
  end

  defp fallback_text(%Rule{tier: tier}, %Issue{} = issue, reason, environment) do
    env_part = if environment in [nil, ""], do: "", else: " · #{environment}"

    "#{tier_emoji(tier)} #{tier_label(tier)} · #{reason_label(reason)} · " <>
      "#{level_label(issue.level)}#{env_part} · #{single_line(issue.title)}"
  end

  defp blocks(%Rule{} = rule, %Issue{} = issue, reason, environment) do
    prefix = mention_prefix(rule.slack_mention)
    header = "#{tier_emoji(rule.tier)} #{tier_label(rule.tier)}: #{reason_label(reason)}"

    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => truncate(header, 150), "emoji" => true}
      }
    ]
    |> maybe_prepend_mention(prefix)
    |> Kernel.++([
      title_block(issue),
      severity_fields_block(issue, environment),
      %{"type" => "divider"},
      context_block(rule, issue),
      actions_block(issue)
    ])
  end

  defp maybe_prepend_mention(blocks, ""), do: blocks

  defp maybe_prepend_mention(blocks, prefix) do
    [
      %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => String.trim(prefix)}}
      | blocks
    ]
  end

  defp title_block(%Issue{} = issue) do
    url = issue_url(issue)

    subtitle =
      case culprit_line(issue) do
        nil -> ""
        line -> "\n`#{escape(line)}`"
      end

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => "*<#{url}|#{escape(truncate(single_line(issue.title), 200))}>*#{subtitle}"
      }
    }
  end

  defp severity_fields_block(%Issue{} = issue, environment) do
    %{
      "type" => "section",
      "fields" => [
        field("Level", level_field(issue.level)),
        field("Environment", environment_field(environment)),
        field("Events", format_count(issue.event_count)),
        field("Last seen", relative_time(issue.last_seen)),
        field("First seen", relative_time(issue.first_seen)),
        field("Status", status_field(issue.status))
      ]
    }
  end

  defp field(label, value), do: %{"type" => "mrkdwn", "text" => "*#{label}*\n#{value}"}

  defp context_block(%Rule{} = rule, %Issue{} = issue) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "mrkdwn", "text" => "Project: *#{escape(project_name(issue))}*"},
        %{"type" => "mrkdwn", "text" => "Rule: #{escape(rule.name)}"},
        %{"type" => "mrkdwn", "text" => "Fingerprint: `#{short_fingerprint(issue.fingerprint)}`"}
      ]
    }
  end

  defp actions_block(%Issue{} = issue) do
    %{
      "type" => "actions",
      "elements" => [
        %{
          "type" => "button",
          "text" => %{"type" => "plain_text", "text" => "Open issue", "emoji" => true},
          "url" => issue_url(issue),
          "style" => "primary"
        }
      ]
    }
  end

  defp mention_prefix(:here), do: "<!here> "
  defp mention_prefix(:channel), do: "<!channel> "
  defp mention_prefix(_none), do: ""

  defp tier_emoji(:incident), do: "🚨"
  defp tier_emoji(_attention), do: "⚠️"

  defp tier_label(:incident), do: "Incident"
  defp tier_label(_attention), do: "Attention"

  defp reason_label(:event_rate), do: "Issue crossed event rate"
  defp reason_label(:regression), do: "Regression"
  defp reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_label(reason) when is_binary(reason), do: reason
  defp reason_label(_), do: "alert"

  defp level_field(:fatal), do: "🟣 fatal"
  defp level_field(:error), do: "🔴 error"
  defp level_field(:warning), do: "🟡 warning"
  defp level_field(:info), do: "🔵 info"
  defp level_field(:debug), do: "⚪ debug"
  defp level_field(nil), do: "—"
  defp level_field(other), do: to_string(other)

  defp level_label(nil), do: "unknown"
  defp level_label(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp level_label(other), do: to_string(other)

  defp status_field(:resolved), do: "resolved"
  defp status_field(:ignored), do: "ignored"
  defp status_field(:unresolved), do: "unresolved"
  defp status_field(nil), do: "—"
  defp status_field(other), do: to_string(other)

  defp environment_field(nil), do: "—"
  defp environment_field(""), do: "—"

  defp environment_field(env) when is_binary(env) do
    if env in ~w(production prod live),
      do: "*`#{escape(env)}`*",
      else: "`#{escape(env)}`"
  end

  defp environment_field(other), do: to_string(other)

  defp format_count(nil), do: "0"
  defp format_count(n) when is_integer(n) and n >= 1_000_000, do: "#{div(n, 1_000_000)}M"
  defp format_count(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_count(n) when is_integer(n), do: Integer.to_string(n)
  defp format_count(other), do: to_string(other)

  defp relative_time(nil), do: "—"

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp culprit_line(%Issue{culprit: culprit}) when is_binary(culprit) and culprit != "" do
    truncate(single_line(culprit), 200)
  end

  defp culprit_line(_), do: nil

  defp single_line(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp single_line(other), do: to_string(other)

  defp project_name(%Issue{project: %Project{name: name}}) when is_binary(name), do: name

  defp project_name(_), do: "unknown"

  defp issue_url(%Issue{id: id}), do: Endpoint.url() <> "/engineering/errors/#{id}"

  defp short_fingerprint(fp) when is_binary(fp) and byte_size(fp) >= 8, do: String.slice(fp, 0, 8)
  defp short_fingerprint(_), do: "—"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  defp truncate(text, _max), do: to_string(text)

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
