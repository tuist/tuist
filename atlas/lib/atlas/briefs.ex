defmodule Atlas.Briefs do
  @moduledoc """
  Builds domain-aware attention briefs from authoritative Atlas records.

  Briefs are durable coordination surfaces: each item keeps its domain,
  evidence, sensitivity, owner, completion condition, resolution, suppression,
  and usefulness feedback. Slack is a delivery surface, not the source of truth.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.Composer
  alias Atlas.Briefs.Config
  alias Atlas.Briefs.Notifier
  alias Atlas.Briefs.Sensitivity
  alias Atlas.Briefs.Subscription
  alias Atlas.Repo
  alias Atlas.Slack
  alias Atlas.Slack.API

  @default_page_size 25
  @max_page_size 100

  @leadership_audience_key "leadership"
  @leadership_cadences ~w(weekly monthly)
  @leadership_domains ~w(finance)
  @leadership_attention_budget 8

  def list_subscriptions(opts \\ []) do
    Subscription
    |> maybe_filter_subscription(:cadence, Keyword.get(opts, :cadence))
    |> maybe_filter_subscription(:audience_key, Keyword.get(opts, :audience_key))
    |> maybe_filter_enabled(Keyword.get(opts, :enabled))
    |> order_by([subscription], asc: subscription.audience_key, asc: subscription.cadence)
    |> Repo.all()
  end

  @doc """
  Creates the leadership subscriptions the scheduled briefs depend on.

  Cron entries alone no longer produce a brief: `ScheduleBriefs` enqueues work
  only for rows in `brief_subscriptions`. Seeds create those rows for
  development, but releases run migrations without seeds, so production would
  otherwise schedule briefs against an empty subscription list and post
  nothing at all.

  Existing rows are left untouched, so operator edits to domains, budget, or
  `enabled` survive. The configured leadership channel is fetched and tracked
  before subscriptions are created, ensuring its sharing metadata is available
  when briefs are composed.
  """
  def ensure_default_subscriptions do
    case Config.leadership_slack_channel_id() do
      nil ->
        {:error, :leadership_slack_channel_not_configured}

      channel_id ->
        with :ok <- ensure_leadership_channel(channel_id) do
          subscriptions =
            @leadership_cadences
            |> Enum.map(&ensure_leadership_subscription(&1, channel_id))
            |> Enum.reject(&is_nil/1)

          {:ok, subscriptions}
        end
    end
  end

  def get_subscription(id) when is_binary(id) do
    Repo.get_by(Subscription, id: id, enabled: true)
  end

  def get_subscription(audience_key, cadence) do
    Repo.get_by(Subscription, audience_key: audience_key, cadence: cadence, enabled: true)
  end

  def upsert_subscription(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)
    audience_key = Map.get(attrs, :audience_key) || Map.get(attrs, "audience_key")
    cadence = Map.get(attrs, :cadence) || Map.get(attrs, "cadence")

    existing = Repo.get_by(Subscription, audience_key: audience_key, cadence: cadence)
    subscription = existing || %Subscription{}

    result =
      Repo.transaction(fn ->
        with {:ok, subscription} <- subscription |> Subscription.changeset(attrs) |> Repo.insert_or_update(),
             :ok <- Sensitivity.validate_subscription(subscription) do
          subscription
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, updated} = success ->
        audit_subscription(if(existing, do: "brief_subscription.updated", else: "brief_subscription.created"), updated)
        success

      error ->
        error
    end
  end

  def list_briefs(opts \\ []) do
    page_size = opts |> Keyword.get(:page_size, @default_page_size) |> min(@max_page_size) |> max(1)
    offset = max(Keyword.get(opts, :offset, 0), 0)

    query =
      Brief
      |> maybe_filter_brief(:cadence, Keyword.get(opts, :cadence))
      |> maybe_filter_brief(:status, Keyword.get(opts, :status))
      |> maybe_filter_brief(:brief_subscription_id, Keyword.get(opts, :subscription_id))
      |> order_by([brief], desc: brief.period_start, desc: brief.id)
      |> preload(:subscription)

    Flop.run(query, %Flop{limit: page_size, offset: offset}, for: Brief)
  end

  def get_brief(id) when is_binary(id) do
    Brief
    |> preload([:subscription, items: [:owner, :resolved_by, :usefulness_by]])
    |> Repo.get(id)
  end

  def compose(%Subscription{} = subscription, opts \\ []), do: Composer.compose(subscription, opts)

  def generate_for_audience(audience_key, cadence, opts \\ []) do
    case get_subscription(audience_key, cadence) do
      nil ->
        {:error, :brief_subscription_not_configured}

      subscription ->
        with {:ok, brief} <- compose(subscription, opts) do
          if cadence == "daily" and brief.status == "immaterial" and subscription.domains != ["finance"] do
            {:ok, brief}
          else
            Notifier.notify(brief)
          end
        end
    end
  end

  defp ensure_leadership_subscription(cadence, channel_id) do
    case Repo.get_by(Subscription, audience_key: @leadership_audience_key, cadence: cadence) do
      nil -> insert_leadership_subscription(cadence, channel_id)
      subscription -> subscription
    end
  end

  defp ensure_leadership_channel(channel_id) do
    case Slack.find_channel(:company, channel_id) do
      nil ->
        with {:ok, channel} <- API.get_channel_info(:company, channel_id),
             {:ok, _tracked_channel} <-
               Audit.with_context(%{interface: "worker"}, fn ->
                 Slack.add_channel(%{
                   slack_app: :company,
                   channel_id: channel.slack_channel_id,
                   channel_name: channel.name,
                   is_shared: channel.is_shared,
                   is_ext_shared: channel.is_ext_shared
                 })
               end) do
          :ok
        end

      _channel ->
        :ok
    end
  end

  defp insert_leadership_subscription(cadence, channel_id) do
    changeset =
      %Subscription{}
      |> Subscription.changeset(%{
        label: "Leadership #{cadence}",
        audience_key: @leadership_audience_key,
        cadence: cadence,
        domains: @leadership_domains,
        slack_app: "company",
        slack_channel_id: channel_id,
        max_sensitivity: "restricted",
        attention_budget: @leadership_attention_budget,
        enabled: true
      })

    case Repo.insert(changeset) do
      {:ok, subscription} ->
        audit_subscription("brief_subscription.created", subscription)
        subscription

      {:error, _changeset} ->
        Repo.get_by(Subscription, audience_key: @leadership_audience_key, cadence: cadence)
    end
  end

  defp maybe_filter_subscription(query, _field, nil), do: query

  defp maybe_filter_subscription(query, field, value),
    do: where(query, [subscription], field(subscription, ^field) == ^value)

  defp maybe_filter_enabled(query, nil), do: query
  defp maybe_filter_enabled(query, enabled), do: where(query, [subscription], subscription.enabled == ^enabled)

  defp maybe_filter_brief(query, _field, nil), do: query
  defp maybe_filter_brief(query, field, value), do: where(query, [brief], field(brief, ^field) == ^value)

  defp audit_subscription(action, %Subscription{} = subscription) do
    Audit.record(
      action,
      %{
        target_type: "brief_subscription",
        target_id: subscription.id,
        target_label: "#{subscription.audience_key}/#{subscription.cadence}",
        metadata: %{
          "audience_key" => subscription.audience_key,
          "cadence" => subscription.cadence,
          "domains" => subscription.domains,
          "slack_channel_id" => subscription.slack_channel_id,
          "enabled" => subscription.enabled,
          "attention_budget" => subscription.attention_budget,
          "max_sensitivity" => subscription.max_sensitivity
        }
      },
      interface: "worker"
    )
  end
end
