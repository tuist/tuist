defmodule AtlasWeb.AccountLive.FeatureUsageView do
  @moduledoc false

  alias Atlas.Accounts.Account
  alias Atlas.FeatureUsage
  alias Atlas.FeatureUsage.Catalog

  @doc """
  Build the feature-usage view model for an account: one row per feature with the
  latest snapshot (or a "not tracked" placeholder when we have no snapshot yet).

  `tracked?` reflects whether the account is linked to a Tuist handle at all;
  when it is not, there is nothing to show and the card can explain why.
  """
  def build(%Account{} = account) do
    if tracked?(account) do
      tracked_view(account)
    else
      untracked_view()
    end
  end

  defp tracked_view(account) do
    snapshots = FeatureUsage.latest_snapshots_map(account.id)

    features =
      Enum.map(Catalog.all(), fn feature ->
        snapshot = Map.get(snapshots, feature.slug)
        status = status(snapshot)

        %{
          slug: feature.slug,
          label: feature.label,
          kind: Catalog.kind(feature),
          scope: Catalog.scope(feature),
          status: status,
          status_label: status_label(status, Catalog.scope(feature)),
          legend_color: legend_color(status),
          value: (snapshot && snapshot.events_last_7d) || 0,
          last_used_label: last_used_label(snapshot),
          events_last_24h: (snapshot && snapshot.events_last_24h) || 0,
          events_last_7d: (snapshot && snapshot.events_last_7d) || 0
        }
      end)

    %{
      tracked?: true,
      features: features,
      build_systems: build_systems(snapshots),
      continuous_integration_providers: continuous_integration_providers(snapshots),
      computed_at: latest_computed_at(snapshots)
    }
  end

  defp untracked_view do
    features =
      Enum.map(Catalog.all(), fn feature ->
        %{
          slug: feature.slug,
          label: feature.label,
          kind: Catalog.kind(feature),
          scope: Catalog.scope(feature),
          status: :unused,
          status_label: status_label(:unused, Catalog.scope(feature)),
          legend_color: legend_color(:unused),
          value: 0,
          last_used_label: "Not tracked yet",
          events_last_24h: 0,
          events_last_7d: 0
        }
      end)

    %{
      tracked?: false,
      features: features,
      build_systems: build_systems(%{}),
      continuous_integration_providers: continuous_integration_providers(%{}),
      computed_at: nil
    }
  end

  # Labels of the build systems the account is actually using (active in the last
  # 7 days). Systems with no recent usage are omitted rather than shown greyed.
  defp build_systems(snapshots) do
    Catalog.build_systems()
    |> Enum.filter(fn system ->
      snapshot = Map.get(snapshots, system.slug)
      snapshot != nil and snapshot.active
    end)
    |> Enum.map(& &1.label)
  end

  defp continuous_integration_providers(snapshots) do
    Catalog.continuous_integration_providers()
    |> Enum.filter(fn provider ->
      snapshot = Map.get(snapshots, provider.slug)
      snapshot != nil and snapshot.active
    end)
    |> Enum.map(& &1.label)
  end

  # Widget status drives the legend colour: an active feature, one that just
  # stopped (used in the prior 7d window but not the last), or unused.
  defp status(nil), do: :unused
  defp status(%{active: true}), do: :active
  defp status(%{active: false, active_previous: true}), do: :stopped
  defp status(_snapshot), do: :unused

  # Maps to Noora chart legend colours used by the widget legend bar.
  defp legend_color(:active), do: "primary"
  defp legend_color(:stopped), do: "destructive"
  defp legend_color(:unused), do: "tertiary"

  defp status_label(:active, :account), do: "Configured"
  defp status_label(:stopped, :account), do: "Removed"
  defp status_label(:unused, :account), do: "Not configured"
  defp status_label(:active, _scope), do: "Active"
  defp status_label(:stopped, _scope), do: "Stopped"
  defp status_label(:unused, _scope), do: "Unused"

  # An account is trackable when it has any handle we can try to resolve to a
  # Tuist account. Prefer the already-preloaded handles (get_account/1 preloads
  # them) so this costs zero database queries; only fall back to a query if the
  # association was not loaded on this struct.
  defp tracked?(%Account{account_handles: handles}) when is_list(handles), do: handles != []
  defp tracked?(%Account{id: id}), do: FeatureUsage.account_handles(id) != []

  defp last_used_label(nil), do: "Never"
  defp last_used_label(%{last_used_at: %DateTime{} = at}), do: Calendar.strftime(at, "%b %-d, %Y")
  defp last_used_label(_snapshot), do: "Never"

  defp latest_computed_at(snapshots) when map_size(snapshots) == 0, do: nil

  defp latest_computed_at(snapshots) do
    snapshots
    |> Map.values()
    |> Enum.map(& &1.computed_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end
end
