defmodule Tuist.Origin.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Origin.Auth
  alias Tuist.Origin.Client

  setup do
    stub(Auth, :app_jwt, fn -> {:ok, "signed-app-jwt"} end)
    :ok
  end

  test "repository discovery follows Origin pagination with freshly minted installation tokens" do
    stub(Req, :request, fn opts ->
      refute opts[:redirect]
      refute opts[:retry]

      case {opts[:method], opts[:url]} do
        {:post, "https://api.cursor.com/v1/origin/app/installations/inst-1/access_tokens"} ->
          assert opts[:auth] == {:bearer, "signed-app-jwt"}
          {:ok, %{status: 200, body: %{"token" => "installation-token"}}}

        {:get, "https://api.cursor.com/v1/origin/installation/repos"} ->
          assert opts[:auth] == {:bearer, "installation-token"}

          body =
            if opts[:params][:pageToken] == "second",
              do: %{"repositories" => [%{"id" => "repo-2"}]},
              else: %{"repositories" => [%{"id" => "repo-1"}], "nextPageToken" => "second"}

          {:ok, %{status: 200, body: body}}
      end
    end)

    assert {:ok, [%{"id" => "repo-1"}, %{"id" => "repo-2"}]} = Client.repositories(%{installation_id: "inst-1"})
  end

  test "API rejection stays an error rather than producing empty feedback" do
    stub(Req, :request, fn _ -> {:ok, %{status: 403, body: %{}}} end)
    assert {:error, {:http, 403}} = Client.comments(%{installation_id: "inst-1"}, "org/repo", 3)
  end
end
