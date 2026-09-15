defmodule TuistWeb.PublicPageChallengeControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.PublicPageChallengePlug
  alias TuistWeb.RateLimit
  alias TuistWeb.Turnstile

  setup %{conn: conn} do
    stub(FeatureFlags, :public_page_challenge_enabled?, fn -> true end)
    stub(Turnstile, :required?, fn -> true end)
    stub(Turnstile, :site_key, fn -> "test-site-key" end)
    stub(RateLimit, :hit, fn _key, _opts -> {:allow, 1} end)
    %{conn: init_test_session(conn, %{})}
  end

  describe "GET /turnstile-challenge" do
    test "renders the dashboard widget even when signup verification is disabled", %{conn: conn} do
      stub(Turnstile, :required?, fn -> false end)

      conn = get(conn, "/turnstile-challenge")

      html = html_response(conn, 200)
      assert html =~ ~s(id="turnstile-widget")
      assert html =~ ~s(data-sitekey="test-site-key")
      assert html =~ ~s(data-action="public_page_challenge")
      refute html =~ "Turnstile is unavailable"
    end

    test "renders the challenge page when anonymous and unverified", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(PublicPageChallengePlug.return_to_key(), "/example-account/example-project/tests")

      conn = get(conn, "/turnstile-challenge")

      html = html_response(conn, 200)
      assert html =~ "Just a quick check"
      assert html =~ "/example-account/example-project/tests"
      assert get_resp_header(conn, "cache-control") == ["no-store, no-cache, must-revalidate, max-age=0"]
    end

    test "redirects to the return path when a fresh verification is already in the session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(PublicPageChallengePlug.session_key(), System.system_time(:second))
        |> put_session(PublicPageChallengePlug.return_to_key(), "/example-account/example-project/tests")

      conn = get(conn, "/turnstile-challenge")

      assert redirected_to(conn) == "/example-account/example-project/tests"
    end

    test "redirects home when the feature flag is off", %{conn: conn} do
      stub(FeatureFlags, :public_page_challenge_enabled?, fn -> false end)

      conn = get(conn, "/turnstile-challenge")

      assert redirected_to(conn) == "/"
    end

    test "captures return_to from query string into the session (LiveView on_mount vector)", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get("/turnstile-challenge?return_to=%2Fexample-account%2Fexample-project%2Ftests")

      assert html_response(conn, 200) =~ "Just a quick check"

      assert get_session(conn, PublicPageChallengePlug.return_to_key()) ==
               "/example-account/example-project/tests"
    end

    test "drops a non-local return_to query rather than persisting it", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get("/turnstile-challenge?return_to=https%3A%2F%2Fevil.example.com%2Fland")

      assert html_response(conn, 200)
      refute get_session(conn, PublicPageChallengePlug.return_to_key())
    end

    test "responds to HEAD without a body but with the no-store header", %{conn: conn} do
      conn = init_test_session(conn, %{})

      conn = head(conn, "/turnstile-challenge")

      assert response(conn, 200) == ""
      assert get_resp_header(conn, "cache-control") == ["no-store, no-cache, must-revalidate, max-age=0"]
    end

    test "redirects signed-in users straight to the return path", %{conn: conn} do
      # See the sibling plug test for why we stub current_user
      # instead of calling Authentication.log_in_user/3 (which sends
      # a redirect before the controller ever runs).
      user = AccountsFixtures.user_fixture()
      stub(Authentication, :current_user, fn _ -> user end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(PublicPageChallengePlug.return_to_key(), "/example-account/example-project/tests")

      conn = get(conn, "/turnstile-challenge")

      assert redirected_to(conn) == "/example-account/example-project/tests"
    end
  end

  describe "POST /turnstile-challenge/verify" do
    test "marks the session verified and honours a local return path on success", %{conn: conn} do
      expect(Turnstile, :verify, fn "good-token", opts ->
        assert opts[:expected_action] == "public_page_challenge"
        :ok
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(PublicPageChallengePlug.return_to_key(), "/example-account/example-project/tests")

      conn = post(conn, "/turnstile-challenge/verify", %{"cf-turnstile-response" => "good-token"})

      assert redirected_to(conn) == "/example-account/example-project/tests"
      assert get_session(conn, PublicPageChallengePlug.session_key())
      refute get_session(conn, PublicPageChallengePlug.return_to_key())
    end

    test "rejects a non-local return_to override, uses root instead", %{conn: conn} do
      expect(Turnstile, :verify, fn _token, _opts -> :ok end)

      conn = init_test_session(conn, %{})

      conn =
        post(conn, "/turnstile-challenge/verify", %{
          "cf-turnstile-response" => "good",
          "return_to" => "https://evil.example.com/land"
        })

      assert redirected_to(conn) == "/"
    end

    test "rejects a protocol-relative return_to override", %{conn: conn} do
      expect(Turnstile, :verify, fn _token, _opts -> :ok end)

      conn = init_test_session(conn, %{})

      conn =
        post(conn, "/turnstile-challenge/verify", %{
          "cf-turnstile-response" => "good",
          "return_to" => "//evil.example.com/land"
        })

      assert redirected_to(conn) == "/"
    end

    test "rejects a return_to override with a control character (Location injection)", %{conn: conn} do
      expect(Turnstile, :verify, fn _token, _opts -> :ok end)

      conn = init_test_session(conn, %{})

      conn =
        post(conn, "/turnstile-challenge/verify", %{
          "cf-turnstile-response" => "good",
          "return_to" => "/example-account/example-project\\rSet-Cookie: evil=1"
        })

      assert redirected_to(conn) == "/"
    end

    test "forces Turnstile.verify to run even if the signup gate is off", %{conn: conn} do
      # A caller that stubs Turnstile.verify without `required?: true`
      # would otherwise slip through when the signup env var is off:
      # `verify/2` short-circuits to `:ok`. This test guards the
      # explicit `required?: true` the controller passes.
      expect(Turnstile, :verify, fn _token, opts ->
        assert Keyword.get(opts, :required?) == true
        :ok
      end)

      conn = init_test_session(conn, %{})

      conn = post(conn, "/turnstile-challenge/verify", %{"cf-turnstile-response" => "good"})

      assert redirected_to(conn) == "/"
    end

    test "renders the challenge with an error on verification failure", %{conn: conn} do
      expect(Turnstile, :verify, fn _token, _opts -> {:error, :rejected} end)

      conn = init_test_session(conn, %{})

      conn = post(conn, "/turnstile-challenge/verify", %{"cf-turnstile-response" => "bad"})

      assert html_response(conn, 400) =~ "Verification failed"
    end

    test "returns 429 when the per-IP rate limit is exhausted", %{conn: conn} do
      stub(RateLimit, :hit, fn _key, _opts -> {:deny, 30} end)

      conn = init_test_session(conn, %{})

      conn = post(conn, "/turnstile-challenge/verify", %{"cf-turnstile-response" => "any"})

      assert html_response(conn, 429) =~ "Too many attempts"
    end
  end
end
