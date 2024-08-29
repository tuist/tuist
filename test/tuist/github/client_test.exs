defmodule Tuist.GitHub.ClientTest do
  use ExUnit.Case, async: true

  use Mimic
  alias Tuist.VCS.Comment
  alias Tuist.GitHub.TokenStorage
  alias Tuist.GitHub.Client

  setup do
    JOSE.JWK |> stub(:from_pem, fn _ -> "pem" end)
    JOSE.JWT |> stub(:sign, fn _, _, _ -> "signed_pem" end)
    JOSE.JWS |> stub(:compact, fn _ -> {%{}, "jwt"} end)

    Tuist.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    JOSE.JWT
    |> stub(:peek_payload, fn _ ->
      %JOSE.JWT{fields: %{"exp" => ~U[2024-04-30 10:20:31Z] |> DateTime.to_unix()}}
    end)

    :ok
  end

  @default_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"Authorization", "token github_token"}
  ]

  describe "get_comments/1" do
    test "returns comments" do
      # Given
      Req
      |> expect(:get, fn [
                           headers: @default_headers,
                           url: "https://api.github.com/repos/tuist/tuist/issues/1/comments"
                         ] ->
        {:ok, %Req.Response{status: 200, body: [%{"id" => "comment-id"}]}}
      end)

      {:ok, _pid} =
        TokenStorage.start_link(%{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]})

      # When
      comments = Client.get_comments(%{repository: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:ok, [%Comment{id: "comment-id", client_id: nil}]}
    end

    test "refreshes token when the response initially returns unauthenticated error" do
      # Given
      Req
      |> stub(
        :get,
        fn
          "https://api.github.com/app/installations", _ ->
            {:ok,
             %Req.Response{status: 200, body: [%{"access_tokens_url" => "access_tokens_url"}]}}
        end
      )

      Req
      |> stub(:get, fn options ->
        headers = Keyword.get(options, :headers)
        [_json_header, auth_header] = headers
        {_, token} = auth_header

        if token == "token new_token" do
          {:ok, %Req.Response{status: 200, body: [%{"id" => "comment-id"}]}}
        else
          {:ok, %Req.Response{status: 401}}
        end
      end)

      Req
      |> expect(:post, fn "access_tokens_url", _ ->
        {:ok,
         %Req.Response{
           status: 201,
           body: %{"token" => "new_token", "expires_at" => "2024-04-30T10:30:31Z"}
         }}
      end)

      {:ok, _pid} =
        TokenStorage.start_link(%{token: "old_token", expires_at: ~U[2024-04-30 10:20:29Z]})

      # When
      comments = Client.get_comments(%{repository: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:ok, [%Comment{id: "comment-id", client_id: nil}]}
    end

    test "refreshes token when the token is initially nil" do
      # Given
      Req
      |> stub(
        :get,
        fn
          "https://api.github.com/app/installations", _options ->
            {:ok,
             %Req.Response{status: 200, body: [%{"access_tokens_url" => "access_tokens_url"}]}}
        end
      )

      Req
      |> stub(:get, fn [
                         headers: [
                           {"Accept", "application/vnd.github.v3+json"},
                           {"Authorization", "token new_token"}
                         ],
                         url: "https://api.github.com/repos/tuist/tuist/issues/1/comments"
                       ] ->
        {:ok, %Req.Response{status: 200, body: [%{"id" => "comment-id"}]}}
      end)

      Req
      |> expect(:post, fn "access_tokens_url", _ ->
        {:ok,
         %Req.Response{
           status: 201,
           body: %{"token" => "new_token", "expires_at" => "2024-04-30T10:30:31Z"}
         }}
      end)

      {:ok, _pid} = TokenStorage.start_link(nil)

      # When
      comments = Client.get_comments(%{repository: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:ok, [%Comment{id: "comment-id", client_id: nil}]}
    end

    test "returns a server error" do
      # Given
      Req
      |> stub(:get, fn _ ->
        {:ok, %Req.Response{status: 500}}
      end)

      {:ok, _pid} =
        TokenStorage.start_link(%{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]})

      # When
      comments = Client.get_comments(%{repository: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:error, "Unexpected status code: 500. Body: \"\""}
    end

    test "returns forbidden error" do
      # Given
      Req
      |> stub(:get, fn _ ->
        {:ok, %Req.Response{status: 403}}
      end)

      {:ok, _pid} =
        TokenStorage.start_link(%{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]})

      # When
      comments = Client.get_comments(%{repository: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:error, "Unexpected status code: 403. Body: \"\""}
    end

    test "returns 503 error when refreshing token fails" do
      # Given
      Req
      |> stub(:get, fn _, _ ->
        {:ok, %Req.Response{status: 503}}
      end)

      {:ok, _pid} =
        TokenStorage.start_link(%{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]})

      # When
      got = Client.get_comments(%{repository: "tuist/tuist", issue_id: 1})

      # Then
      assert got ==
               {:error,
                "Unexpected status code when getting the access token url: 503. Body: \"\""}
    end
  end

  describe "create_comment/1" do
    test "creates a new comment" do
      # Given
      Req
      |> expect(:post, fn [
                            headers: @default_headers,
                            url: "https://api.github.com/repos/tuist/tuist/issues/1/comments",
                            json: %{body: "comment"}
                          ] ->
        {:ok, %Req.Response{status: 201}}
      end)

      {:ok, _pid} =
        TokenStorage.start_link(%{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]})

      # When
      response = Client.create_comment(%{repository: "tuist/tuist", issue_id: 1, body: "comment"})

      # Then
      assert response == :ok
    end
  end

  describe "update_comment/1" do
    test "updates comment" do
      # Given
      Req
      |> expect(:patch, fn [
                             headers: @default_headers,
                             url: "https://api.github.com/repos/tuist/tuist/issues/comments/1",
                             json: %{body: "comment"}
                           ] ->
        {:ok, %Req.Response{status: 201}}
      end)

      {:ok, _pid} =
        TokenStorage.start_link(%{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]})

      # When
      response =
        Client.update_comment(%{repository: "tuist/tuist", comment_id: 1, body: "comment"})

      # Then
      assert response == :ok
    end
  end
end
