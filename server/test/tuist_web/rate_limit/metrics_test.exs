defmodule TuistWeb.RateLimit.MetricsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.User
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.Metrics

  describe "hit/1" do
    test "uses a fixed-window policy keyed by the authenticated subject", %{conn: conn} do
      user = %User{id: 123}
      window = to_timeout(minute: 1)

      stub(Authentication, :authenticated_subject, fn ^conn -> user end)

      expect(RateLimit, :hit, fn
        "metrics:user:123", [limit: 300, window: ^window] ->
          {:allow, 1}
      end)

      assert Metrics.hit(conn) == {:allow, 1}
    end
  end
end
