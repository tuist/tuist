defmodule Atlas.MCP.Tools.FeatureUsageToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.FeatureUsage.Snapshot
  alias Atlas.MCP.Tools.GetAccountFeatureUsage
  alias Atlas.MCP.Tools.ListAccountFeatureUsage
  alias Atlas.Repo

  defp insert_snapshot!(account, attrs) do
    defaults = %{
      account_id: account.id,
      feature: "cache",
      events_last_24h: 0,
      events_last_7d: 0,
      events_prior_7d: 0,
      active: false,
      active_previous: false,
      computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %Snapshot{}
    |> Snapshot.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "get_account_feature_usage" do
    test "returns the latest snapshot per feature for an account" do
      account = insert_account!()
      insert_snapshot!(account, %{feature: "cache", active: true, events_last_7d: 12})

      assert {:ok, payload} =
               execute_tool(GetAccountFeatureUsage, %{}, %{"account_id" => account.id})

      assert payload["account_id"] == account.id
      cache = Enum.find(payload["features"], &(&1["feature"] == "cache"))
      assert cache["active"] == true
      assert cache["events_last_7d"] == 12
      assert cache["label"] == "Cache"
    end

    test "returns single sign-on and continuous-integration usage signals" do
      account = insert_account!()

      insert_snapshot!(account, %{
        feature: "single_sign_on",
        active: true,
        events_last_24h: 1,
        events_last_7d: 1
      })

      insert_snapshot!(account, %{
        feature: "continuous_integration_github",
        active: true,
        events_last_24h: 3,
        events_last_7d: 12
      })

      assert {:ok, payload} =
               execute_tool(GetAccountFeatureUsage, %{}, %{"account_id" => account.id})

      single_sign_on = Enum.find(payload["features"], &(&1["feature"] == "single_sign_on"))
      github = Enum.find(payload["features"], &(&1["feature"] == "continuous_integration_github"))

      assert single_sign_on["label"] == "Single sign-on"
      assert single_sign_on["active"] == true
      assert github["label"] == "GitHub"
      assert github["events_last_7d"] == 12
    end

    test "errors when the account cannot be resolved" do
      assert {:error, _message} = execute_tool(GetAccountFeatureUsage, %{}, %{"account_id" => Ecto.UUID.generate()})
    end
  end

  describe "list_account_feature_usage" do
    test "lists recent stopped-feature transitions, filterable by feature" do
      account = insert_account!()
      insert_snapshot!(account, %{feature: "cache", active: false, active_previous: true, events_prior_7d: 6})
      insert_snapshot!(account, %{feature: "builds", active: false, active_previous: true, events_prior_7d: 3})
      insert_snapshot!(account, %{feature: "runners", active: true, active_previous: true})

      assert {:ok, %{"stopped_using" => all, "count" => count}} =
               execute_tool(ListAccountFeatureUsage, %{}, %{})

      assert count == 2
      features = all |> Enum.map(& &1["feature"]["feature"]) |> Enum.sort()
      assert features == ["builds", "cache"]

      assert {:ok, %{"stopped_using" => [entry]}} =
               execute_tool(ListAccountFeatureUsage, %{}, %{"feature" => "cache"})

      assert entry["account_id"] == account.id
      assert entry["feature"]["feature"] == "cache"
    end
  end
end
