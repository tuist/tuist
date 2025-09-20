defmodule Tuist.LoopsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Loops

  describe "send_transactional_email/3" do
    test "successfully sends transactional email" do
      # Given
      email = "test@example.com"
      transactional_id = "test-campaign-id"
      data_variables = %{"verificationUrl" => "https://example.com/verify"}

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn url, opts ->
        assert url == "https://app.loops.so/api/v1/transactional"
        assert opts[:json]["email"] == email
        assert opts[:json]["transactionalId"] == transactional_id
        assert opts[:json]["dataVariables"] == data_variables
        assert opts[:headers] == [{"Authorization", "Bearer test-api-key"}]
        {:ok, %{status: 200}}
      end)

      # When
      result = Loops.send_transactional_email(email, transactional_id, data_variables)

      # Then
      assert result == :ok
    end

    test "returns error when Loops API returns error status" do
      # Given
      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "Invalid campaign"}}}
      end)

      # When
      result = Loops.send_transactional_email("test@example.com", "invalid-campaign")

      # Then
      assert result == {:error, {:http_error, 400, %{"error" => "Invalid campaign"}}}
    end

    test "returns error when network request fails" do
      # Given
      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:error, :timeout}
      end)

      # When
      result = Loops.send_transactional_email("test@example.com", "campaign-id")

      # Then
      assert result == {:error, :timeout}
    end
  end

  describe "update_contact/2" do
    test "successfully updates contact with mailing lists" do
      # Given
      email = "test@example.com"
      mailing_lists = %{"list-id-1" => true, "list-id-2" => false}

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn url, opts ->
        assert url == "https://app.loops.so/api/v1/contacts/update"
        assert opts[:json]["email"] == email
        assert opts[:json]["mailingLists"] == mailing_lists
        assert opts[:headers] == [{"Authorization", "Bearer test-api-key"}]
        {:ok, %{status: 200}}
      end)

      # When
      result = Loops.update_contact(email, mailing_lists)

      # Then
      assert result == :ok
    end

    test "works with empty mailing lists" do
      # Given
      email = "test@example.com"

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, opts ->
        assert opts[:json]["mailingLists"] == %{}
        {:ok, %{status: 200}}
      end)

      # When
      result = Loops.update_contact(email)

      # Then
      assert result == :ok
    end

    test "returns error when Loops API returns error status" do
      # Given
      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 404}}
      end)

      # When
      result = Loops.update_contact("test@example.com")

      # Then
      assert result == {:error, {:http_error, 404}}
    end

    test "returns error when network request fails" do
      # Given
      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:error, :connection_refused}
      end)

      # When
      result = Loops.update_contact("test@example.com")

      # Then
      assert result == {:error, :connection_refused}
    end
  end

  describe "send_newsletter_confirmation/2" do
    test "sends confirmation email with correct campaign ID and verification URL" do
      # Given
      email = "test@example.com"
      verification_url = "https://example.com/verify?token=abc123"

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn url, opts ->
        assert url == "https://app.loops.so/api/v1/transactional"
        assert opts[:json]["email"] == email
        assert opts[:json]["transactionalId"] == "cmfglb1pe5esq2w0ixnkdou94"
        assert opts[:json]["dataVariables"]["verificationUrl"] == verification_url
        {:ok, %{status: 200}}
      end)

      # When
      result = Loops.send_newsletter_confirmation(email, verification_url)

      # Then
      assert result == :ok
    end

    test "returns error when underlying send_transactional_email fails" do
      # Given
      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:error, :timeout}
      end)

      # When
      result =
        Loops.send_newsletter_confirmation("test@example.com", "https://example.com/verify")

      # Then
      assert result == {:error, :timeout}
    end
  end

  describe "add_to_newsletter_list/1" do
    test "adds email to Tuist Digest mailing list" do
      # Given
      email = "test@example.com"

      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn url, opts ->
        assert url == "https://app.loops.so/api/v1/contacts/update"
        assert opts[:json]["email"] == email
        assert opts[:json]["mailingLists"]["cmfgl9s214xcv0izt5jyu7e9d"] == true
        {:ok, %{status: 200}}
      end)

      # When
      result = Loops.add_to_newsletter_list(email)

      # Then
      assert result == :ok
    end

    test "returns error when underlying update_contact fails" do
      # Given
      expect(Environment, :loops_api_key, fn -> "test-api-key" end)

      expect(Req, :post, fn _url, _opts ->
        {:error, :connection_refused}
      end)

      # When
      result = Loops.add_to_newsletter_list("test@example.com")

      # Then
      assert result == {:error, :connection_refused}
    end
  end
end
