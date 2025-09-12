defmodule TuistWeb.Marketing.MarketingControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment

  describe "POST /newsletter" do
    test "successfully sends confirmation email when API key is present", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, opts ->
        assert opts[:json]["email"] == email
        assert opts[:json]["transactionalId"] == "cmfglb1pe5esq2w0ixnkdou94"

        assert String.contains?(
                 opts[:json]["dataVariables"]["verificationUrl"],
                 "/newsletter/verify?token="
               )

        {:ok, %{status: 200}}
      end)

      # When
      conn = post(conn, ~p"/newsletter", %{"email" => email})

      # Then
      assert json_response(conn, 200) == %{
               "success" => true,
               "message" => "Please check your email to confirm your subscription."
             }
    end

    test "returns error when API key is missing", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Environment, :loops_api_key, fn -> nil end)

      # When
      conn = post(conn, ~p"/newsletter", %{"email" => email})

      # Then
      assert json_response(conn, 500) == %{
               "success" => false,
               "message" =>
                 "Newsletter service configuration error: missing API key. Please try again later."
             }
    end

    test "returns error when Loops API fails", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "Invalid request"}}}
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

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
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

  describe "GET /newsletter/verify" do
    test "successfully verifies email with valid token", %{conn: conn} do
      # Given
      email = "test@example.com"
      token = Base.encode64(email)

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, opts ->
        assert opts[:json]["email"] == email
        assert opts[:json]["mailingLists"]["cmfgir0c94l6k0ix00ssx6cbx"] == true
        {:ok, %{status: 200}}
      end)

      # When
      conn = get(conn, ~p"/newsletter/verify?token=#{token}")

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == email
      assert conn.assigns.error_message == nil
      assert conn.assigns.head_title == "Successfully Subscribed!"
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

    test "shows error page when Loops API fails during verification", %{conn: conn} do
      # Given
      email = "test@example.com"
      token = Base.encode64(email)

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "List not found"}}}
      end)

      # When
      conn = get(conn, ~p"/newsletter/verify?token=#{token}")

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil
      assert conn.assigns.error_message == "Verification failed. Please try signing up again."
      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end

    test "shows error page when API key is missing during verification", %{conn: conn} do
      # Given
      email = "test@example.com"
      token = Base.encode64(email)

      expect(Environment, :loops_api_key, fn -> nil end)

      # When
      conn = get(conn, ~p"/newsletter/verify?token=#{token}")

      # Then
      assert html_response(conn, 200)
      assert conn.assigns.email == nil
      assert conn.assigns.error_message == "Verification failed. Please try signing up again."
      assert conn.assigns.head_title == "Newsletter Verification Failed"
    end
  end
end
