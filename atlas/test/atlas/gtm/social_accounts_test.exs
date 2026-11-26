defmodule Atlas.GTM.SocialAccountsTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [insert_user!: 1]

  alias Atlas.Connections.Config
  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialAccounts

  setup do
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    :ok
  end

  defp stub_x_oauth(test) do
    stub(Req, :request, fn opts ->
      case opts[:url] do
        "https://api.x.com/2/oauth2/token" ->
          assert opts[:auth] == {:basic, "test-client:test-secret"}
          refute Map.has_key?(opts[:form], "client_secret")
          grant = opts[:form]["grant_type"]
          send(test, {:token_request, grant})
          token = if grant == "refresh_token", do: "x-rotated", else: "x-access"

          response(%{
            "access_token" => token,
            "expires_in" => 7200,
            "refresh_token" => token <> "-refresh",
            "scope" => "tweet.read users.read offline.access"
          })

        "https://api.x.com/2/users/me" ->
          response(%{"data" => %{"id" => "1201413677729173505", "username" => "tuistdev"}})
      end
    end)
  end

  test "the grant belongs to the account: reconnecting updates it, and it outlives who connected it" do
    stub_x_oauth(self())
    first = insert_user!(%{scopes: ["gtm:write"]})
    second = insert_user!(%{scopes: ["gtm:write"]})

    assert {:ok, account} = SocialAccounts.connect(first, "brand", "code", "https://atlas.test/cb", "verifier")
    assert %{handle: "@tuistdev", kind: "brand", external_id: "1201413677729173505"} = account

    # Encrypted at rest.
    %{rows: [[stored]]} =
      Repo.query!("SELECT access_token FROM social_accounts WHERE id = $1", [Ecto.UUID.dump!(account.id)])

    refute stored =~ "x-access"

    assert {:ok, again} = SocialAccounts.connect(second, "personal", "code", "https://atlas.test/cb", "verifier")
    assert again.id == account.id
    assert %{kind: "personal", connected_by_id: second_id} = again
    assert second_id == second.id

    Repo.delete!(second)
    assert [%SocialAccount{id: id, connected_by: nil}] = SocialAccounts.list()
    assert id == account.id
  end

  test "connecting and disconnecting need gtm:write" do
    stub(Req, :request, fn _ -> flunk("readers must not reach X") end)
    reader = insert_user!(%{scopes: ["gtm:read"]})
    account = insert_account!()

    assert {:error, :forbidden} = SocialAccounts.connect(reader, "brand", "code", "https://atlas.test/cb", "v")
    assert {:error, :forbidden} = SocialAccounts.disconnect(reader, account.id)
    assert Repo.reload(account)

    writer = insert_user!(%{scopes: ["gtm:write"]})
    assert {:ok, _} = SocialAccounts.disconnect(writer, account.id)
    refute Repo.reload(account)
  end

  test "an expired token or a 401 refreshes the rotating grant once; a revoked one needs reconnecting" do
    test = self()
    stub_x_oauth(test)
    account = insert_account!(%{expires_at: DateTime.add(DateTime.utc_now(), -60, :second)})

    assert {:ok, "x-rotated"} = SocialAccounts.with_token(account, &{:ok, &1})
    assert_received {:token_request, "refresh_token"}
    assert Repo.reload!(account).refresh_token == "x-rotated-refresh"

    # X rejected a token it had not expired yet: refresh, then retry with the new one.
    fresh = insert_account!(%{access_token: "stale"})

    assert {:ok, "x-rotated"} =
             SocialAccounts.with_token(fresh, fn
               "stale" -> {:error, {:http, 401, "Unauthorized"}}
               token -> {:ok, token}
             end)

    stub(Req, :request, fn _ -> {:ok, %Req.Response{status: 400, body: %{"error" => "invalid_grant"}}} end)
    revoked = insert_account!(%{expires_at: DateTime.add(DateTime.utc_now(), -60, :second)})

    assert {:error, :needs_authorization} = SocialAccounts.with_token(revoked, &{:ok, &1})
    assert Repo.reload!(revoked).needs_authorization
  end

  defp insert_account!(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %SocialAccount{platform: "x", external_id: "acct#{n}"}
    |> SocialAccount.changeset(
      Map.merge(
        %{
          handle: "@acct#{n}",
          kind: "brand",
          access_token: "x-access",
          refresh_token: "x-refresh",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp response(body), do: {:ok, %Req.Response{status: 200, body: body}}
end
