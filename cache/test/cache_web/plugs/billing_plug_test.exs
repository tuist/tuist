defmodule CacheWeb.Plugs.BillingPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias CacheWeb.Plugs.BillingPlug

  describe "call/2" do
    test "lets the request through when no xcode cache limit flag is assigned (e.g. JWT-only auth)" do
      conn = assign(build_conn(), :xcode_cache_limit_surpassed, nil)

      result = BillingPlug.call(conn, BillingPlug.init([]))

      refute result.halted
    end

    test "lets the request through when the xcode cache limit is not surpassed" do
      conn = assign(build_conn(), :xcode_cache_limit_surpassed, false)

      result = BillingPlug.call(conn, BillingPlug.init([]))

      refute result.halted
    end

    test "rejects the request when the xcode cache limit is surpassed" do
      conn = assign(build_conn(), :xcode_cache_limit_surpassed, true)

      result = BillingPlug.call(conn, BillingPlug.init([]))

      assert result.halted
      assert result.status == 402
      assert result.resp_body =~ "free tier"
    end
  end

  defp build_conn do
    :get
    |> conn("/api/cache/cas/some-hash?account_handle=tuist&project_handle=app")
    |> fetch_query_params()
  end
end
