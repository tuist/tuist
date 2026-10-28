defmodule Tuist.Origin.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.VCS.Comment

  @installation %Installation{app_id: "app_tuist", installation_id: "i_test"}
  @base "https://api.cursor.com/v1/origin"

  setup do
    key = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, pem} = JOSE.JWK.to_pem(key)
    stub(Environment, :origin_app_id, fn -> "app_tuist" end)
    stub(Environment, :origin_app_private_key, fn -> pem end)
    %{key: key}
  end

  test "signs an EdDSA app JWT with Origin's required identity", %{key: key} do
    assert {:ok, token} = Client.app_token()

    assert {true, %{fields: claims}, %{fields: header}} =
             JOSE.JWT.verify_strict(key, ["EdDSA"], token)

    assert header["kid"] == "app_tuist"
    assert header["typ"] == "JWT"
    assert claims["iss"] == "app_tuist"
    assert claims["aud"] == "origin-apps"
    assert claims["exp"] - claims["iat"] == 300
  end

  test "missing and malformed credentials fail without exposing the key" do
    stub(Environment, :origin_app_private_key, fn -> nil end)
    assert {:error, :origin_not_configured} = Client.app_token()
    stub(Environment, :origin_app_private_key, fn -> "invalid-private-key" end)
    assert {:error, :invalid_origin_key} = Client.app_token()
  end

  test "explicitly includes automatically approved metadata access in narrowed installation tokens" do
    expect(Req, :request, fn options ->
      assert options[:method] == :post
      assert options[:url] == @base <> "/app/installations/i_test/access_tokens"

      assert options[:json] == %{
               scopes: [
                 "repository:metadata:read",
                 "repository:pull_requests:read",
                 "repository:pull_requests:reviews:write"
               ]
             }

      assert Client.scopes() == ["repository:pull_requests:read", "repository:pull_requests:reviews:write"]
      assert {:bearer, token} = options[:auth]
      assert token != "i_test"
      {:ok, %Req.Response{status: 201, body: %{"token" => "oit_test"}}}
    end)

    assert {:ok, "oit_test"} = Client.installation_token(@installation)
  end

  test "rejects an installation belonging to a different app" do
    reject(&Req.request/1)

    assert {:error, :origin_app_mismatch} =
             Client.installation_token(%{@installation | app_id: "app_other"})
  end

  test "discovers installation repositories across pages without requesting extra scopes" do
    expect_token()

    expect(Req, :request, fn options ->
      assert options[:method] == :get
      assert options[:url] == @base <> "/installation/repos"
      assert options[:auth] == {:bearer, "oit_test"}
      assert options[:params] == [pageSize: 100]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "repositories" => [%{"fullName" => "acme/first"}],
           "nextPageToken" => "page2"
         }
       }}
    end)

    expect(Req, :request, fn options ->
      assert options[:url] == @base <> "/installation/repos"
      assert options[:params] == [pageSize: 100, pageToken: "page2"]
      {:ok, %Req.Response{status: 200, body: %{"repositories" => [%{"fullName" => "acme/second"}]}}}
    end)

    assert {:ok, [%{"fullName" => "acme/first"}, %{"fullName" => "acme/second"}]} =
             Client.list_repositories(@installation)
  end

  test "propagates repository discovery errors instead of returning an empty list" do
    expect_token()
    expect(Req, :request, fn _ -> {:ok, %Req.Response{status: 503, body: %{}}} end)
    assert {:error, {:origin_http_error, 503}} = Client.list_repositories(@installation)
  end

  test "finds an app-authored report on later comment pages" do
    expect_token()

    expect(Req, :request, fn options ->
      assert options[:params] == [pageSize: 100]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "comments" => [
             %{
               "id" => "human",
               "body" => "hello",
               "author" => %{"user" => %{"id" => "user_test"}}
             }
           ],
           "nextPageToken" => "page2"
         }
       }}
    end)

    expect(Req, :request, fn options ->
      assert options[:params] == [pageSize: 100, pageToken: "page2"]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "comments" => [
             %{
               "id" => "comment_test",
               "body" => "report",
               "author" => %{"app" => %{"id" => "app_tuist"}}
             }
           ]
         }
       }}
    end)

    assert {:ok, [%Comment{client_id: nil}, %Comment{id: "comment_test", client_id: "app_tuist"}]} =
             Client.get_comments(%{
               repository_full_handle: "acme/rocket",
               issue_id: 7,
               installation: @installation
             })
  end

  test "creates a general discussion comment and updates it with PATCH" do
    expect_token()

    params = %{
      repository_full_handle: "acme/rocket",
      issue_id: 7,
      body: "report",
      installation: @installation
    }

    expect(Req, :request, fn options ->
      assert options[:method] == :post
      assert options[:url] == @base <> "/repos/acme/rocket/pulls/7/comments"
      assert options[:auth] == {:bearer, "oit_test"}
      assert options[:json] == %{body: "report"}
      {:ok, %Req.Response{status: 201, body: %{"id" => "comment_test"}}}
    end)

    assert {:ok, %{"id" => "comment_test"}} = Client.create_comment(params)

    expect_token()

    expect(Req, :request, fn options ->
      assert options[:method] == :patch
      assert options[:url] == @base <> "/repos/acme/rocket/pulls/comments/comment_test"
      {:ok, %Req.Response{status: 200, body: %{}}}
    end)

    assert {:ok, %{}} = Client.update_comment(Map.put(params, :comment_id, "comment_test"))
  end

  test "a narrowed token can read metadata and verify native access before connecting an empty repository" do
    expect_token()
    repository = %{"fullName" => "acme/rocket", "defaultBranch" => "main"}

    expect(Req, :request, fn options ->
      assert options[:url] == @base <> "/repos/acme/rocket"
      assert options[:auth] == {:bearer, "oit_test"}
      {:ok, %Req.Response{status: 200, body: repository}}
    end)

    expect(Req, :request, fn options ->
      assert options[:url] == @base <> "/repos/acme/rocket/pulls"
      assert options[:params] == [pageSize: 1]
      assert options[:auth] == {:bearer, "oit_test"}
      {:ok, %Req.Response{status: 200, body: %{"pullRequests" => []}}}
    end)

    assert {:ok, ^repository} = Client.get_repository(@installation, "acme/rocket")
  end

  test "the native-repository probe rejects mirrors even when metadata omits mirror details" do
    expect_token()

    expect(Req, :request, fn options ->
      assert options[:url] == @base <> "/repos/acme/rocket"
      {:ok, %Req.Response{status: 200, body: %{"name" => "rocket"}}}
    end)

    expect(Req, :request, fn options ->
      assert options[:url] == @base <> "/repos/acme/rocket/pulls"
      assert options[:params] == [pageSize: 1]
      {:ok, %Req.Response{status: 404, body: %{}}}
    end)

    assert {:error, {:origin_http_error, 404}} =
             Client.get_repository(@installation, "acme/rocket")
  end

  test "HTTP errors are sanitized and writes are not automatically retried" do
    expect_token()

    expect(Req, :request, fn options ->
      assert options[:retry] == false
      assert options[:redirect] == false
      {:ok, %Req.Response{status: 429, body: %{"message" => "sensitive provider response"}}}
    end)

    assert {:error, {:origin_http_error, 429}} =
             Client.get_comments(%{
               repository_full_handle: "acme/rocket",
               issue_id: 7,
               installation: @installation
             })
  end

  test "rejects oversized Unicode comments before authenticating" do
    reject(&Req.request/1)

    assert {:error, :origin_comment_too_long} =
             Client.create_comment(%{
               repository_full_handle: "acme/rocket",
               issue_id: 7,
               body: String.duplicate("😀", 65_537),
               installation: @installation
             })
  end

  test "branch lookup ignores superseded heads rather than updating a newer PR" do
    expect_token()
    sha = String.duplicate("a", 40)

    stub(Req, :request, fn _ ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "pullRequests" => [
             %{
               "number" => "7",
               "head" => %{"ref" => "feature", "sha" => String.duplicate("b", 40)}
             }
           ]
         }
       }}
    end)

    assert {:error, :not_pull_request} =
             Client.get_pull_request_number(%{
               repository_full_handle: "acme/rocket",
               installation: @installation,
               git_ref: "refs/heads/feature",
               git_commit_sha: sha
             })
  end

  defp expect_token do
    expect(Req, :request, fn options ->
      assert options[:url] == @base <> "/app/installations/i_test/access_tokens"
      assert options[:json] == %{scopes: ["repository:metadata:read" | Client.scopes()]}
      {:ok, %Req.Response{status: 201, body: %{"token" => "oit_test"}}}
    end)
  end

  test "resolves an unambiguous current branch head" do
    expect_token()
    sha = String.duplicate("a", 40)

    expect(Req, :request, fn options ->
      assert options[:params][:headSha] == sha
      assert options[:params][:state] == "open"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "pullRequests" => [%{"number" => "7", "head" => %{"ref" => "feature", "sha" => sha}}]
         }
       }}
    end)

    assert {:ok, 7} =
             Client.get_pull_request_number(%{
               repository_full_handle: "acme/rocket",
               installation: @installation,
               git_ref: "feature",
               git_commit_sha: sha
             })
  end
end
