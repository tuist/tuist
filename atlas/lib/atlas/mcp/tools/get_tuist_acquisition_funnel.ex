defmodule Atlas.MCP.Tools.GetTuistAcquisitionFunnel do
  @moduledoc "Reads Tuist's acquisition funnel, as the dashboard's Acquisition page shows it."

  use Atlas.MCP.Tool,
    name: "get_tuist_acquisition_funnel",
    schema: %{
      "type" => "object",
      "required" => ["start_date", "end_date"],
      "properties" => %{
        "start_date" => %{"type" => "string", "format" => "date", "description" => "First day (UTC), YYYY-MM-DD."},
        "end_date" => %{"type" => "string", "format" => "date", "description" => "Last day (UTC), inclusive."},
        "source" => %{
          "type" => "string",
          "description" => "Only this source, such as chatgpt.com. Omit for every source."
        },
        "campaign" => %{
          "type" => "string",
          "description" =>
            "Only this campaign (utm_campaign, exact), as on the campaign's Atlas page. Omit for every campaign."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => [
        "totals",
        "previous_totals",
        "channels",
        "sources",
        "subscriptions",
        "campaigns",
        "effectiveness",
        "series",
        "granularity"
      ],
      "properties" => %{
        "totals" => %{"type" => "object"},
        "previous_totals" => %{"type" => "object"},
        "sources" => %{"type" => "array", "items" => %{"type" => "string"}},
        "subscriptions" => %{"type" => "array", "items" => %{"type" => "object"}},
        "campaigns" => %{"type" => "array", "items" => %{"type" => "object"}},
        "effectiveness" => %{"type" => "object"},
        "channels" => %{"type" => "array", "items" => %{"type" => "object"}},
        "series" => %{"type" => "array", "items" => %{"type" => "object"}},
        "granularity" => %{"type" => "string", "enum" => ["day", "week", "month"]}
      }
    }

  alias Atlas.MCP.Tools.TuistPostgres
  alias Atlas.TuistAcquisition

  @max_days 366

  @impl EMCP.Tool
  def description do
    "Read Tuist's acquisition funnel for a date range, per source, medium, campaign and ad (utm_content): landings (visits that " <>
      "arrived on tuist.dev from a link tagged with utm_source or ref on another site or app), signups (users created in the " <>
      "range who arrived on their own, leaving out teammates who joined an existing organization, SCIM-provisioned " <>
      "users and agent accounts, by the first-touch campaign or referring site of their sign-up; an empty source means direct or " <>
      "unknown) and customers (paying accounts those signups brought: their own account, or an organization they " <>
      "administer, now on Pro or Enterprise through a subscription that started after the sign-up, each account " <>
      "counted once). Customers are a cohort of the range's signups, not conversions that happened in it. Also " <>
      "returns totals, the totals of the equally long period before (previous_totals), every source seen in the " <>
      "range (to pick a source filter), campaigns (totals per utm_campaign), effectiveness (signup_rate, " <>
      "customer_rate, landings_per_customer, median and mean days from sign-up to subscription, plan mix, active " <>
      "dates, top source and ad), subscriptions (each paying Pro or Enterprise subscription of the " <>
      "range's signups with its account, plan, status and dates and the source, campaign and ad its signup came " <>
      "from, to tie revenue to an ad; all of them, newest first), and a series bucketed by day, week or month. Pass campaign to evaluate one campaign, and compare it with " <>
      "previous_totals or another range. Read-only."
  end

  def execute(_conn, args) do
    with :ok <- TuistPostgres.ensure_available(),
         {:ok, range} <- range(args),
         {:ok, funnel} <- TuistAcquisition.funnel(range, source: source(args), campaign: campaign(args)) do
      {:ok, serialize(funnel)}
    else
      {:error, :not_configured} -> {:error, "The Tuist server is not reachable from this environment."}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _reason} -> {:error, "The Tuist server could not measure the funnel."}
    end
  end

  defp range(%{"start_date" => start_date, "end_date" => end_date})
       when is_binary(start_date) and is_binary(end_date) do
    with {:ok, start_date} <- Date.from_iso8601(start_date),
         {:ok, end_date} <- Date.from_iso8601(end_date),
         diff when diff >= 0 and diff < @max_days <- Date.diff(end_date, start_date) do
      {:ok, {start_date, end_date}}
    else
      _ -> {:error, "start_date and end_date must be YYYY-MM-DD dates, in order, at most #{@max_days} days apart."}
    end
  end

  defp range(_args), do: {:error, "start_date and end_date are required."}

  defp source(%{"source" => source}) when is_binary(source) and source != "", do: String.downcase(source)
  defp source(_args), do: nil

  defp campaign(%{"campaign" => campaign}) when is_binary(campaign) and campaign != "", do: campaign
  defp campaign(_args), do: nil

  defp json_value(%Date{} = date), do: Date.to_iso8601(date)

  defp json_value(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {to_string(key), json_value(value)} end)

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(value), do: value

  defp serialize(%{totals: totals, previous: previous, sources: sources, channels: channels} = funnel) do
    %{series: series, granularity: granularity, subscriptions: subscriptions} = funnel
    %{campaigns: campaigns, effectiveness: effectiveness} = funnel

    %{
      "totals" => Map.new(totals, fn {key, value} -> {Atom.to_string(key), value} end),
      "previous_totals" => Map.new(previous, fn {key, value} -> {Atom.to_string(key), value} end),
      "sources" => sources,
      "campaigns" => json_value(campaigns),
      "effectiveness" => json_value(effectiveness),
      "subscriptions" =>
        Enum.map(subscriptions, fn subscription ->
          Map.new(subscription, fn
            {key, %Date{} = date} -> {Atom.to_string(key), Date.to_iso8601(date)}
            {key, value} -> {Atom.to_string(key), value}
          end)
        end),
      "channels" =>
        Enum.map(channels, fn channel -> Map.new(channel, fn {key, value} -> {Atom.to_string(key), value} end) end),
      "series" =>
        [series.landings, series.signups, series.attributed_signups, series.customers]
        |> Enum.zip()
        |> Enum.map(fn {{date, landings}, {_, signups}, {_, attributed_signups}, {_, customers}} ->
          %{
            "date" => Date.to_iso8601(date),
            "landings" => landings,
            "signups" => signups,
            "attributed_signups" => attributed_signups,
            "customers" => customers
          }
        end),
      "granularity" => Atom.to_string(granularity)
    }
  end
end
