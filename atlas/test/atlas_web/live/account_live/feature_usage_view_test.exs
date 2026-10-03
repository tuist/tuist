defmodule AtlasWeb.AccountLive.FeatureUsageViewTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.FeatureUsage.Snapshot
  alias Atlas.Repo
  alias AtlasWeb.AccountLive.FeatureUsageView

  defp account_with_handle! do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "account:#{System.unique_integer([:positive])}",
        name: "Acme",
        segment: :customer
      })
      |> Repo.insert!()

    handle =
      %AccountHandle{}
      |> AccountHandle.changeset(%{account_id: account.id, handle: "acme", source: "tuist"})
      |> Repo.insert!()

    # `Accounts.get_account/1` preloads the handles, and the view relies on that.
    %{account | account_handles: [handle]}
  end

  defp insert_snapshot!(account, attrs) do
    %Snapshot{}
    |> Snapshot.changeset(
      Map.merge(
        %{
          account_id: account.id,
          events_prior_7d: 0,
          computed_at: ~U[2026-07-31 06:00:00Z]
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp feature(view, slug), do: Enum.find(view.features, &(&1.slug == slug))

  describe "build/1" do
    test "marks the automations widget as a configuration feature" do
      account = account_with_handle!()

      insert_snapshot!(account, %{
        feature: "automations",
        # 3 enabled out of 5 configured across the account's projects.
        events_last_24h: 5,
        events_last_7d: 3,
        last_used_at: ~U[2026-07-24 09:30:00Z],
        active: true,
        active_previous: false
      })

      view = FeatureUsageView.build(account)
      automations = feature(view, "automations")

      assert automations.kind == :configuration
      assert automations.status == :active
      assert automations.value == 3
      assert automations.events_last_24h == 5
      assert automations.last_used_label == "Jul 24, 2026"
    end

    test "shows automations as unused when the account has none enabled" do
      account = account_with_handle!()

      insert_snapshot!(account, %{
        feature: "automations",
        events_last_24h: 0,
        events_last_7d: 0,
        active: false,
        active_previous: false
      })

      automations = account |> FeatureUsageView.build() |> feature("automations")

      assert automations.status == :unused
      assert automations.value == 0
      assert automations.last_used_label == "Never"
    end

    test "keeps event features on the event kind" do
      account = account_with_handle!()

      assert account |> FeatureUsageView.build() |> feature("cache") |> Map.fetch!(:kind) == :events
    end

    test "shows single sign-on configuration and detected continuous-integration providers" do
      account = account_with_handle!()

      insert_snapshot!(account, %{
        feature: "single_sign_on",
        events_last_24h: 1,
        events_last_7d: 1,
        last_used_at: ~U[2026-07-31 10:45:00Z],
        active: true,
        active_previous: true
      })

      insert_snapshot!(account, %{
        feature: "continuous_integration_github",
        events_last_24h: 3,
        events_last_7d: 12,
        last_used_at: ~U[2026-07-31 10:30:00Z],
        active: true,
        active_previous: true
      })

      view = FeatureUsageView.build(account)
      single_sign_on = feature(view, "single_sign_on")

      assert single_sign_on.kind == :configuration
      assert single_sign_on.scope == :account
      assert single_sign_on.status_label == "Configured"
      assert view.continuous_integration_providers == ["GitHub"]
    end
  end
end
