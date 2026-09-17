defmodule Atlas.Briefs.Notifier do
  @moduledoc false

  alias Atlas.Audit
  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.Sensitivity
  alias Atlas.Finance.Briefs.SlackRenderer
  alias Atlas.Repo
  alias Atlas.Slack.API

  require Logger

  @action_prefix "brief_item:"

  def action_id(action), do: @action_prefix <> action
  def parse_action_id(@action_prefix <> action), do: {:ok, action}
  def parse_action_id(_action_id), do: :error

  def notify(%Brief{} = brief) do
    brief = Repo.preload(brief, [:subscription, items: [:owner]], force: true)

    with :ok <- validate_sensitivity(brief),
         {:ok, delivery} <- deliver(brief) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      brief
      |> Brief.changeset(%{
        status: "posted",
        slack_channel_id: delivery.channel_id,
        slack_thread_ts: delivery.thread_ts,
        posted_at: now,
        failure_reason: nil
      })
      |> Repo.update()
      |> tap(fn
        {:ok, posted} -> audit_posted(posted)
        _result -> :ok
      end)
    else
      {:error, reason} = error ->
        mark_failed(brief, reason)
        error
    end
  end

  def build_blocks(%Brief{report: %{"kind" => "finance_pulse"}, subscription: %{domains: ["finance"]}} = brief) do
    SlackRenderer.build_blocks(brief)
  end

  def build_blocks(%Brief{} = brief) do
    if monthly_finance_recap?(brief) do
      monthly_recap_blocks(brief)
    else
      [
        %{
          "type" => "header",
          "text" => %{"type" => "plain_text", "text" => brief.headline, "emoji" => true}
        },
        %{
          "type" => "context",
          "elements" => [
            %{
              "type" => "mrkdwn",
              "text" => context_text(brief)
            }
          ]
        }
      ] ++ summary_blocks(brief) ++ item_blocks(brief) ++ footer_blocks(brief)
    end
  end

  def fallback_text(brief) do
    cond do
      monthly_finance_recap?(brief) ->
        "#{brief.headline}: #{Map.get(brief.report, "intro", brief.summary || "Monthly financial recap")}"

      finance_pulse?(brief) ->
        "#{brief.headline}: #{brief.summary}"

      true ->
        "#{brief.headline}: #{length(brief.items)} items across #{brief.subscription.domains |> Enum.join(", ")}."
    end
  end

  defp monthly_recap_blocks(brief) do
    report = brief.report

    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => brief.headline, "emoji" => true}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "mrkdwn",
            "text" => "#{format_month(brief.period_start)} | Month-end financial recap"
          }
        ]
      },
      %{
        "type" => "section",
        "text" => %{"type" => "mrkdwn", "text" => escape(Map.get(report, "intro", brief.summary || ""))}
      }
    ] ++ monthly_recap_sections(report) ++ monthly_recap_footer()
  end

  defp monthly_recap_sections(report) do
    report
    |> Map.get("sections", [])
    |> Enum.flat_map(fn section ->
      with heading when is_binary(heading) and heading != "" <- Map.get(section, "heading"),
           text when is_binary(text) and text != "" <- Map.get(section, "text") do
        [
          %{"type" => "divider"},
          %{
            "type" => "section",
            "text" => %{"type" => "mrkdwn", "text" => "*#{escape(heading)}*\n#{escape(text)}"}
          }
        ]
      else
        _invalid_section -> []
      end
    end)
  end

  defp monthly_recap_footer do
    [
      %{"type" => "divider"},
      %{
        "type" => "actions",
        "elements" => [
          %{
            "type" => "button",
            "text" => %{"type" => "plain_text", "text" => "Open finance dashboard", "emoji" => true},
            "url" => "#{AtlasWeb.Endpoint.url()}/commercial/finance",
            "style" => "primary"
          }
        ]
      }
    ]
  end

  defp deliver(%Brief{slack_thread_ts: thread_ts} = brief) when is_binary(thread_ts) do
    case API.update_message(
           slack_app(brief.subscription.slack_app),
           brief.slack_channel_id || brief.subscription.slack_channel_id,
           thread_ts,
           fallback_text(brief),
           build_blocks(brief),
           metadata: brief_metadata(brief)
         ) do
      {:ok, _response} ->
        {:ok,
         %{
           channel_id: brief.slack_channel_id || brief.subscription.slack_channel_id,
           thread_ts: thread_ts
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deliver(brief) do
    channel_id = brief.subscription.slack_channel_id

    case API.find_message_by_metadata(slack_app(brief.subscription.slack_app), channel_id, "atlas_brief", brief.id) do
      {:ok, %{"ts" => thread_ts} = message} when is_binary(thread_ts) ->
        {:ok, %{channel_id: message["channel"] || channel_id, thread_ts: thread_ts}}

      {:ok, nil} ->
        post_new(brief)

      # Reading history is an optimisation that avoids double-posting a retried
      # brief. A bot that can post without holding `channels:history`, or a
      # transient read failure, must not cost leadership the brief entirely.
      {:error, reason} ->
        Logger.warning(
          "Could not reconcile brief #{brief.id} against channel #{channel_id} " <>
            "(#{inspect(reason)}); posting without reconciliation"
        )

        post_new(brief)
    end
  end

  defp post_new(brief) do
    channel_id = brief.subscription.slack_channel_id

    case API.post_message(
           slack_app(brief.subscription.slack_app),
           channel_id,
           fallback_text(brief),
           build_blocks(brief),
           client_msg_id: brief.id,
           metadata: brief_metadata(brief)
         ) do
      {:ok, %{"ts" => thread_ts} = response} when is_binary(thread_ts) ->
        {:ok, %{channel_id: response["channel"] || channel_id, thread_ts: thread_ts}}

      {:ok, _response} ->
        {:error, :slack_brief_timestamp_missing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp brief_metadata(brief) do
    %{
      event_type: "atlas_brief",
      event_payload: %{key: brief.id}
    }
  end

  defp validate_sensitivity(brief) do
    with {:ok, ceiling} <- Sensitivity.ceiling(brief.subscription) do
      if Enum.all?(brief.items, &Sensitivity.permits?(ceiling, &1.sensitivity)),
        do: :ok,
        else: {:error, :brief_exceeds_subscription_sensitivity}
    end
  end

  defp summary_blocks(%Brief{summary: summary} = brief) when is_binary(summary) and summary != "" do
    [
      %{
        "type" => "section",
        "text" => %{"type" => "mrkdwn", "text" => "*#{summary_heading(brief)}*\n#{escape(summary)}"}
      }
    ]
  end

  defp summary_blocks(_brief), do: []

  defp item_blocks(%Brief{items: []} = brief) do
    if finance_pulse?(brief) do
      []
    else
      [
        %{
          "type" => "section",
          "text" => %{
            "type" => "mrkdwn",
            "text" => "No material changes or open loops crossed the attention threshold."
          }
        }
      ]
    end
  end

  defp item_blocks(brief) do
    if finance_pulse?(brief) do
      finance_pulse_item_blocks(brief.items)
    else
      brief.items
      |> Enum.sort_by(& &1.position)
      |> Enum.map(& &1.domain)
      |> Enum.uniq()
      |> Enum.flat_map(fn domain ->
        domain_items = Enum.filter(brief.items, &(&1.domain == domain))
        [domain_header(domain) | Enum.flat_map(domain_items, &item_block/1)]
      end)
    end
  end

  # Finance pulses are a self-contained readout, not a task queue. The brief
  # items remain durable evidence for the finance view and audit trail, while
  # Slack presents their findings as one narrative without interactive actions.
  defp finance_pulse_item_blocks(items) do
    items = Enum.sort_by(items, & &1.position)

    {concerns, follow_ups} = Enum.split_with(items, &(&1.kind != "follow_up"))

    sections = [finance_findings("What to watch", concerns), finance_findings("Suggested focus", follow_ups)]

    case Enum.reject(sections, &is_nil/1) do
      [] -> []
      sections -> [%{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => Enum.join(sections, "\n\n")}}]
    end
  end

  defp finance_findings(_heading, []), do: nil

  defp finance_findings(heading, items) do
    findings =
      Enum.map_join(items, "\n", fn item ->
        if item.kind == "follow_up" or item.title == item.detail do
          "• #{escape(item.detail)}"
        else
          "• *#{escape(item.title)}*: #{escape(item.detail)}"
        end
      end)

    "*#{heading}*\n#{findings}"
  end

  defp domain_header(domain) do
    %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => "*#{domain_label(domain)}*"}}
  end

  defp item_block(item) do
    owner = if item.owner, do: item.owner.name || item.owner.email, else: "Unowned"
    due = if item.due_at, do: format_date(item.due_at), else: "No due date"

    text =
      [
        "#{severity_prefix(item.severity)} *#{escape(item.title)}*",
        escape(item.detail),
        optional_line("Suggested next move", item.suggested_action),
        optional_line("Done when", item.completion_condition),
        "_Owner: #{escape(owner)} | Due: #{due}_",
        source_line(item.source_path)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    section = %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => text
      }
    }

    if item.status in ["open", "acknowledged"] do
      [section, actions_block(item)]
    else
      [section]
    end
  end

  defp actions_block(item) do
    %{
      "type" => "actions",
      "elements" => [
        button("Own", "claim", item.id, "primary"),
        button("Acknowledge", "acknowledge", item.id),
        button("Useful", "useful", item.id),
        button("Not useful", "not_useful", item.id),
        button("Mute 30 days", "mute", item.id)
      ]
    }
  end

  defp button(label, action, id, style \\ nil) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "action_id" => action_id(action),
      "value" => id
    }
    |> maybe_put("style", style)
  end

  defp footer_blocks(brief) do
    if finance_pulse?(brief), do: [], else: [footer_block()]
  end

  defp footer_block do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" => "Use the actions above to own, acknowledge, or tune these recommendations."
        }
      ]
    }
  end

  defp summary_heading(brief) do
    if finance_pulse?(brief), do: "Financial pulse", else: "Situation"
  end

  defp context_text(brief) do
    if finance_pulse?(brief) do
      "#{format_date(brief.period_start)} | Financial pulse"
    else
      "#{format_date(brief.period_start)} to #{format_date(DateTime.add(brief.period_end, -1, :second))} | #{length(brief.items)} items"
    end
  end

  defp format_month(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Calendar.strftime("%B %Y")
  end

  defp finance_pulse?(%Brief{subscription: %{domains: ["finance"]}}), do: true
  defp finance_pulse?(_brief), do: false

  defp monthly_finance_recap?(%Brief{cadence: "monthly", report: %{"kind" => "monthly_finance_recap"}}), do: true
  defp monthly_finance_recap?(_brief), do: false

  defp mark_failed(brief, reason) do
    attrs =
      if is_binary(brief.slack_thread_ts) do
        %{failure_reason: inspect(reason)}
      else
        %{status: "failed", failure_reason: inspect(reason)}
      end

    brief
    |> Brief.changeset(attrs)
    |> Repo.update()
  end

  defp audit_posted(brief) do
    Audit.record(
      "brief.posted",
      %{
        target_type: "brief",
        target_id: brief.id,
        target_label: brief.headline,
        metadata: %{
          "cadence" => brief.cadence,
          "channel_id" => brief.slack_channel_id,
          "thread_ts" => brief.slack_thread_ts,
          "report_kind" => Map.get(brief.report, "kind"),
          "dashboard_path" => report_dashboard_path(brief.report)
        }
      },
      interface: "worker"
    )
  end

  defp report_dashboard_path(%{"kind" => "monthly_finance_recap"}), do: "/commercial/finance"
  defp report_dashboard_path(_report), do: nil

  defp slack_app("community"), do: :community
  defp slack_app(_app), do: :company

  defp domain_label("accounts"), do: "Accounts"
  defp domain_label("outreach"), do: "Outreach"
  defp domain_label("finance"), do: "Finance"
  defp domain_label("product"), do: "Product"
  defp domain_label("company"), do: "Across the company"
  defp domain_label(domain), do: String.capitalize(domain)

  defp severity_prefix("critical"), do: ":rotating_light:"
  defp severity_prefix("warning"), do: ":warning:"
  defp severity_prefix(_severity), do: ":information_source:"

  defp format_date(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)

  defp optional_line(_label, nil), do: nil
  defp optional_line(label, value), do: "*#{label}:* #{escape(value)}"

  defp source_line("/" <> _rest = path), do: "<#{AtlasWeb.Endpoint.url()}#{path}|Open source>"

  defp source_line(path) when is_binary(path) do
    case URI.parse(path) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> "<#{path}|Open source>"
      _uri -> nil
    end
  end

  defp source_line(_path), do: nil

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
