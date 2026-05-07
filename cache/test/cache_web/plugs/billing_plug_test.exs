defmodule CacheWeb.Plugs.BillingPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias CacheWeb.Plugs.BillingPlug

  describe "call/2" do
    test "lets the request through when no billing snapshot is assigned (e.g. JWT-only auth)" do
      conn = assign(build_conn(), :account_billing, nil)

      result = BillingPlug.call(conn, BillingPlug.init([]))

      refute result.halted
    end

    test "lets an air-plan account through when under the threshold" do
      conn =
        assign(build_conn(), :account_billing, %{plan: :air, subscription_active: true, thresholds_surpassed: false})

      result = BillingPlug.call(conn, BillingPlug.init([]))

      refute result.halted
    end

    test "rejects an air-plan account that has surpassed the free tier thresholds" do
      conn =
        assign(build_conn(), :account_billing, %{plan: :air, subscription_active: true, thresholds_surpassed: true})

      result = BillingPlug.call(conn, BillingPlug.init([]))

      assert result.halted
      assert result.status == 402
      assert result.resp_body =~ "free tier"
    end

    test "lets a pro-plan account through even when over the air thresholds" do
      conn =
        assign(build_conn(), :account_billing, %{plan: :pro, subscription_active: true, thresholds_surpassed: true})

      result = BillingPlug.call(conn, BillingPlug.init([]))

      refute result.halted
    end

    test "rejects a pro-plan account whose subscription is no longer active" do
      conn =
        assign(build_conn(), :account_billing, %{plan: :pro, subscription_active: false, thresholds_surpassed: false})

      result = BillingPlug.call(conn, BillingPlug.init([]))

      assert result.halted
      assert result.status == 402
      assert result.resp_body =~ "subscription"
    end

    test "rejects an enterprise-plan account whose subscription is no longer active" do
      conn =
        assign(build_conn(), :account_billing, %{
          plan: :enterprise,
          subscription_active: false,
          thresholds_surpassed: false
        })

      result = BillingPlug.call(conn, BillingPlug.init([]))

      assert result.halted
      assert result.status == 402
    end
  end

  defp build_conn do
    :get
    |> conn("/api/cache/cas/some-hash?account_handle=tuist&project_handle=app")
    |> fetch_query_params()
  end
end
