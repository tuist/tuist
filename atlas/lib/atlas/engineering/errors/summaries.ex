defmodule Atlas.Engineering.Errors.Summaries do
  @moduledoc """
  Builds and delivers scheduled Slack summaries of recently observed,
  unresolved error issues.

  Each reporting period has one durable run. Generated output is stored before
  delivery, so a Slack retry never invokes the model again. When a later period
  has an identical bounded input snapshot, the stored output is reused.

  Ported from `Hive.Errors.Summaries`. The prompt is delegated to
  `Atlas.Engineering.Errors.Agents.SummaryAgent`; delivery goes through
  `Atlas.Slack.API.post_message/5` under the `:company` app key.
  """

  import Ecto.Query

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Agents.SummaryAgent
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Errors.SummaryRun
  alias Atlas.Engineering.Errors.SummarySettings
  alias Atlas.LLMs.Errors, as: LLMErrors
  alias Atlas.Repo
  alias Atlas.Slack.API, as: SlackAPI
  alias AtlasWeb.Endpoint

  @settings_id "singleton"
  @app_key :company
  @claim_timeout_seconds 300
  @durable_failure_reasons ~w(
    llm_credit_limit
    llm_invalid_credentials
    llm_provider_rejected_request
    llm_provider_account_suspended
  )
  @initial_window_seconds 86_400
  @max_issues 50

  def load_settings do
    case Repo.get(SummarySettings, @settings_id) do
      nil -> %SummarySettings{id: @settings_id}
      %SummarySettings{} = settings -> settings
    end
  end

  def upsert_settings(attrs) do
    settings = load_settings()

    settings
    |> SummarySettings.changeset(Map.put(attrs, "id", @settings_id))
    |> Repo.insert_or_update()
  end

  def config do
    settings = load_settings()

    %{
      enabled: settings.enabled,
      schedule: settings.schedule,
      slack_channel_id: settings.slack_channel_id
    }
  end

  def reconcile(opts \\ []) do
    scheduled_for =
      opts
      |> Keyword.get(:scheduled_for, DateTime.utc_now())
      |> DateTime.truncate(:second)

    conf = Keyword.get_lazy(opts, :config, &config/0)

    if due?(scheduled_for, conf) do
      run(Keyword.merge(opts, config: conf, scheduled_for: scheduled_for))
    else
      {:ok, nil, if(conf.enabled, do: :not_due, else: :disabled)}
    end
  end

  def due?(_scheduled_for, %{enabled: false}), do: false

  def due?(%DateTime{} = scheduled_for, %{enabled: true, schedule: schedule}) do
    case Oban.Plugins.Cron.parse(schedule) do
      {:ok, expression} -> Oban.Cron.Expression.now?(expression, scheduled_for)
      {:error, _error} -> false
    end
  end

  def run(opts \\ []) do
    conf = Keyword.get_lazy(opts, :config, &config/0)

    if conf.enabled do
      scheduled_for =
        opts
        |> Keyword.get(:scheduled_for, DateTime.utc_now())
        |> DateTime.truncate(:second)

      window_end = scheduled_for
      window_start = previous_completed_window_end(window_end)
      {issues, issue_count} = recent_unresolved_issues(window_start, window_end)
      input = build_input(issues, issue_count)
      fingerprint = fingerprint(input)

      attrs = %{
        scheduled_for: scheduled_for,
        window_start: window_start,
        window_end: window_end,
        input_fingerprint: fingerprint,
        issue_ids: Enum.map(issues, & &1.id),
        issue_count: issue_count,
        status: :generating,
        slack_channel_id: conf.slack_channel_id
      }

      with {:claimed, run} <- claim(attrs, opts),
           {:ok, run, outcome} <- generate_or_reuse(run, input, issues, opts),
           {:ok, run, outcome} <- maybe_deliver(run, issues, outcome, opts) do
        {:ok, run, outcome}
      else
        {:existing, run} -> resume(run, opts)
        {:busy, run} -> {:ok, run, :busy}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, nil, :disabled}
    end
  end

  defp previous_completed_window_end(window_end) do
    SummaryRun
    |> where([run], run.status in [:delivered, :empty])
    |> where([run], run.window_end < ^window_end)
    |> order_by([run], desc: run.window_end)
    |> select([run], run.window_end)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> DateTime.add(window_end, -@initial_window_seconds, :second)
      previous -> previous
    end
  end

  defp recent_unresolved_issues(window_start, window_end) do
    base =
      Issue
      |> where([issue], issue.status == :unresolved)
      |> where([issue], issue.last_seen >= ^window_start and issue.last_seen < ^window_end)

    count = Repo.aggregate(base, :count, :id)

    issues =
      base
      |> order_by(
        [issue],
        asc:
          fragment(
            "CASE ?::text WHEN 'fatal' THEN 0 WHEN 'error' THEN 1 WHEN 'warning' THEN 2 WHEN 'info' THEN 3 ELSE 4 END",
            issue.level
          ),
        desc: issue.event_count,
        desc: issue.last_seen
      )
      |> limit(@max_issues)
      |> preload(:project)
      |> Repo.all()

    {issues, count}
  end

  defp build_input(issues, issue_count) do
    %{
      "issues" => Enum.map(issues, &issue_input/1),
      "omitted_issue_count" => max(issue_count - length(issues), 0)
    }
  end

  defp issue_input(issue) do
    %{
      "id" => issue.id,
      "project" => issue_project_name(issue),
      "title" => truncate(issue.title, 240),
      "culprit" => truncate(issue.culprit || "", 240),
      "level" => to_string(issue.level),
      "event_count" => issue.event_count,
      "first_seen" => DateTime.to_iso8601(issue.first_seen),
      "last_seen" => DateTime.to_iso8601(issue.last_seen)
    }
  end

  defp fingerprint(input) do
    :sha256
    |> :crypto.hash(JSON.encode!(input))
    |> Base.encode16(case: :lower)
  end

  defp claim(attrs, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %SummaryRun{}
    |> SummaryRun.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, run} ->
        {:claimed, run}

      {:error, changeset} ->
        if changeset.errors[:scheduled_for] do
          reclaim_existing(attrs.scheduled_for, now, Keyword.get(opts, :retry?, false))
        else
          {:error, changeset}
        end
    end
  end

  defp reclaim_existing(scheduled_for, now, retry?) do
    Repo.transaction(fn ->
      run =
        SummaryRun
        |> where([run], run.scheduled_for == ^scheduled_for)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      existing_run_result(run, now, retry?)
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp existing_run_result(%SummaryRun{status: status} = run, _now, _retry?)
       when status in [:delivered, :empty, :generated], do: {:existing, run}

  defp existing_run_result(%SummaryRun{status: :failed} = run, _now, true), do: reclaim(run)

  defp existing_run_result(%SummaryRun{status: :failed} = run, _now, false), do: {:existing, run}

  defp existing_run_result(run, now, _retry?) do
    if stale_claim?(run, now), do: reclaim(run), else: {:busy, run}
  end

  defp stale_claim?(%SummaryRun{status: :generating, updated_at: updated_at}, now) do
    DateTime.diff(now, updated_at, :second) >= @claim_timeout_seconds
  end

  defp stale_claim?(_run, _now), do: false

  defp reclaim(run) do
    case update_run(run, %{status: :generating, failure_reason: nil}) do
      {:ok, run} -> {:claimed, run}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp generate_or_reuse(run, _input, [], _opts) do
    case update_run(run, %{status: :empty}) do
      {:ok, run} -> {:ok, run, :empty}
      error -> error
    end
  end

  defp generate_or_reuse(run, input, issues, opts) do
    run.input_fingerprint
    |> reusable_run()
    |> reuse_or_generate(run, input, issues, opts)
  end

  defp reuse_or_generate(%SummaryRun{status: :failed} = previous, run, _input, _issues, _opts) do
    case update_run(run, %{status: :failed, failure_reason: previous.failure_reason}) do
      {:ok, run} -> {:ok, run, :failed}
      error -> error
    end
  end

  defp reuse_or_generate(%SummaryRun{} = previous, run, _input, _issues, _opts),
    do: persist_generated(run, previous.summary, previous.attention)

  defp reuse_or_generate(nil, run, input, issues, opts) do
    runner = Keyword.get(opts, :runner, &SummaryAgent.summarize/1)

    input
    |> runner.()
    |> handle_generated_output(run, issues)
  end

  defp handle_generated_output({:ok, output}, run, issues) do
    case normalize_output(output, issues) do
      {:ok, summary, attention} ->
        persist_generated(run, summary, attention)

      {:error, reason} ->
        mark_failed(run, reason)
        {:error, reason}
    end
  end

  defp handle_generated_output({:error, reason}, run, _issues) do
    mark_failed(run, reason)
    {:error, reason}
  end

  defp reusable_run(fingerprint) do
    SummaryRun
    |> where([run], run.input_fingerprint == ^fingerprint)
    |> where(
      [run],
      (run.status in [:generated, :delivered] and not is_nil(run.summary)) or
        (run.status == :failed and run.failure_reason in ^@durable_failure_reasons)
    )
    |> order_by([run], desc: run.generated_at)
    |> limit(1)
    |> Repo.one()
  end

  defp normalize_output(output, issues) when is_map(output) do
    summary = output |> value(:summary) |> normalize_text(3_000)
    allowed_ids = MapSet.new(issues, & &1.id)

    attention =
      output
      |> value(:attention)
      |> List.wrap()
      |> Enum.flat_map(&normalize_attention(&1, allowed_ids))
      |> Enum.uniq_by(& &1["issue_id"])
      |> Enum.take(5)

    if summary == "", do: {:error, :invalid_error_summary}, else: {:ok, summary, attention}
  end

  defp normalize_output(_output, _issues), do: {:error, :invalid_error_summary}

  defp normalize_attention(item, allowed_ids) when is_map(item) do
    issue_id = value(item, :issue_id)
    reason = item |> value(:reason) |> normalize_text(240)

    if is_binary(issue_id) and MapSet.member?(allowed_ids, issue_id) and reason != "" do
      [%{"issue_id" => issue_id, "reason" => reason}]
    else
      []
    end
  end

  defp normalize_attention(_item, _allowed_ids), do: []

  defp persist_generated(run, summary, attention) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case update_run(run, %{
           status: :generated,
           summary: summary,
           attention: attention,
           generated_at: now,
           failure_reason: nil
         }) do
      {:ok, run} -> {:ok, run, :generated}
      error -> error
    end
  end

  defp maybe_deliver(run, _issues, :empty, _opts), do: {:ok, run, :empty}
  defp maybe_deliver(run, _issues, :failed, _opts), do: {:ok, run, :failed}

  defp maybe_deliver(run, issues, :generated, opts) do
    poster = Keyword.get(opts, :poster, &SlackAPI.post_message/5)

    payload = slack_payload(run, issues)

    case poster.(@app_key, run.slack_channel_id, payload.text, payload.blocks, []) do
      {:ok, response} ->
        update_run(run, %{
          status: :delivered,
          slack_message_ts: response["ts"],
          delivered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> case do
          {:ok, delivered} -> {:ok, delivered, :delivered}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resume(%SummaryRun{status: :generated} = run, opts),
    do: maybe_deliver(run, issues_by_ids(run.issue_ids), :generated, opts)

  defp resume(%SummaryRun{status: :delivered} = run, _opts), do: {:ok, run, :existing}
  defp resume(%SummaryRun{status: :empty} = run, _opts), do: {:ok, run, :empty}
  defp resume(%SummaryRun{} = run, _opts), do: {:ok, run, :existing}

  defp issues_by_ids([]), do: []

  defp issues_by_ids(ids) do
    Issue
    |> where([issue], issue.id in ^ids)
    |> preload(:project)
    |> Repo.all()
  end

  defp slack_payload(run, issues) do
    issue_by_id = Map.new(issues, &{&1.id, &1})
    attention_issue_ids = attention_issue_ids(run.attention)

    impacted_by_issue =
      Errors.impacted_accounts_by_issue_ids(attention_issue_ids, limit_per_issue: 3)

    attention_blocks = attention_blocks(run.attention, issue_by_id, impacted_by_issue)

    blocks = [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => "Error summary", "emoji" => true}
      },
      %{
        "type" => "section",
        "text" => %{"type" => "mrkdwn", "text" => run.summary |> slack_safe() |> truncate(2_900)}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "mrkdwn",
            "text" =>
              "*#{run.issue_count} unresolved issue(s)* observed from " <>
                "#{format_time(run.window_start)} to #{format_time(run.window_end)} " <>
                "Coordinated Universal Time"
          }
        ]
      }
    ]

    blocks =
      if attention_blocks == [] do
        blocks
      else
        blocks ++
          [
            %{"type" => "divider"},
            %{
              "type" => "section",
              "text" => %{"type" => "mrkdwn", "text" => "*Requires special attention*"}
            }
          ] ++ attention_blocks
      end

    %{
      text: "Error summary: #{run.issue_count} unresolved issue(s) observed",
      blocks: blocks
    }
  end

  defp attention_issue_ids(items) do
    items
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"issue_id" => id} when is_binary(id) -> [id]
      _ -> []
    end)
  end

  defp attention_blocks(items, issue_by_id, impacted_by_issue) do
    items
    |> List.wrap()
    |> Enum.flat_map(fn item ->
      case issue_by_id[item["issue_id"]] do
        %Issue{} = issue ->
          url = Endpoint.url() <> "/engineering/errors/" <> issue.id
          impacted = Map.get(impacted_by_issue, issue.id, [])

          [
            %{
              "type" => "section",
              "text" => %{
                "type" => "mrkdwn",
                "text" =>
                  "*<#{url}|#{issue.title |> slack_safe() |> truncate(180)}>*\n" <>
                    (item["reason"] |> slack_safe() |> truncate(240))
              }
            },
            %{
              "type" => "context",
              "elements" => [
                context_element("Project", issue_project_name(issue)),
                context_element("Level", issue.level),
                context_element("Events", issue.event_count)
              ]
            }
          ] ++ impacted_accounts_block(impacted)

        nil ->
          []
      end
    end)
  end

  # A Slack "context" block accepts up to 10 elements and each image
  # element renders inline next to text — perfect for a compact row
  # like `[icon] Acme (enterprise, 42 events)`.
  defp impacted_accounts_block([]), do: []

  defp impacted_accounts_block(rows) do
    elements =
      rows
      |> Enum.flat_map(fn row ->
        image = account_image_element(row.account)
        text = account_text_element(row)

        Enum.reject([image, text], &is_nil/1)
      end)

    if elements == [] do
      []
    else
      [
        %{
          "type" => "context",
          "elements" => [%{"type" => "mrkdwn", "text" => "*Impacted accounts:*"} | elements]
        }
      ]
    end
  end

  defp account_image_element(%{primary_domain: domain} = _account) when is_binary(domain) and byte_size(domain) > 0 do
    normalised =
      domain
      |> String.replace(~r|^https?://|i, "")
      |> String.trim_trailing("/")

    %{
      "type" => "image",
      "image_url" => "https://www.google.com/s2/favicons?domain=" <> URI.encode(normalised) <> "&sz=64",
      "alt_text" => "favicon"
    }
  end

  defp account_image_element(_), do: nil

  defp account_text_element(row) do
    name = row.account.name |> slack_safe() |> truncate(60)
    tier = row.account.plan_tier
    prefix = if tier == "enterprise", do: ":star: ", else: ""

    tier_part =
      case tier do
        nil -> ""
        "" -> ""
        other -> " (#{other})"
      end

    %{
      "type" => "mrkdwn",
      "text" => "#{prefix}*#{name}*#{tier_part} · #{row.event_count} events"
    }
  end

  defp context_element(label, value) do
    %{"type" => "mrkdwn", "text" => "*#{label}:* #{value |> slack_safe() |> truncate(120)}"}
  end

  defp issue_project_name(%Issue{project: %{name: name}}) when is_binary(name), do: name
  defp issue_project_name(_issue), do: "Unknown project"

  defp update_run(run, attrs), do: run |> SummaryRun.changeset(attrs) |> Repo.update()

  defp mark_failed(run, reason) do
    failure_reason =
      case LLMErrors.hard_failure_reason(reason) do
        nil -> inspect(reason, limit: 5, printable_limit: 300)
        durable_reason -> to_string(durable_reason)
      end

    update_run(run, %{
      status: :failed,
      failure_reason: truncate(failure_reason, 500)
    })
  end

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp normalize_text(value, length) when is_binary(value) do
    value
    |> String.replace(" — ", ": ")
    |> String.replace("—", "-")
    |> String.trim()
    |> truncate(length)
  end

  defp normalize_text(_value, _length), do: ""

  defp truncate(nil, _length), do: ""

  defp truncate(value, length) when is_binary(value) do
    if String.length(value) > length,
      do: String.slice(value, 0, length - 3) <> "...",
      else: value
  end

  defp truncate(value, length), do: value |> to_string() |> truncate(length)

  defp slack_safe(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
