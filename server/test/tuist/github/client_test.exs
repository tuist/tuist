defmodule Tuist.GitHub.ClientTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client
  alias Tuist.OAuth2.SSRFGuard
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
    stub(App, :get_installation_token, fn _installation_id, _opts ->
      {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
    end)

    :ok
  end

  describe "generate_jit_config/3" do
    test "uses the organization endpoint when it is available" do
      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/orgs/tuist/actions/runners/generate-jitconfig"
        assert opts[:headers] == @default_api_headers

        assert opts[:json] == %{
                 "labels" => ["self-hosted", "macOS", "ARM64", "tuist-macos"],
                 "name" => "runner-1",
                 "runner_group_id" => 1,
                 "work_folder" => "/Users/runner/work"
               }

        {:ok,
         %Req.Response{
           status: 201,
           body: %{
             "encoded_jit_config" => "jit-config",
             "runner" => %{"id" => 42, "name" => "runner-1"}
           }
         }}
      end)

      assert {:ok, %{encoded_jit_config: "jit-config", runner_id: 42, runner_name: "runner-1"}} =
               Client.generate_jit_config(
                 %{installation_id: "installation-id"},
                 "tuist",
                 %{
                   name: "runner-1",
                   labels: ["self-hosted", "macOS", "ARM64", "tuist-macos"],
                   work_folder: "/Users/runner/work",
                   repository_full_handle: "tuist/tuist"
                 }
               )
    end

    test "falls back to the repository endpoint for a personal account" do
      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/orgs/2sem/actions/runners/generate-jitconfig"
        {:ok, %Req.Response{status: 404, body: %{"message" => "Not Found"}}}
      end)

      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/2sem/gersanghelper/actions/runners/generate-jitconfig"

        {:ok,
         %Req.Response{
           status: 201,
           body: %{
             "encoded_jit_config" => "repository-jit-config",
             "runner" => %{"id" => 43, "name" => "runner-2"}
           }
         }}
      end)

      assert {:ok, %{encoded_jit_config: "repository-jit-config", runner_id: 43, runner_name: "runner-2"}} =
               Client.generate_jit_config(
                 %{installation_id: "installation-id"},
                 "2sem",
                 %{
                   name: "runner-2",
                   labels: ["self-hosted", "macOS", "ARM64", "tuist-macos"],
                   repository_full_handle: "2sem/gersanghelper"
                 }
               )
    end

    test "identifies a repository endpoint that returns not found" do
      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/orgs/2sem/actions/runners/generate-jitconfig"
        {:ok, %Req.Response{status: 404, body: %{"message" => "Not Found"}}}
      end)

      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/2sem/gersanghelper/actions/runners/generate-jitconfig"
        {:ok, %Req.Response{status: 404, body: %{"message" => "Not Found"}}}
      end)

      assert {:error, {:repository_jit_config_not_found, 404, %{"message" => "Not Found"}}} =
               Client.generate_jit_config(
                 %{installation_id: "installation-id"},
                 "2sem",
                 %{
                   name: "runner-3",
                   labels: ["self-hosted", "macOS", "ARM64", "tuist-macos"],
                   repository_full_handle: "2sem/gersanghelper"
                 }
               )
    end

    test "identifies a repository installation that has not accepted the administration permission" do
      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/orgs/2sem/actions/runners/generate-jitconfig"
        {:ok, %Req.Response{status: 404, body: %{"message" => "Not Found"}}}
      end)

      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/2sem/gersanghelper/actions/runners/generate-jitconfig"
        {:ok, %Req.Response{status: 403, body: %{"message" => "Forbidden"}}}
      end)

      assert {:error, {:repository_administration_permission_required, 403, %{"message" => "Forbidden"}}} =
               Client.generate_jit_config(
                 %{installation_id: "installation-id"},
                 "2sem",
                 %{
                   name: "runner-4",
                   labels: ["self-hosted", "macOS", "ARM64", "tuist-macos"],
                   repository_full_handle: "2sem/gersanghelper"
                 }
               )
    end
  end

  describe "get_comments/1" do
    test "returns comments" do
      # Given
      expect(Req, :get, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"

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
      comments =
        Client.get_comments(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          installation: %{installation_id: "installation-id"}
        })

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

      stub(App, :get_installation_token, fn _installation_id, _opts ->
        stub(App, :get_installation_token, fn _installation_id, _opts ->
          {:ok, %{token: "new_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
        end)

        {:ok, %{token: "old_token", expires_at: ~U[2024-04-30 10:20:29Z]}}
      end)

      stub(App, :clear_token, fn -> :ok end)

      # When
      comments =
        Client.get_comments(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          installation: %{installation_id: "installation-id"}
        })

      # Then
      assert comments == {:ok, [%Comment{id: "comment-id", client_id: nil}]}
    end

    test "returns a server error" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 500}}
      end)

      # When
      comments =
        Client.get_comments(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          installation: %{installation_id: "installation-id"}
        })

      # Then
      assert comments == {:error, "Unexpected status code: 500. Body: \"\""}
    end

    test "returns forbidden error" do
      # Given
      stub(Req, :get, fn _ ->
        {:ok, %Req.Response{status: 403}}
      end)

      # When
      comments =
        Client.get_comments(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          installation: %{installation_id: "installation-id"}
        })

      # Then
      assert comments == {:error, "Unexpected status code: 403. Body: \"\""}
    end

    test "returns error when getting token fails" do
      # Given
      stub(App, :get_installation_token, fn _installation_id, _opts ->
        {:error, "Failed to get token."}
      end)

      # When
      got =
        Client.get_comments(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          installation: %{installation_id: "installation-id"}
        })

      # Then
      assert got ==
               {:error, "Failed to get token."}
    end
  end

  describe "create_comment/1" do
    test "creates a new comment" do
      # Given
      expect(Req, :post, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:json] == %{body: "comment"}
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"

        {:ok, %Req.Response{status: 201}}
      end)

      # When
      response =
        Client.create_comment(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          body: "comment",
          installation: %{installation_id: "installation-id"}
        })

      # Then
      assert response == :ok
    end

    test "routes to a GitHub Enterprise Server API URL based on the installation's client_url" do
      # Given
      ghes_api_url = "https://github.example.com/api/v3"
      pinned_url = "https://198.51.100.10/api/v3/repos/tuist/tuist/issues/1/comments"

      stub(SSRFGuard, :pin, fn url ->
        assert url == "#{ghes_api_url}/repos/tuist/tuist/issues/1/comments"
        {:ok, pinned_url, "github.example.com"}
      end)

      stub(SSRFGuard, :connect_options, fn "github.example.com" -> [hostname: "github.example.com"] end)

      expect(Req, :post, fn opts ->
        # SSRF-pinned URL is passed to Req, with TLS hostname preserved
        assert opts[:url] == pinned_url
        assert opts[:connect_options] == [hostname: "github.example.com"]
        # api_url and installation should be stripped before reaching Req
        refute Keyword.has_key?(opts, :api_url)
        refute Keyword.has_key?(opts, :installation_id)
        refute Keyword.has_key?(opts, :installation)
        {:ok, %Req.Response{status: 201}}
      end)

      # When
      response =
        Client.create_comment(%{
          repository_full_handle: "tuist/tuist",
          issue_id: 1,
          body: "comment",
          installation: %{installation_id: "installation-id", client_url: "https://github.example.com"}
        })

      # Then
      assert response == :ok
    end
  end

  describe "GitHub Enterprise API proxies" do
    test "posts comments through the persisted proxy instead of the browser host" do
      installation = %Tuist.VCS.GitHubAppInstallation{
        installation_id: "123",
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/api/v3"
      }

      expect(App, :get_installation_token, fn ^installation, _ -> {:ok, %{token: "proxy-token"}} end)

      expect(SSRFGuard, :pin, fn url ->
        assert url == "#{installation.api_url}/repos/tuist/tuist/issues/1/comments"
        {:ok, "https://198.51.100.10/api/v3/repos/tuist/tuist/issues/1/comments", "proxy.example.com"}
      end)

      expect(SSRFGuard, :connect_options, fn "proxy.example.com" -> [hostname: "proxy.example.com"] end)

      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://198.51.100.10/api/v3/repos/tuist/tuist/issues/1/comments"
        assert opts[:redirect] == false
        assert opts[:connect_options] == [hostname: "proxy.example.com"]
        assert {"Authorization", "token proxy-token"} in opts[:headers]
        {:ok, %Req.Response{status: 201}}
      end)

      assert :ok =
               Client.create_comment(%{
                 repository_full_handle: "tuist/tuist",
                 issue_id: 1,
                 body: "comment",
                 installation: installation
               })
    end

    test "does not send authenticated requests to a private proxy IP" do
      installation = %{
        installation_id: "123",
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/api/v3"
      }

      expect(SSRFGuard, :pin, fn url ->
        assert url == "#{installation.api_url}/repos/tuist/tuist/issues/1/comments"
        {:error, :private_ip_resolved}
      end)

      reject(&Req.post/1)

      assert {:error, message} =
               Client.create_comment(%{
                 repository_full_handle: "tuist/tuist",
                 issue_id: 1,
                 body: "comment",
                 installation: installation
               })

      assert message =~ "SSRF"
    end
  end

  describe "API proxy repository pagination" do
    test "follows canonical Link headers through the proxy with its path prefix" do
      installation = %{
        installation_id: "123",
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/ghe/api/v3"
      }

      expect(SSRFGuard, :pin, 2, fn url ->
        assert String.starts_with?(url, installation.api_url)
        {:ok, String.replace(url, "proxy.example.com", "198.51.100.10"), "proxy.example.com"}
      end)

      stub(SSRFGuard, :connect_options, fn _ -> [] end)

      expect(Req, :get, 2, fn opts ->
        assert opts[:redirect] == false

        next =
          if String.contains?(opts[:url], "page=2"),
            do: nil,
            else: "#{installation.client_url}/api/v3/installation/repositories?page=2"

        headers = if next, do: %{"link" => ["<#{next}>; rel=\"next\""]}, else: %{}
        {:ok, %Req.Response{status: 200, body: %{"repositories" => []}, headers: headers}}
      end)

      assert {:ok, %{meta: %{next_url: next}}} = Client.list_installation_repositories(installation)
      assert {:ok, %{meta: %{next_url: nil}}} = Client.list_installation_repositories(installation, next_url: next)
    end

    test "refuses an unrelated pagination origin before minting or sending credentials" do
      installation = %{
        installation_id: "123",
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/api/v3"
      }

      reject(&App.get_installation_token/2)
      reject(&Req.get/1)

      assert {:error, _} =
               Client.list_installation_repositories(installation,
                 next_url: "https://attacker.example/api/v3/installation/repositories"
               )
    end
  end

  describe "update_comment/1" do
    test "updates comment" do
      # Given
      expect(Req, :patch, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:json] == %{body: "comment"}
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/comments/1"

        {:ok, %Req.Response{status: 201}}
      end)

      # When
      response =
        Client.update_comment(%{
          repository_full_handle: "tuist/tuist",
          comment_id: 1,
          body: "comment",
          installation: %{installation_id: "installation-id"}
        })

      # Then
      assert response == :ok
    end
  end

  describe "get_user_by_id/1" do
    test "returns user" do
      # Given
      expect(Req, :get, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/user/123"

        {:ok, %Req.Response{status: 200, body: %{"login" => "tuist"}}}
      end)

      # When
      user = Client.get_user_by_id(%{id: "123", installation: %{installation_id: "installation-id"}})

      # Then
      assert user == {:ok, %VCS.User{username: "tuist"}}
    end

    test "returns ok with 404 error" do
      # Given
      expect(Req, :get, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/user/123"

        {:ok, %Req.Response{status: 404, body: "Not found"}}
      end)

      # When
      user = Client.get_user_by_id(%{id: "123", installation: %{installation_id: "installation-id"}})

      # Then
      assert user == {:error, "Unexpected status code: 404. Body: \"Not found\""}
    end
  end

  describe "get_tags/1" do
    test "returns tags" do
      # Given
      stub(
        Req,
        :request,
        fn opts ->
          case Keyword.get(opts, :url) do
            "https://api.github.com/repos/tuist/tuist/tags?per_page=100" ->
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

            "https://api.github.com/repos/tuist/tuist/tags?page=2" ->
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
        :request,
        fn _opts ->
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
      stub(Req, :request, fn _ ->
        {:ok, %Req.Response{status: 404}}
      end)

      # When
      got = Client.get_tags(%{repository_full_handle: "tuist/tuist", token: "github_token"})

      # Then
      assert got ==
               {:error, {:http_error, 404}}
    end
  end

  describe "get_source_archive_by_tag_and_repository_full_handle/1" do
    test "returns source archive" do
      # Given
      stub(Req, :request, fn _ ->
        {:ok, %Req.Response{status: 200, body: ""}}
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
      stub(Req, :request, fn _ ->
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

  describe "list_installation_repositories/2" do
    test "returns repositories for a given installation without pagination" do
      # Given
      stub(App, :get_installation_token, fn %{installation_id: "123"}, _opts ->
        {:ok, %{token: "github_token"}}
      end)

      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://api.github.com/installation/repositories?per_page=100"
        assert opts[:headers] == @default_api_headers
        assert opts[:finch] == Tuist.Finch

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{},
           body: %{
             "repositories" => [
               %{
                 "id" => 123,
                 "name" => "tuist",
                 "full_name" => "tuist/tuist",
                 "private" => false,
                 "default_branch" => "main"
               },
               %{
                 "id" => 456,
                 "name" => "private-repo",
                 "full_name" => "tuist/private-repo",
                 "private" => true,
                 "default_branch" => "master"
               }
             ]
           }
         }}
      end)

      # When
      result = Client.list_installation_repositories(%{installation_id: "123"})

      # Then
      assert result ==
               {:ok,
                %{
                  meta: %{next_url: nil},
                  repositories: [
                    %{
                      id: 123,
                      name: "tuist",
                      full_name: "tuist/tuist",
                      private: false,
                      default_branch: "main"
                    },
                    %{
                      id: 456,
                      name: "private-repo",
                      full_name: "tuist/private-repo",
                      private: true,
                      default_branch: "master"
                    }
                  ]
                }}
    end

    test "returns repositories with pagination link" do
      # Given
      stub(App, :get_installation_token, fn %{installation_id: "123"}, _opts ->
        {:ok, %{token: "github_token"}}
      end)

      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://api.github.com/installation/repositories?per_page=100"
        assert opts[:headers] == @default_api_headers
        assert opts[:finch] == Tuist.Finch

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{
             "link" => [
               ~s(<https://api.github.com/installation/repositories?per_page=100&page=2>; rel="next", <https://api.github.com/installation/repositories?per_page=100&page=3>; rel="last")
             ]
           },
           body: %{
             "repositories" => [
               %{
                 "id" => 123,
                 "name" => "tuist",
                 "full_name" => "tuist/tuist",
                 "private" => false,
                 "default_branch" => "main"
               }
             ]
           }
         }}
      end)

      # When
      result = Client.list_installation_repositories(%{installation_id: "123"})

      # Then
      assert result ==
               {:ok,
                %{
                  meta: %{
                    next_url: "https://api.github.com/installation/repositories?per_page=100&page=2"
                  },
                  repositories: [
                    %{
                      id: 123,
                      name: "tuist",
                      full_name: "tuist/tuist",
                      private: false,
                      default_branch: "main"
                    }
                  ]
                }}
    end

    test "returns error when API returns non-200 status" do
      # Given
      stub(App, :get_installation_token, fn %{installation_id: "123"}, _opts ->
        {:ok, %{token: "github_token"}}
      end)

      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://api.github.com/installation/repositories?per_page=100"
        assert opts[:headers] == @default_api_headers
        assert opts[:finch] == Tuist.Finch

        {:ok,
         %Req.Response{
           status: 404,
           body: %{"message" => "Not Found"}
         }}
      end)

      # When
      result = Client.list_installation_repositories(%{installation_id: "123"})

      # Then
      assert result == {:error, "Failed to fetch repositories"}
    end

    test "handles empty repositories list" do
      # Given
      stub(App, :get_installation_token, fn %{installation_id: "123"}, _opts ->
        {:ok, %{token: "github_token"}}
      end)

      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://api.github.com/installation/repositories?per_page=100"
        assert opts[:headers] == @default_api_headers
        assert opts[:finch] == Tuist.Finch

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{},
           body: %{
             "repositories" => []
           }
         }}
      end)

      # When
      result = Client.list_installation_repositories(%{installation_id: "123"})

      # Then
      assert result == {:ok, %{meta: %{next_url: nil}, repositories: []}}
    end

    test "returns error when getting installation token fails" do
      # Given
      stub(App, :get_installation_token, fn %{installation_id: "123"}, _opts ->
        {:error, "Failed to get token"}
      end)

      # When
      result = Client.list_installation_repositories(%{installation_id: "123"})

      # Then
      assert result == {:error, "Failed to get token"}
    end
  end

  describe "get_repository_content/1" do
    test "returns contents array in a given repository" do
      stub(Req, :request, fn _ ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{"path" => "Package.swift"},
             %{"path" => "Package@swift-5.9.swift"}
           ]
         }}
      end)

      got =
        Client.get_repository_content(%{
          repository_full_handle: "Alamofire/Alamofire",
          token: "github_token"
        })

      assert got ==
               {:ok,
                [
                  %Content{path: "Package.swift"},
                  %Content{path: "Package@swift-5.9.swift"}
                ]}
    end

    test "returns file content in a given repository" do
      encoded_content = Base.encode64("Package.swift content")

      stub(Req, :request, fn _ ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "content" => encoded_content,
             "encoding" => "base64"
           }
         }}
      end)

      got =
        Client.get_repository_content(
          %{
            repository_full_handle: "Alamofire/Alamofire",
            token: "github_token"
          },
          path: "Package.swift"
        )

      assert got == {:ok, %Content{path: "Package.swift", content: "Package.swift content"}}
    end

    test "returns :not_found error when the content does not exist" do
      stub(Req, :request, fn _ ->
        {:ok, %Req.Response{status: 404}}
      end)

      got =
        Client.get_repository_content(%{
          repository_full_handle: "Alamofire/Alamofire",
          path: "Package.swift",
          token: "github_token"
        })

      assert got == {:error, :not_found}
    end

    test "returns unexpected error when the content does not exist" do
      stub(Req, :request, fn _ ->
        {:ok, %Req.Response{status: 329}}
      end)

      got =
        Client.get_repository_content(%{
          repository_full_handle: "Alamofire/Alamofire",
          path: "Package.swift",
          token: "github_token"
        })

      assert got == {:error, "Unexpected status code: 329 when getting contents."}
    end
  end

  describe "list_app_hook_deliveries/1" do
    setup do
      stub(App, :get_jwt, fn _opts -> {:ok, "app-jwt"} end)
      :ok
    end

    test "hits the App-wide endpoint with JWT auth and parses the metadata-only response" do
      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://api.github.com/app/hook/deliveries?per_page=100"

        headers = opts[:headers]
        assert {"Authorization", "Bearer app-jwt"} in headers
        assert {"Accept", "application/vnd.github+json"} in headers
        # No status filter — see worker moduledoc / docs.
        refute opts[:url] =~ "status="

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{},
           body: [
             %{
               "id" => 7_001,
               "guid" => "g-1",
               "delivered_at" => "2026-05-21T10:00:00Z",
               "redelivery" => false,
               "status" => "Internal Server Error",
               "status_code" => 500,
               "event" => "workflow_job",
               "action" => "queued",
               "installation_id" => 42,
               "repository_id" => 100
             }
           ]
         }}
      end)

      assert {:ok, %{meta: %{next_url: nil}, deliveries: [d]}} = Client.list_app_hook_deliveries()

      assert d.id == 7_001
      assert d.guid == "g-1"
      assert d.status_code == 500
      assert d.event == "workflow_job"
      assert d.action == "queued"
      assert d.installation_id == 42
      assert %DateTime{} = d.delivered_at
    end

    test "uses the GHES api_url and per-App credentials when supplied" do
      ghes_creds = %{app_id: "ghes-app", private_key: "pk", client_id: "cid"}

      expect(App, :get_jwt, fn opts ->
        assert Keyword.get(opts, :credentials) == ghes_creds
        assert Keyword.get(opts, :api_url) == "https://ghes.example.com/api/v3"
        {:ok, "ghes-jwt"}
      end)

      expect(SSRFGuard, :pin, fn url ->
        assert url == "https://ghes.example.com/api/v3/app/hook/deliveries?per_page=100"
        {:ok, "https://198.51.100.10/api/v3/app/hook/deliveries?per_page=100", "ghes.example.com"}
      end)

      stub(SSRFGuard, :connect_options, fn _ -> [hostname: "ghes.example.com"] end)

      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://198.51.100.10/api/v3/app/hook/deliveries?per_page=100"
        assert opts[:redirect] == false
        refute Keyword.has_key?(opts, :finch)
        assert {"Authorization", "Bearer ghes-jwt"} in opts[:headers]

        {:ok, %Req.Response{status: 200, headers: %{}, body: []}}
      end)

      assert {:ok, %{deliveries: []}} =
               Client.list_app_hook_deliveries(
                 credentials: ghes_creds,
                 api_url: "https://ghes.example.com/api/v3"
               )
    end

    test "rebases canonical webhook pagination onto a proxy path prefix" do
      expect(SSRFGuard, :pin, fn url ->
        assert url == "https://proxy.example.com/ghe/api/v3/app/hook/deliveries?cursor=next"
        {:ok, "https://198.51.100.10/ghe/api/v3/app/hook/deliveries?cursor=next", "proxy.example.com"}
      end)

      stub(SSRFGuard, :connect_options, fn _ -> [] end)

      expect(Req, :get, fn opts ->
        assert opts[:redirect] == false
        {:ok, %Req.Response{status: 200, body: [], headers: %{}}}
      end)

      assert {:ok, _} =
               Client.list_app_hook_deliveries(
                 client_url: "https://github.internal.example.com",
                 api_url: "https://proxy.example.com/ghe/api/v3",
                 next_url: "https://github.internal.example.com/api/v3/app/hook/deliveries?cursor=next"
               )
    end

    test "pins App-level endpoints on every call, refusing private IPs" do
      expect(SSRFGuard, :pin, 2, fn _ -> {:error, :private_ip_resolved} end)
      reject(&Req.get/1)
      reject(&Req.post/1)
      assert {:error, _} = Client.list_app_hook_deliveries(api_url: "https://proxy.example.com/api/v3")
      assert {:error, _} = Client.redeliver_app_hook_delivery(1, api_url: "https://proxy.example.com/api/v3")
    end

    test "surfaces the Link rel=\"next\" cursor for caller-driven pagination" do
      expect(Req, :get, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           headers: %{
             "link" => [
               "<https://api.github.com/app/hook/deliveries?cursor=v1_42>; rel=\"next\""
             ]
           },
           body: []
         }}
      end)

      assert {:ok, %{meta: %{next_url: next_url}}} = Client.list_app_hook_deliveries()
      assert next_url == "https://api.github.com/app/hook/deliveries?cursor=v1_42"
    end

    test "passes :next_url straight through (caller-driven pagination)" do
      cursor_url = "https://api.github.com/app/hook/deliveries?cursor=v1_99"

      expect(Req, :get, fn opts ->
        assert opts[:url] == cursor_url
        {:ok, %Req.Response{status: 200, headers: %{}, body: []}}
      end)

      assert {:ok, _} = Client.list_app_hook_deliveries(next_url: cursor_url)
    end

    test "returns {:error, {:http, status, body}} on non-200" do
      expect(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 403, body: %{"message" => "forbidden"}}}
      end)

      assert {:error, {:http, 403, %{"message" => "forbidden"}}} = Client.list_app_hook_deliveries()
    end

    test "returns {:error, {:transport, _}} on transport failure" do
      expect(Req, :get, fn _opts -> {:error, :timeout} end)

      assert {:error, {:transport, :timeout}} = Client.list_app_hook_deliveries()
    end

    test "returns {:error, _} when the App has no credentials configured" do
      expect(App, :get_jwt, fn _opts -> {:error, "GitHub App is not configured"} end)
      reject(&Req.get/1)

      assert {:error, _} = Client.list_app_hook_deliveries()
    end
  end

  describe "redeliver_app_hook_delivery/2" do
    setup do
      stub(App, :get_jwt, fn _opts -> {:ok, "app-jwt"} end)
      :ok
    end

    test "POSTs to the per-delivery attempts endpoint with JWT auth, treats 202 as success" do
      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.github.com/app/hook/deliveries/12345/attempts"
        assert {"Authorization", "Bearer app-jwt"} in opts[:headers]

        {:ok, %Req.Response{status: 202, body: %{}}}
      end)

      assert :ok = Client.redeliver_app_hook_delivery(12_345)
    end

    test "uses the per-App credentials and api_url when supplied (GHES path)" do
      ghes_creds = %{app_id: "ghes-app", private_key: "pk"}

      expect(App, :get_jwt, fn opts ->
        assert Keyword.get(opts, :credentials) == ghes_creds
        {:ok, "ghes-jwt"}
      end)

      expect(SSRFGuard, :pin, fn url ->
        assert url == "https://ghes.example.com/api/v3/app/hook/deliveries/777/attempts"
        {:ok, "https://198.51.100.10/api/v3/app/hook/deliveries/777/attempts", "ghes.example.com"}
      end)

      stub(SSRFGuard, :connect_options, fn _ -> [hostname: "ghes.example.com"] end)

      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://198.51.100.10/api/v3/app/hook/deliveries/777/attempts"
        assert opts[:redirect] == false
        refute Keyword.has_key?(opts, :finch)
        assert {"Authorization", "Bearer ghes-jwt"} in opts[:headers]

        {:ok, %Req.Response{status: 202, body: %{}}}
      end)

      assert :ok =
               Client.redeliver_app_hook_delivery(777,
                 credentials: ghes_creds,
                 api_url: "https://ghes.example.com/api/v3"
               )
    end

    test "returns {:error, {:http, _, _}} on non-202 (e.g. 422 Validation Failed)" do
      expect(Req, :post, fn _opts ->
        {:ok, %Req.Response{status: 422, body: %{"message" => "Validation Failed"}}}
      end)

      assert {:error, {:http, 422, _}} = Client.redeliver_app_hook_delivery(1)
    end

    test "returns {:error, {:transport, _}} on transport failure" do
      expect(Req, :post, fn _opts -> {:error, :econnrefused} end)

      assert {:error, {:transport, :econnrefused}} = Client.redeliver_app_hook_delivery(1)
    end
  end
end
