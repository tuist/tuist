defmodule TuistWeb.Plugs.PublicPageChallengePlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.PublicPageChallengePlug

  setup %{conn: conn} do
    stub(FeatureFlags, :public_page_challenge_enabled?, fn -> true end)
    %{conn: init_test_session(conn, %{})}
  end

  describe "call/2" do
    test "passes through when the feature flag is off", %{conn: conn} do
      stub(FeatureFlags, :public_page_challenge_enabled?, fn -> false end)

      out = PublicPageChallengePlug.call(conn, [])

      refute out.halted
      refute get_session(out, PublicPageChallengePlug.session_key())
    end

    test "passes through for a signed-in user without touching the session", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      # `Authentication.log_in_user/3` renews the session and issues a
      # redirect to the signed-in home, which means the response has
      # already been sent by the time the plug runs. The plug reads
      # the signed-in state through `Authentication.current_user/1`,
      # so stubbing that keeps this test focused on the plug's own
      # branching without dragging the full sign-in pipeline in.
      stub(Authentication, :current_user, fn _ -> user end)

      out = PublicPageChallengePlug.call(conn, [])

      refute out.halted
      refute get_session(out, PublicPageChallengePlug.return_to_key())
    end

    test "passes through when the session already carries a fresh verification", %{conn: conn} do
      conn = put_session(conn, PublicPageChallengePlug.session_key(), System.system_time(:second))

      out = PublicPageChallengePlug.call(conn, [])

      refute out.halted
    end

    test "redirects to the challenge and stores return_to when anonymous", %{conn: conn} do
      conn =
        fetch_query_params(%{
          conn
          | request_path: "/example-account/example-project/tests/test-runs",
            query_string: "page=3"
        })

      out = PublicPageChallengePlug.call(conn, [])

      assert out.halted
      assert redirected_to(out) == PublicPageChallengePlug.challenge_path()

      assert get_session(out, PublicPageChallengePlug.return_to_key()) ==
               "/example-account/example-project/tests/test-runs?page=3"
    end

    test "redirects when the stored timestamp is beyond the freshness window", %{conn: conn} do
      # 12h old — well outside the 4h default freshness.
      stale = System.system_time(:second) - 12 * 60 * 60
      conn = put_session(conn, PublicPageChallengePlug.session_key(), stale)

      out = PublicPageChallengePlug.call(conn, [])

      assert out.halted
      assert redirected_to(out) == PublicPageChallengePlug.challenge_path()
    end
  end

  describe "verified_within_freshness?/1 with session map" do
    test "false for a missing key" do
      refute PublicPageChallengePlug.verified_within_freshness?(%{})
    end

    test "true for a fresh integer timestamp" do
      session = %{PublicPageChallengePlug.session_key() => System.system_time(:second)}
      assert PublicPageChallengePlug.verified_within_freshness?(session)
    end

    test "false for a stale integer timestamp" do
      stale = System.system_time(:second) - 24 * 60 * 60
      session = %{PublicPageChallengePlug.session_key() => stale}
      refute PublicPageChallengePlug.verified_within_freshness?(session)
    end

    test "false for a non-integer value (defensive against a session dump)" do
      session = %{PublicPageChallengePlug.session_key() => "totally-not-a-timestamp"}
      refute PublicPageChallengePlug.verified_within_freshness?(session)
    end
  end
end
