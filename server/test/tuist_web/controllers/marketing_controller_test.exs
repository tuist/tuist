defmodule TuistWeb.Marketing.MarketingControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Atlas.Email
  alias Tuist.Loops
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "GET /" do
    test "includes agent discovery link headers on the homepage", %{conn: conn} do
      conn = get(conn, "/")

      assert html_response(conn, 200)
      assert [link_header] = get_resp_header(conn, "link")
      assert link_header =~ ~s(</.well-known/api-catalog>; rel="api-catalog")
      assert link_header =~ ~s(type="application/linkset+json")
      assert link_header =~ ~s(profile="https://www.rfc-editor.org/info/rfc9727")
      assert link_header =~ ~s(</api/spec>; rel="service-desc"; type="application/json")
      assert link_header =~ ~s(</api/docs>; rel="service-doc"; type="text/html")
    end
  end

  describe "GET / (new design rollout)" do
    test "renders the legacy design and stylesheet by default", %{conn: conn} do
      conn = get(conn, "/")

      html = html_response(conn, 200)
      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "renders the new design and stylesheet when the page flag is enabled", %{conn: conn} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_home -> true
        _ -> false
      end)

      conn = get(conn, "/")

      html = html_response(conn, 200)
      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "renders the new design for a user actor-gated onto the page flag", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      user_id = user.id

      stub(FunWithFlags, :enabled?, fn _flag -> false end)

      stub(FunWithFlags, :enabled?, fn
        :new_marketing_home, [for: %{id: ^user_id}] -> true
        _flag, _opts -> false
      end)

      conn = conn |> log_in_user(user) |> get("/")

      html = html_response(conn, 200)
      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "keeps the legacy design for authenticated users without the actor gate", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      stub(FunWithFlags, :enabled?, fn _flag -> false end)
      stub(FunWithFlags, :enabled?, fn _flag, _opts -> false end)

      conn = conn |> log_in_user(user) |> get("/")

      html = html_response(conn, 200)
      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "anonymous responses stay publicly cacheable", %{conn: conn} do
      conn = get(conn, "/")

      assert get_resp_header(conn, "cache-control") == ["public, max-age=60, stale-while-revalidate=86400"]
    end

    test "authenticated responses are not cacheable by shared caches", %{conn: conn} do
      # An authenticated user can be actor-gated onto a redesigned page, so
      # a shared cache must never store their variant at the ordinary URL.
      user = AccountsFixtures.user_fixture()

      conn = conn |> log_in_user(user) |> get("/")

      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end
  end

  describe "POST /newsletter" do
    test "successfully sends confirmation email", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Email, :send_newsletter_confirmation, fn ^email, verification_url ->
        uri = URI.parse(verification_url)
        assert uri.path == "/newsletter/verify"
        assert %{"token" => token} = URI.decode_query(uri.query)

        assert {:ok, ^email} =
                 Phoenix.Token.verify(TuistWeb.Endpoint, "newsletter_subscription", token, max_age: 2 * 24 * 60 * 60)

        :ok
      end)

      # When
      conn = post(conn, ~p"/newsletter", %{"email" => email})

      # Then
      assert json_response(conn, 200) == %{
               "success" => true,
               "message" => "Please check your email to confirm your subscription."
             }
    end

    test "returns error when the email API fails", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Email, :send_newsletter_confirmation, fn ^email, _verification_url ->
        {:error, {:http_error, 400, %{"error" => "Invalid request"}}}
      end)

      # When
      conn = post(conn, ~p"/newsletter", %{"email" => email})

      # Then
      assert json_response(conn, 400) == %{
               "success" => false,
               "message" => "Something went wrong. Please try again."
             }
    end

    test "returns error when network request fails", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Email, :send_newsletter_confirmation, fn ^email, _verification_url ->
        {:error, :timeout}
      end)

      # When
      conn = post(conn, ~p"/newsletter", %{"email" => email})

      # Then
      assert json_response(conn, 400) == %{
               "success" => false,
               "message" => "Something went wrong. Please try again."
             }
    end
  end

  describe "GET /page" do
    test "raises NotFoundError when page is not found", %{conn: conn} do
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        conn
        |> Map.put(:request_path, "//terms")
        |> TuistWeb.Marketing.MarketingController.page(%{})
      end
    end
  end

  describe "GET /customers/:slug" do
    test "renders the localized Hyperconnect case study", %{conn: conn} do
      conn = get(conn, ~p"/ko/customers/hyperconnect")

      html = html_response(conn, 200)

      assert html =~ "Hyperconnect가 Tuist로 멀티 서비스 파이프라인을 최적화한 방법"
      assert html =~ "복수의 서비스 타깃을 동시에 운영"
    end

    test "redirects external case studies to their source article", %{conn: conn} do
      conn = get(conn, ~p"/customers/delivery-hero")

      assert redirected_to(conn) ==
               "https://deliveryhero.jobs/blog/scaling-ios-application-development-with-tuist/"
    end
  end

  describe "GET /newsletter/verify" do
    test "shows a confirmation page with a valid token", %{conn: conn} do
      # Given
      email = "test@example.com"
      token = signed_newsletter_token(email)

      # When
      conn = get(conn, ~p"/newsletter/verify?token=#{token}")

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == email
      assert conn.assigns.verification_token == token
      assert conn.assigns.subscription_confirmed == false
      assert conn.assigns.error_message == nil
      assert conn.assigns.head_title == "Confirm Subscription"
    end

    test "does not accept legacy base64 email tokens", %{conn: conn} do
      # Given
      token = Base.encode64("test@example.com")

      # When
      conn = get(conn, ~p"/newsletter/verify?token=#{token}")

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil

      assert conn.assigns.error_message ==
               "Invalid verification link. Please try signing up again."

      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end

    test "shows error page when token is invalid", %{conn: conn} do
      # Given
      invalid_token = "invalid-token"

      # When
      conn = get(conn, ~p"/newsletter/verify?token=#{invalid_token}")

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil

      assert conn.assigns.error_message ==
               "Invalid verification link. Please try signing up again."

      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end

    test "shows error page when no token provided", %{conn: conn} do
      # When
      conn = get(conn, ~p"/newsletter/verify")

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil

      assert conn.assigns.error_message ==
               "Verification link expired or invalid. Please try signing up again."

      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end
  end

  describe "POST /newsletter/verify" do
    test "subscribes email with a valid token", %{conn: conn} do
      # Given
      email = "test@example.com"
      token = signed_newsletter_token(email)

      expect(Email, :add_to_newsletter_list, fn ^email ->
        :ok
      end)

      # When
      conn = post(conn, ~p"/newsletter/verify", %{"token" => token})

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == email
      assert conn.assigns.subscription_confirmed == true
      assert conn.assigns.error_message == nil
      assert conn.assigns.head_title == "Successfully Subscribed!"
    end

    test "shows error page when the email API fails during verification", %{conn: conn} do
      # Given
      email = "test@example.com"
      token = signed_newsletter_token(email)

      expect(Email, :add_to_newsletter_list, fn ^email ->
        {:error, {:http_error, 400}}
      end)

      # When
      conn = post(conn, ~p"/newsletter/verify", %{"token" => token})

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil
      assert conn.assigns.error_message == "Verification failed. Please try signing up again."
      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end

    test "shows error page when token is invalid", %{conn: conn} do
      # When
      conn = post(conn, ~p"/newsletter/verify", %{"token" => "invalid-token"})

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil

      assert conn.assigns.error_message ==
               "Invalid verification link. Please try signing up again."

      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end

    test "shows error page when no token provided", %{conn: conn} do
      # When
      conn = post(conn, ~p"/newsletter/verify", %{})

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil

      assert conn.assigns.error_message ==
               "Verification link expired or invalid. Please try signing up again."

      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end
  end

  defp signed_newsletter_token(email) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "newsletter_subscription", email)
  end
end
