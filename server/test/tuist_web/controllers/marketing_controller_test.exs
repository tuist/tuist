defmodule TuistWeb.Marketing.MarketingControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Loops

  describe "POST /newsletter" do
    test "successfully sends confirmation email", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Loops, :send_newsletter_confirmation, fn ^email, verification_url ->
        assert String.contains?(verification_url, "/newsletter/verify?token=")
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

    test "returns error when Loops API fails", %{conn: conn} do
      # Given
      email = "test@example.com"

      expect(Loops, :send_newsletter_confirmation, fn ^email, _verification_url ->
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

      expect(Loops, :send_newsletter_confirmation, fn ^email, _verification_url ->
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

      expect(Loops, :add_to_newsletter_list, fn ^email ->
        :ok
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

      expect(Loops, :add_to_newsletter_list, fn ^email ->
        {:error, {:http_error, 400}}
      end)

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
