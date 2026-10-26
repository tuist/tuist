defmodule Tuist.OAuth.UpstreamExchangeConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Token
  alias Boruta.Oauth.Authorization
  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.Exchange
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Oauth.TokenController

  @redirect_uri "https://example.test/callback"

  for grant <- ["authorization_code", "refresh_token"],
      {carrier, retry_carrier} <- [{:form, :form}, {:request, :request}, {:form, :request}, {:request, :form}] do
    @tag grant: grant, carrier: carrier, retry_carrier: retry_carrier
    test "real controller #{grant} via #{carrier}/#{retry_carrier} serializes redemption and reuse", %{
      grant: grant,
      carrier: carrier,
      retry_carrier: retry_carrier
    } do
      {client, token, credential} = fixture(grant)
      parent = self()

      run = fn first? ->
        Sandbox.unboxed_run(Repo, fn ->
          %{rows: [[pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:connection, first?, pid})
          key = if grant == "authorization_code", do: "code", else: "refresh_token"
          params = Map.put(params(client.id, grant), key, credential)
          request_carrier = if first?, do: carrier, else: retry_carrier
          body = if request_carrier == :request, do: %{"request" => jwt(params)}, else: params

          authorize = fn request ->
            assert Repo.in_transaction?()

            if first? do
              send(parent, {:entered, self()})

              receive do
                :release -> :ok
              after
                10_000 -> raise "test barrier was not released"
              end
            end

            Authorization.token(request)
          end

          expect(Exchange, :token, fn conn, application ->
            Mimic.call_original(Exchange, :token, [conn, application, [authorize: authorize]])
          end)

          conn = connection(body)
          response = TokenController.token(conn, conn.params)
          Mimic.verify!()
          response
        end)
      end

      first = Task.async(fn -> run.(true) end)
      assert_receive {:connection, true, first_db}, 5_000
      assert_receive {:entered, owner}, 5_000
      second = Task.async(fn -> run.(false) end)

      try do
        assert_receive {:connection, false, second_db}, 5_000
        refute first_db == second_db
        assert waiting_on_lock?(second_db, 100)
        send(owner, :release)
        successful = Task.await(first, 10_000)
        repeated = Task.await(second, 10_000)

        assert successful.status == 200,
               inspect(Map.take(JSON.decode!(successful.resp_body), ["error", "error_description"]))

        if grant == "refresh_token" do
          assert repeated.status == 200
          assert JSON.decode!(repeated.resp_body) == JSON.decode!(successful.resp_body)
        else
          assert repeated.status == 400
          assert %{"error" => "invalid_grant"} = JSON.decode!(repeated.resp_body)
        end

        assert %{"access_token" => issued} = JSON.decode!(successful.resp_body)
        assert {:ok, %{"scopes" => ["mcp"]}} = Tuist.Guardian.decode_and_verify(issued)

        Sandbox.unboxed_run(Repo, fn ->
          child = Repo.get_by!(Token, value: issued)
          current = Repo.get!(Token, token.id)

          if grant == "authorization_code" do
            assert current.revoked_at
            assert child.revoked_at
            assert Repo.aggregate(from(t in Token, where: t.previous_code == ^credential), :count) == 1
          else
            assert current.refresh_token_revoked_at
            assert is_nil(child.revoked_at)
            assert Repo.aggregate(from(t in Token, where: t.previous_token == ^token.value), :count) == 1
          end
        end)
      after
        send(owner, :release)
        Task.shutdown(first, :brutal_kill)
        Task.shutdown(second, :brutal_kill)
      end
    end
  end

  defp fixture(grant) do
    Sandbox.unboxed_run(Repo, fn ->
      user = AccountsFixtures.user_fixture()

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.delete_all(from(a in Account, where: a.id == ^user.account.id))
          Repo.delete_all(from(u in User, where: u.id == ^user.id))
        end)
      end)

      client =
        case Clients.create_client(%{
               redirect_uris: [@redirect_uri],
               pkce: false,
               confidential: false,
               public_refresh_token: true,
               authorize_scope: false
             }) do
          {:ok, client} -> client
          {:error, changeset} -> raise "invalid client fixture: #{inspect(changeset.errors)}"
        end

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          account_sub = Integer.to_string(user.account.id)

          Repo.delete_all(
            from(t in "guardian_tokens",
              where: field(t, :sub) == ^account_sub and fragment("?->>'client_id' = ?", field(t, :claims), ^client.id)
            )
          )

          token_hashes =
            from(t in Token, where: t.client_id == ^client.id and not is_nil(t.refresh_token), select: t.refresh_token)
            |> Repo.all()
            |> Enum.map(&:crypto.hash(:sha256, &1))

          Repo.delete_all(from(r in "refresh_token_replays", where: r.kind == "oauth" and r.token_hash in ^token_hashes))
          Repo.delete_all(from(t in Token, where: t.client_id == ^client.id))
          Repo.delete_all(from(c in Client, where: c.id == ^client.id))
        end)
      end)

      code =
        Repo.insert!(%Token{
          type: "code",
          value: Ecto.UUID.generate(),
          client_id: client.id,
          sub: Integer.to_string(user.id),
          scope: "mcp",
          redirect_uri: @redirect_uri,
          expires_at: System.system_time(:second) + 300
        })

      case grant do
        "authorization_code" ->
          {client, code, code.value}

        "refresh_token" ->
          conn = client.id |> params("authorization_code") |> Map.put("code", code.value) |> connection()
          response = Exchange.token(conn, TokenController)
          assert response.status == 200
          %{"refresh_token" => refresh} = JSON.decode!(response.resp_body)
          {client, Repo.get_by!(Token, refresh_token: refresh), refresh}
      end
    end)
  end

  defp params(client_id, grant), do: %{"grant_type" => grant, "client_id" => client_id, "redirect_uri" => @redirect_uri}

  defp connection(body),
    do: :post |> Plug.Test.conn("/oauth2/token?grant_type=refresh_token", body) |> Plug.Conn.fetch_query_params()

  defp jwt(claims),
    do:
      Enum.map_join([%{"alg" => "none"}, claims], ".", fn value ->
        value |> JSON.encode!() |> Base.url_encode64(padding: false)
      end) <> "."

  defp waiting_on_lock?(_pid, 0), do: false

  defp waiting_on_lock?(pid, attempts) do
    waiting =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = $1", [pid]).rows == [[true]]
      end)

    if waiting,
      do: true,
      else:
        (
          Process.sleep(10)
          waiting_on_lock?(pid, attempts - 1)
        )
  end
end
