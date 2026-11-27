defmodule Atlas.TuistAcquisition do
  @moduledoc """
  The acquisition funnel of Tuist: campaign landings, signups and paying
  customers per source and campaign.

  The Tuist server records the data itself (see `Tuist.Marketing.Attribution`
  in `server/`), and Atlas reads it through `Atlas.TuistServer`'s read-only
  Postgres and ClickHouse proxies, like `Atlas.TuistOverview`:

    * Landings come from ClickHouse `marketing_landings`: one anonymous row per
      visit that arrived on tuist.dev from a campaign link (`utm_*` or `ref`)
      on another site or app, counted on the day it landed.
    * Signups are Tuist users created in the window who arrived on their own,
      grouped by the first-touch campaign or referring site stored in
      `signup_attributions`. Users without one (direct visits, the CLI) are
      grouped under an empty source. Teammates who joined an organization that
      already existed, users an organization provisioned through SCIM, and
      Tuist's agent accounts are left out: they are seat growth inside
      existing teams, not acquisition.
    * Customers are the paying accounts those signups brought: a personal
      account, or an organization they administer, with an active or
      past-due Pro or Enterprise subscription that started after they signed
      up. An organization counts once, for the admin its subscription is
      credited to (see below). It is a cohort count, so a channel's customers
      are counted on the day the user signed up, not the day they converted.

  Landings and signups join on source, medium, campaign and ad (`utm_content`,
  the convention for telling the ads of one campaign apart). A signup whose
  visit carried no campaign but came from another site has the site as its
  source and `referral` as its medium; those have no landings, because only
  campaign links are counted on arrival.

  Subscriptions connect revenue back to the ad: every paying Pro or Enterprise
  subscription of those signups that started after the sign-up, with the
  first touch of the user who signed up (for an organization, its
  earliest-signed-up administrator from the window, preferring one with an
  attribution).
  """

  alias Atlas.Environment
  alias Atlas.TuistOverview
  alias Atlas.TuistServer

  require Logger

  # Subscription plan values of `Tuist.Billing.Subscription` (`enterprise: 1`,
  # `pro: 3`): Air and Open Source are free.
  @paid_plans [1, 3]
  @paying_statuses ["active", "past_due"]

  @metrics [:landings, :signups, :attributed_signups, :customers]

  # Landing channels read per window, at most a few hundred bytes each per
  # chart bucket: with up to 32 buckets that stays well inside the ClickHouse
  # proxy's 5 MiB result.
  @max_landing_channels 100
  @other_source "(other)"

  # Keeps the users `u` who arrived on their own. A teammate is a member of an
  # organization created before them who got that membership within a day of
  # signing up (an invite or SSO enrollment); someone who signed up alone and
  # was invited somewhere weeks later still counts. Agent accounts are the
  # `agent-<id>@agents.tuist.local` users of `Tuist.Accounts.AgentAuth`.
  @independent_user """
  u.provisioned_by_organization_id IS NULL
        AND u.email::text NOT LIKE '%@agents.tuist.local'
        AND NOT EXISTS (
          SELECT 1
          FROM users_roles ur
          JOIN roles r ON r.id = ur.role_id AND r.resource_type = 'Organization'
          JOIN organizations o ON o.id = r.resource_id
          WHERE ur.user_id = u.id
            AND o.created_at < u.created_at
            AND ur.created_at < u.created_at + interval '1 day'
        )
  """

  def metrics, do: @metrics

  @doc """
  Measures the funnel for the inclusive `{start_date, end_date}` window,
  optionally narrowed to one `:source` and one `:campaign` (`utm_campaign`).

  Returns `{:ok, %{totals: %{metric => count}, previous: %{metric => count},
  series: %{metric => [{date, count}]}, granularity: :day | :week | :month,
  channels: [channel], sources: [source]}}`. `previous` holds the totals of the
  equally long window before, and `sources` every named source in the window
  (of the `:campaign`, when given), ignoring `:source`. Each channel is `%{source, medium, campaign, content,
  landings, signups, customers}` (empty strings for missing values) sorted by
  signups, then landings. `subscriptions` lists the paying subscriptions of the
  window's signups, newest first, as `%{account, plan, status, subscribed_on,
  signed_up_on, source, medium, campaign, content}`. `campaigns` totals every
  named campaign of the narrowed rows, and `effectiveness` rates the narrowed
  funnel (see `effectiveness/1`). Without a reachable Tuist
  server it returns deterministic sample data in dev and
  `{:error, :not_configured}` elsewhere; `{:error, reason}` when a query fails.
  """
  def funnel({%Date{} = start_date, %Date{} = end_date}, opts \\ []) do
    pg_query = Keyword.get(opts, :pg_query, &TuistServer.query/2)
    ch_query = Keyword.get(opts, :ch_query, &TuistServer.clickhouse_query/2)
    configured_fun = Keyword.get(opts, :configured?, &TuistServer.configured?/0)
    source = Keyword.get(opts, :source)
    campaign = Keyword.get(opts, :campaign)

    # One read covers the window and the equally long one before it, for trends.
    previous_start = Date.add(start_date, -(Date.diff(end_date, start_date) + 1))

    data =
      cond do
        configured_fun.() ->
          with {:ok, landings} <- landings(previous_start, start_date, end_date, ch_query),
               {:ok, signups} <- signups(previous_start, end_date, pg_query),
               {:ok, subscriptions} <- subscriptions(start_date, end_date, pg_query),
               do: {:ok, landings ++ signups, subscriptions}

        Environment.dev?() ->
          rows = sample_rows(previous_start, end_date)
          {:ok, rows, sample_subscriptions(rows, start_date)}

        true ->
          {:error, :not_configured}
      end

    with {:ok, rows, subscriptions} <- data do
      {current, previous} = Enum.split_with(rows, &(Date.compare(&1.day, start_date) != :lt))

      narrow =
        &Enum.filter(&1, fn row ->
          (is_nil(source) or row.source == source) and (is_nil(campaign) or row.campaign == campaign)
        end)

      subscriptions = narrow.(subscriptions)

      {:ok,
       current
       |> narrow.()
       |> summarize(start_date, end_date)
       |> Map.merge(%{
         previous: totals(narrow.(previous)),
         sources: current |> Enum.filter(&(is_nil(campaign) or &1.campaign == campaign)) |> sources(),
         subscriptions: subscriptions
       })
       |> then(&Map.merge(&1, %{campaigns: campaigns(&1.channels), effectiveness: effectiveness(&1)}))}
    end
  end

  @doc """
  How effective the narrowed funnel was: `signup_rate` (signups that came from
  a campaign or referring site, per landing: direct and CLI signups have no
  landing to come from),
  `customer_rate` (customers per signup), `landings_per_customer`, the median
  and mean days from sign-up to subscription, the plan mix of its
  subscriptions, the first and last day with any landing or signup, and the
  source and ad that brought the most signups. Rates are nil without a
  denominator.
  """
  def effectiveness(%{totals: totals, channels: channels, subscriptions: subscriptions, series: series}) do
    days_to_subscribe =
      subscriptions
      |> Enum.filter(&(&1.subscribed_on && &1.signed_up_on))
      |> Enum.map(&max(Date.diff(&1.subscribed_on, &1.signed_up_on), 0))
      |> Enum.sort()

    active_days =
      for {date, value} <- series.landings ++ series.signups, value > 0, do: date

    %{
      signup_rate: ratio(totals.attributed_signups, totals.landings),
      customer_rate: ratio(totals.customers, totals.signups),
      landings_per_customer: ratio(totals.landings, totals.customers),
      median_days_to_subscribe: median(days_to_subscribe),
      mean_days_to_subscribe: ratio(Enum.sum(days_to_subscribe), length(days_to_subscribe)),
      plans: Enum.frequencies_by(subscriptions, & &1.plan),
      first_active_on: if(active_days != [], do: Enum.min(active_days, Date)),
      last_active_on: if(active_days != [], do: Enum.max(active_days, Date)),
      top_source: top(channels, :source),
      top_ad: top(channels, :content)
    }
  end

  defp campaigns(channels) do
    channels
    |> Enum.reject(&(&1.campaign == ""))
    |> Enum.group_by(& &1.campaign)
    |> Enum.map(fn {campaign, group} ->
      %{
        campaign: campaign,
        sources: group |> Enum.map(& &1.source) |> Enum.uniq() |> Enum.sort(),
        ads: group |> Enum.map(& &1.content) |> Enum.reject(&(&1 == "")) |> Enum.uniq() |> Enum.sort(),
        landings: sum(group, :landings),
        signups: sum(group, :signups),
        customers: sum(group, :customers)
      }
    end)
    |> Enum.sort_by(&{-&1.signups, -&1.landings, &1.campaign})
  end

  defp top(channels, field) do
    channels
    |> Enum.reject(&(Map.fetch!(&1, field) == ""))
    |> Enum.group_by(&Map.fetch!(&1, field))
    |> Enum.map(fn {value, group} -> {value, sum(group, :signups)} end)
    |> Enum.filter(fn {_value, signups} -> signups > 0 end)
    |> Enum.max_by(fn {_value, signups} -> signups end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp ratio(_count, 0), do: nil
  defp ratio(count, total), do: count / total

  defp median([]), do: nil

  defp median(sorted) do
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1,
      do: Enum.at(sorted, middle),
      else: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
  end

  defp sources(rows) do
    rows |> Enum.map(& &1.source) |> Enum.reject(&(&1 == "")) |> Enum.uniq() |> Enum.sort()
  end

  # One row holding every (bucket, channel) group, so the proxy's row cap
  # cannot cut it short: a result too large fails the query instead. Landings
  # are bucketed by the chart's granularity, on the bucket's first day inside
  # the window, and the previous window, which only feeds totals, collapses
  # onto its first day.
  defp landings(previous_start, start_date, end_date, ch_query) do
    bucket =
      case TuistOverview.granularity(start_date, end_date) do
        :day -> "toDate(inserted_at)"
        :week -> "greatest(toMonday(inserted_at), toDate({start_ts:DateTime}))"
        :month -> "greatest(toStartOfMonth(inserted_at), toDate({start_ts:DateTime}))"
      end

    # Anyone can make up a campaign link, so the number of channels is not
    # bounded by Tuist's own campaigns: past the busiest #{@max_landing_channels}, the rest
    # are counted together under the `(other)` source. That keeps the row
    # within the proxy's result size however many made-up values arrive.
    sql = """
    WITH (source, medium, campaign, content) IN (
      SELECT source, medium, campaign, content
      FROM marketing_landings
      WHERE inserted_at >= {previous_ts:DateTime} AND inserted_at < {end_ts:DateTime}
      GROUP BY source, medium, campaign, content
      ORDER BY count() DESC, source, medium, campaign, content
      LIMIT #{@max_landing_channels}
    ) AS kept
    SELECT toJSONString(groupArray(map('day', toString(day), 'source', channel_source, 'medium', channel_medium,
             'campaign', channel_campaign, 'content', channel_content, 'c', toString(c)))) AS groups
    FROM (
      SELECT if(inserted_at < {start_ts:DateTime}, toDate({previous_ts:DateTime}), #{bucket}) AS day,
             if(kept, source, '#{@other_source}') AS channel_source,
             if(kept, medium, '') AS channel_medium,
             if(kept, campaign, '') AS channel_campaign,
             if(kept, content, '') AS channel_content,
             count() AS c
      FROM marketing_landings
      WHERE inserted_at >= {previous_ts:DateTime} AND inserted_at < {end_ts:DateTime}
      GROUP BY day, channel_source, channel_medium, channel_campaign, channel_content
    )
    """

    params = %{
      "previous_ts" => "#{Date.to_iso8601(previous_start)} 00:00:00",
      "start_ts" => "#{Date.to_iso8601(start_date)} 00:00:00",
      "end_ts" => "#{Date.to_iso8601(Date.add(end_date, 1))} 00:00:00"
    }

    case ch_query.(sql, params: params, limit: 1) do
      {:ok, %{"rows" => rows}} ->
        {:ok,
         rows
         |> Enum.flat_map(&decode_json_list(&1["groups"]))
         |> Enum.map(fn group ->
           group |> channel_key() |> Map.merge(%{day: parse_date(group["day"]), landings: to_integer(group["c"])})
         end)}

      {:error, reason} ->
        Logger.warning("Tuist acquisition landings query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # One row holding every (day, channel) group as JSON: the Postgres proxy caps
  # result rows, and a year of daily channels can exceed it.
  defp signups(start_date, end_date, pg_query) do
    sql = """
    WITH signups AS (
      SELECT u.id AS user_id,
             u.created_at,
             u.created_at::date AS day,
             COALESCE(sa.source, '') AS source,
             COALESCE(sa.medium, '') AS medium,
             COALESCE(sa.campaign, '') AS campaign,
             COALESCE(sa.content, '') AS content
      FROM users u
      LEFT JOIN signup_attributions sa ON sa.user_id = u.id
      WHERE u.created_at >= '#{Date.to_iso8601(start_date)}'
        AND u.created_at < '#{Date.to_iso8601(Date.add(end_date, 1))}'
        AND #{@independent_user}
    ),
    owners AS (
      SELECT a.id AS account_id, a.user_id
      FROM accounts a
      WHERE a.user_id IN (SELECT user_id FROM signups)
      UNION ALL
      SELECT a.id, ur.user_id
      FROM users_roles ur
      JOIN roles r ON r.id = ur.role_id AND r.resource_type = 'Organization' AND r.name = 'admin'
      JOIN accounts a ON a.organization_id = r.resource_id
      WHERE ur.user_id IN (SELECT user_id FROM signups)
    ),
    -- Each paying account once, credited like its subscriptions: to the
    -- earliest signup of the window behind it, preferring an attributed one,
    -- and only when it started paying after that signup.
    customers AS (
      SELECT DISTINCT ON (o.account_id) o.account_id, o.user_id
      FROM owners o
      JOIN signups s ON s.user_id = o.user_id
      JOIN subscriptions sub ON sub.account_id = o.account_id
        AND sub.plan IN (#{Enum.join(@paid_plans, ", ")})
        AND sub.status IN (#{Enum.map_join(@paying_statuses, ", ", &"'#{&1}'")})
        AND sub.inserted_at >= s.created_at
      ORDER BY o.account_id, s.source = '', s.created_at
    ),
    customers_per_user AS (
      SELECT user_id, count(*) AS customers FROM customers GROUP BY user_id
    ),
    grouped AS (
      SELECT s.day, s.source, s.medium, s.campaign, s.content,
             count(*) AS signups,
             COALESCE(sum(c.customers), 0) AS customers
      FROM signups s
      LEFT JOIN customers_per_user c ON c.user_id = s.user_id
      GROUP BY s.day, s.source, s.medium, s.campaign, s.content
    )
    SELECT COALESCE((SELECT json_agg(row_to_json(grouped)) FROM grouped), '[]') AS groups
    """

    case pg_query.(sql, limit: 1) do
      {:ok, %{"rows" => [row | _]}} ->
        {:ok,
         row["groups"]
         |> decode_json_list()
         |> Enum.map(fn group ->
           group
           |> channel_key()
           |> Map.merge(%{
             day: parse_date(group["day"]),
             signups: to_integer(group["signups"]),
             customers: to_integer(group["customers"])
           })
         end)}

      {:ok, %{"rows" => []}} ->
        {:ok, []}

      {:error, reason} ->
        Logger.warning("Tuist acquisition signups query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Every paying subscription of the window's signups, so that narrowing and
  # effectiveness see them all, each with the first touch
  # of the signup behind it. An organization goes to its earliest-signed-up
  # administrator from the window, preferring one with an attribution.
  defp subscriptions(start_date, end_date, pg_query) do
    sql = """
    WITH signups AS (
      SELECT u.id AS user_id, u.created_at FROM users u
      WHERE u.created_at >= '#{Date.to_iso8601(start_date)}'
        AND u.created_at < '#{Date.to_iso8601(Date.add(end_date, 1))}'
        AND #{@independent_user}
    ),
    owners AS (
      SELECT a.id AS account_id, a.name AS account, a.user_id
      FROM accounts a JOIN signups s ON s.user_id = a.user_id
      UNION ALL
      SELECT a.id, a.name, ur.user_id
      FROM users_roles ur
      JOIN signups s ON s.user_id = ur.user_id
      JOIN roles r ON r.id = ur.role_id AND r.resource_type = 'Organization' AND r.name = 'admin'
      JOIN accounts a ON a.organization_id = r.resource_id
    ),
    rows AS (
      SELECT DISTINCT ON (sub.id)
             o.account,
             CASE sub.plan WHEN 1 THEN 'enterprise' ELSE 'pro' END AS plan,
             sub.status,
             sub.inserted_at::date AS subscribed_on,
             s.created_at::date AS signed_up_on,
             COALESCE(sa.source, '') AS source,
             COALESCE(sa.medium, '') AS medium,
             COALESCE(sa.campaign, '') AS campaign,
             COALESCE(sa.content, '') AS content
      FROM subscriptions sub
      JOIN owners o ON o.account_id = sub.account_id
      JOIN signups s ON s.user_id = o.user_id
      LEFT JOIN signup_attributions sa ON sa.user_id = o.user_id
      WHERE sub.plan IN (#{Enum.join(@paid_plans, ", ")})
        AND sub.status IN (#{Enum.map_join(@paying_statuses, ", ", &"'#{&1}'")})
        AND sub.inserted_at >= s.created_at
      ORDER BY sub.id, sa.user_id IS NULL, s.created_at
    )
    SELECT COALESCE((SELECT json_agg(r ORDER BY r.subscribed_on DESC, r.account) FROM rows r), '[]')
      AS subscriptions
    """

    case pg_query.(sql, limit: 1) do
      {:ok, %{"rows" => [row | _]}} ->
        {:ok,
         row["subscriptions"]
         |> decode_json_list()
         |> Enum.map(fn subscription ->
           subscription
           |> channel_key()
           |> Map.merge(%{
             account: to_string(subscription["account"]),
             plan: to_string(subscription["plan"]),
             status: to_string(subscription["status"]),
             subscribed_on: parse_date(subscription["subscribed_on"]),
             signed_up_on: parse_date(subscription["signed_up_on"])
           })
         end)}

      {:ok, %{"rows" => []}} ->
        {:ok, []}

      {:error, reason} ->
        Logger.warning("Tuist acquisition subscriptions query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Deterministic sample channels so dev renders with real-looking numbers:
  # {source, medium, campaign, ad, daily landings, signups per landing, customers per signup}.
  @sample_channels [
    {"chatgpt.com", "", "", "", 38, 0.045, 0.12},
    {"newsletter", "email", "2026-11", "", 12, 0.06, 0.15},
    {"linkedin", "paid_social", "launch-week", "carousel-a", 14, 0.05, 0.2},
    {"linkedin", "paid_social", "launch-week", "video-b", 9, 0.09, 0.25},
    {"google", "cpc", "brand", "search-ad-1", 11, 0.08, 0.25},
    {"producthunt", "launch", "registry", "", 9, 0.05, 0.1},
    {"news.ycombinator.com", "referral", "", "", 0, 0.0, 0.1},
    {"github.com", "referral", "", "", 0, 0.0, 0.2},
    {"", "", "", "", 0, 0.0, 0.07}
  ]
  @sample_accounts ~w(acme-mobile northwind pixelforge orbital-labs bluefin tidewater-app lumen-health
    harbor-bank quill-studio fernway kitepay solstice-games marlow-retail cobalt-io drift-travel)
  @sample_referral_signups %{"news.ycombinator.com" => 0.6, "github.com" => 1.4, "" => 7.5}

  defp sample_rows(start_date, end_date) do
    for day <- Date.range(start_date, end_date),
        {source, medium, campaign, content, daily_landings, signup_rate, customer_rate} <- @sample_channels do
      noise = fn salt -> 0.6 + :erlang.phash2({day, source, content, salt}, 1000) / 1250 end
      landings = round(daily_landings * noise.(:landings))

      signups =
        case Map.fetch(@sample_referral_signups, source) do
          {:ok, daily} -> round(daily * noise.(:signups))
          :error -> round(landings * signup_rate * noise.(:signups))
        end

      customers =
        if :erlang.phash2({day, source, content, :customers}, 1000) / 1000 < customer_rate * signups, do: 1, else: 0

      %{
        day: day,
        source: source,
        medium: medium,
        campaign: campaign,
        content: content,
        landings: landings,
        signups: signups,
        customers: min(customers, signups)
      }
    end
  end

  defp sample_subscriptions(rows, start_date) do
    rows
    |> Enum.filter(&(&1.customers > 0 and Date.compare(&1.day, start_date) != :lt))
    |> Enum.map(fn row ->
      hash = :erlang.phash2({row.day, row.source, row.content})

      row
      |> Map.take([:source, :medium, :campaign, :content])
      |> Map.merge(%{
        account: Enum.at(@sample_accounts, rem(hash, length(@sample_accounts))),
        plan: if(rem(hash, 7) == 0, do: "enterprise", else: "pro"),
        status: if(rem(hash, 11) == 0, do: "past_due", else: "active"),
        signed_up_on: row.day,
        subscribed_on: Date.utc_today() |> Date.diff(row.day) |> min(rem(hash, 9)) |> then(&Date.add(row.day, &1))
      })
    end)
    |> Enum.sort_by(&{&1.subscribed_on, &1.account}, fn {a_date, a}, {b_date, b} ->
      Date.after?(a_date, b_date) or (a_date == b_date and a <= b)
    end)
  end

  defp summarize(rows, start_date, end_date) do
    granularity = TuistOverview.granularity(start_date, end_date)

    channels =
      rows
      |> Enum.group_by(&Map.take(&1, [:source, :medium, :campaign, :content]))
      |> Enum.map(fn {key, group} ->
        Map.merge(key, %{
          landings: sum(group, :landings),
          signups: sum(group, :signups),
          customers: sum(group, :customers)
        })
      end)
      |> Enum.sort_by(&{-&1.signups, -&1.landings, &1.source, &1.campaign, &1.content})

    attributed = Enum.filter(rows, &(&1.source != ""))

    %{
      granularity: granularity,
      channels: channels,
      totals: totals(rows),
      series: %{
        landings: series(rows, :landings, start_date, end_date, granularity),
        signups: series(rows, :signups, start_date, end_date, granularity),
        attributed_signups: series(attributed, :signups, start_date, end_date, granularity),
        customers: series(rows, :customers, start_date, end_date, granularity)
      }
    }
  end

  defp totals(rows) do
    %{
      landings: sum(rows, :landings),
      signups: sum(rows, :signups),
      attributed_signups: rows |> Enum.filter(&(&1.source != "")) |> sum(:signups),
      customers: sum(rows, :customers)
    }
  end

  # Every bucket of the window, keyed by its first day inside the window, as
  # in `Atlas.TuistOverview`.
  defp series(rows, field, start_date, end_date, granularity) do
    by_day =
      Enum.reduce(rows, %{}, fn row, acc ->
        Map.update(acc, row.day, Map.get(row, field, 0), &(&1 + Map.get(row, field, 0)))
      end)

    start_date
    |> Date.range(end_date)
    |> Enum.chunk_by(&bucket_start(&1, granularity))
    |> Enum.map(fn [first | _] = days -> {first, Enum.reduce(days, 0, &(Map.get(by_day, &1, 0) + &2))} end)
  end

  defp bucket_start(day, :day), do: day
  defp bucket_start(day, :week), do: Date.beginning_of_week(day)
  defp bucket_start(day, :month), do: Date.beginning_of_month(day)

  defp sum(rows, field), do: Enum.reduce(rows, 0, &(Map.get(&1, field, 0) + &2))

  defp channel_key(row) do
    %{
      source: to_string(row["source"] || ""),
      medium: to_string(row["medium"] || ""),
      campaign: to_string(row["campaign"] || ""),
      content: to_string(row["content"] || "")
    }
  end

  defp decode_json_list(list) when is_list(list), do: list

  defp decode_json_list(binary) when is_binary(binary) do
    case JSON.decode(binary) do
      {:ok, list} when is_list(list) -> list
      _other -> []
    end
  end

  defp decode_json_list(_other), do: []

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> 0
    end
  end

  defp to_integer(_value), do: 0
end
