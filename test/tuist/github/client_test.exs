defmodule Tuist.GitHub.ClientTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Base64
  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.VCS.Repositories.Content
  alias Tuist.VCS.Repositories.Tag

  @default_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"Authorization", "token github_token"}
  ]

  @default_api_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"Authorization", "Bearer github_token"}
  ]

  setup do
    stub(App, :get_app_installation_token_for_repository, fn _ ->
      {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
    end)

    :ok
  end

  describe "get_comments/1" do
    test "returns comments" do
      # Given
      expect(Req, :get, fn [
                             finch: Tuist.Finch,
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
      stub(Req, :get, fn options ->
        headers = Keyword.get(options, :headers)
        [_json_header, auth_header] = headers
        {_, token} = auth_header

        if token == "token new_token" do
          {:ok, %Req.Response{status: 200, body: [%{"id" => "comment-id"}]}}
        else
          {:ok, %Req.Response{status: 401}}
        end
      end)

      stub(App, :get_app_installation_token_for_repository, fn _ ->
        stub(App, :get_app_installation_token_for_repository, fn _ ->
          {:ok, %{token: "new_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
        end)

        {:ok, %{token: "old_token", expires_at: ~U[2024-04-30 10:20:29Z]}}
      end)

      stub(App, :refresh_token, fn _ ->
        {:ok, %{token: "new_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
      end)

      # When
      comments = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:ok, [%Comment{id: "comment-id", client_id: nil}]}
    end

    test "returns a server error" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 500}}
      end)

      # When
      comments = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:error, "Unexpected status code: 500. Body: \"\""}
    end

    test "returns forbidden error" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 403}}
      end)

      # When
      comments = Client.get_comments(%{repository_full_handle: "tuist/tuist", issue_id: 1})

      # Then
      assert comments == {:error, "Unexpected status code: 403. Body: \"\""}
    end

    test "returns error when getting token fails" do
      # Given
      stub(App, :get_app_installation_token_for_repository, fn _ ->
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
      expect(Req, :post, fn [
                              finch: Tuist.Finch,
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
      expect(Req, :patch, fn [
                               finch: Tuist.Finch,
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
      expect(Req, :get, fn [
                             finch: Tuist.Finch,
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
      expect(Req, :get, fn [
                             finch: Tuist.Finch,
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
      stub(Req, :get, fn [
                           finch: Tuist.Finch,
                           headers: @default_headers,
                           url: "https://api.github.com/user/123"
                         ] ->
        {:ok, %Req.Response{status: 200, body: %{"login" => "tuist"}}}
      end)

      stub(
        Req,
        :get,
        fn [
             finch: Tuist.Finch,
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
      expect(Req, :get, fn [
                             finch: Tuist.Finch,
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

  describe "get_tags/1" do
    test "returns tags" do
      # Given
      stub(
        Req,
        :get,
        fn
          [
            url: "https://api.github.com/repos/tuist/tuist/tags?page_size=100",
            headers: @default_api_headers,
            finch: Tuist.Finch
          ] ->
            {:ok,
             %Req.Response{
               status: 200,
               headers: %{
                 "link" => [
                   ~s(<https://api.github.com/repos/tuist/tuist/tags?page=2>; rel="next", <https://api.github.com/repos/tuist/tuist/tags?page=2>; rel="last")
                 ]
               },
               body: [
                 %{"name" => "1.0.2"},
                 %{"name" => "1.0.1"}
               ]
             }}

          [
            url: "https://api.github.com/repos/tuist/tuist/tags?page=2&page_size=100",
            headers: @default_api_headers,
            finch: Tuist.Finch
          ] ->
            {:ok,
             %Req.Response{
               status: 200,
               headers: %{
                 "link" => [
                   "<https://api.github.com/repos/tuist/tuist/tags?page=2>; rel=\"last\""
                 ]
               },
               body: [
                 %{"name" => "1.0.0"}
               ]
             }}
        end
      )

      # When
      got = Client.get_tags(%{repository_full_handle: "tuist/tuist", token: "github_token"})

      # Then
      assert got == [%Tag{name: "1.0.2"}, %Tag{name: "1.0.1"}, %Tag{name: "1.0.0"}]
    end

    test "returns empty array when no tags exist" do
      # Given
      stub(
        Req,
        :get,
        fn
          [
            url: "https://api.github.com/repos/tuist/tuist/tags?page_size=100",
            headers: @default_api_headers,
            finch: Tuist.Finch
          ] ->
            {:ok,
             %Req.Response{
               status: 200,
               headers: %{
                 "link" => [
                   "<https://api.github.com/repos/tuist/tuist/tags?page=1>; rel=\"last\""
                 ]
               },
               body: []
             }}
        end
      )

      # When
      got = Client.get_tags(%{repository_full_handle: "tuist/tuist", token: "github_token"})

      # Then
      assert got == []
    end

    test "returns error when endpoint returns unexpected status code" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 404}}
      end)

      # When
      got = Client.get_tags(%{repository_full_handle: "tuist/tuist", token: "github_token"})

      # Then
      assert got ==
               {:error,
                "Unexpected status code: 404 when getting tags at https://api.github.com/repos/tuist/tuist/tags?page_size=100."}
    end
  end

  describe "get_source_archive_by_tag_and_repository_full_handle/1" do
    test "returns source archive" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 200, body: "File contents"}}
      end)

      # When
      got =
        Client.get_source_archive_by_tag_and_repository_full_handle(%{
          repository_full_handle: "Alamofire/Alamofire",
          tag: "5.10.0",
          token: "github_token"
        })

      # Then
      {:ok, _} = got
    end

    test "returns error when getting the source archive fails" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 404}}
      end)

      # When
      got =
        Client.get_source_archive_by_tag_and_repository_full_handle(%{
          repository_full_handle: "Alamofire/Alamofire",
          tag: "5.10.0",
          token: "github_token"
        })

      # Then
      assert got ==
               {:error,
                "Unexpected status code 404 when downloading Alamofire/Alamofire repository's source archive for 5.10.0 tag."}
    end
  end

  describe "get_repository_content/1" do
    test "returns contents array in a given repository" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{
               "path" => "Package.swift"
             },
             %{
               "path" => "Package@swift-5.9.swift"
             }
           ]
         }}
      end)

      # When
      got =
        Client.get_repository_content(%{
          repository_full_handle: "Alamofire/Alamofire",
          token: "github_token"
        })

      # Then
      assert got ==
               {:ok,
                [
                  %Content{
                    path: "Package.swift"
                  },
                  %Content{
                    path: "Package@swift-5.9.swift"
                  }
                ]}
    end

    test "returns file content in a given repository" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "path" => "Package.swift",
             "content" => "Package.swift encoded content"
           }
         }}
      end)

      stub(Base64, :decode, fn "Package.swift encoded content" -> "Package.swift content" end)

      # When
      got =
        Client.get_repository_content(
          %{
            repository_full_handle: "Alamofire/Alamofire",
            token: "github_token"
          },
          path: "Package.swift"
        )

      # Then
      assert got ==
               {:ok,
                %Content{
                  path: "Package.swift",
                  content: "Package.swift content"
                }}
    end

    test "returns :not_found error when the content does not exist" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 404}}
      end)

      # When
      got =
        Client.get_repository_content(%{
          repository_full_handle: "Alamofire/Alamofire",
          path: "Package.swift",
          token: "github_token"
        })

      # Then
      assert got ==
               {:error, :not_found}
    end

    test "returns unexpected error when the content does not exist" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 329}}
      end)

      # When
      got =
        Client.get_repository_content(%{
          repository_full_handle: "Alamofire/Alamofire",
          path: "Package.swift",
          token: "github_token"
        })

      # Then
      assert got ==
               {:error,
                "Unexpected status code: 329 when getting contents at https://api.github.com/repos/Alamofire/Alamofire/contents/."}
    end
  end
end
