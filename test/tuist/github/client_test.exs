defmodule Tuist.GitHub.ClientTest do
  use ExUnit.Case, async: false

  use Mimic
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client

  @default_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"Authorization", "token github_token"}
  ]

  setup do
    App
    |> stub(:get_app_installation_token_for_repository, fn _ ->
      {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
    end)

    :ok
  end

  describe "get_comments/1" do
    test "returns comments" do
      # Given
      Req
      |> expect(:get, fn [
                           headers: @default_headers,
                           url: "https://api.github.com/repos/tuist/tuist/issues/1/comments"
                         ] ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{"id" => "comment-id-one"},
             %{
               "id" => "comment-id-two",
               "performed_via_github_app" => %{"client_id" => "client-id-two"}
             }
           ]
         }}
      end)

      # When
      comments = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert comments ==
               {:ok,
                [
                  %Comment{id: "comment-id-one", client_id: nil},
                  %Comment{id: "comment-id-two", client_id: "client-id-two"}
                ]}
    end

    test "refreshes token when the response initially returns unauthenticated error" do
      # Given
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

      App
      |> stub(:get_app_installation_token_for_repository, fn _ ->
        App
        |> stub(:get_app_installation_token_for_repository, fn _ ->
          {:ok, %{token: "new_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
        end)

        {:ok, %{token: "old_token", expires_at: ~U[2024-04-30 10:20:29Z]}}
      end)

      App
      |> stub(:refresh_token, fn _ ->
        {:ok, %{token: "new_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
      end)

      # When
      comments = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:ok, [%Comment{id: "comment-id", client_id: nil}]}
    end

    test "returns a server error" do
      # Given
      Req
      |> stub(:get, fn _ ->
        {:ok, %Req.Response{status: 500}}
      end)

      # When
      comments = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:error, "Unexpected status code: 500. Body: \"\""}
    end

    test "returns forbidden error" do
      # Given
      Req
      |> stub(:get, fn _ ->
        {:ok, %Req.Response{status: 403}}
      end)

      # When
      comments = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:error, "Unexpected status code: 403. Body: \"\""}
    end

    test "returns error when getting token fails" do
      # Given
      App
      |> stub(:get_app_installation_token_for_repository, fn _ ->
        {:error, "Failed to get token."}
      end)

      # When
      got = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert got ==
               {:error, "Failed to get token."}
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

      # When
      response =
        Client.create_comment(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          body: "comment"
        })

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

      # When
      response =
        Client.update_comment(%{
          repository_full_handle: "tuist/tuist",
          comment_id: 1,
          body: "comment"
        })

      # Then
      assert response == :ok
    end
  end

  describe "get_user_by_id/1" do
    test "returns user" do
      # Given
      Req
      |> expect(:get, fn [
                           headers: @default_headers,
                           url: "https://api.github.com/user/123"
                         ] ->
        {:ok, %Req.Response{status: 200, body: %{"login" => "tuist"}}}
      end)

      # When
      user = Client.get_user_by_id(%{id: "123", repository_full_handle: "tuist/tuist"})

      # Then
      assert user == {:ok, %VCS.User{username: "tuist"}}
    end

    test "returns ok with 404 error" do
      # Given
      Req
      |> expect(:get, fn [
                           headers: @default_headers,
                           url: "https://api.github.com/user/123"
                         ] ->
        {:ok, %Req.Response{status: 404}}
      end)

      # When
      user = Client.get_user_by_id(%{id: "123", repository_full_handle: "tuist/tuist"})

      # Then
      assert user == {:error, "Unexpected status code: 404. Body: \"\""}
    end
  end

  describe "get_user_permission/1" do
    test "returns user permission" do
      # Given
      Req
      |> stub(:get, fn [
                         headers: @default_headers,
                         url: "https://api.github.com/user/123"
                       ] ->
        {:ok, %Req.Response{status: 200, body: %{"login" => "tuist"}}}
      end)

      Req
      |> stub(
        :get,
        fn [
             headers: @default_headers,
             url: "https://api.github.com/repos/tuist/tuist/collaborators/tuist/permission"
           ] ->
          {:ok, %Req.Response{status: 200, body: %{"permission" => "admin"}}}
        end
      )

      # When
      permission =
        Client.get_user_permission(%{username: "tuist", repository_full_handle: "tuist/tuist"})

      # Then
      assert permission == {:ok, %VCS.Repositories.Permission{permission: "admin"}}
    end
  end

  describe "get_repository/1" do
    test "returns repository" do
      # Given
      Req
      |> expect(:get, fn [
                           headers: @default_headers,
                           url: "https://api.github.com/repos/tuist/tuist"
                         ] ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"full_name" => "tuist/tuist", "default_branch" => "main"}
         }}
      end)

      # When
      repository = Client.get_repository("tuist/tuist")

      # Then
      assert repository ==
               {:ok,
                %VCS.Repositories.Repository{
                  default_branch: "main",
                  full_handle: "tuist/tuist",
                  provider: :github
                }}
    end
  end
end
