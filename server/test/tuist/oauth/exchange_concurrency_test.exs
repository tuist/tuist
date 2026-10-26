defmodule Tuist.OAuth.ExchangeConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.OAuth.Exchange
  alias Tuist.Repo

  defmodule Response do
    @moduledoc false
    def token_success(conn, _), do: Plug.Conn.send_resp(conn, 200, "ok")
    def token_error(conn, _), do: Plug.Conn.send_resp(conn, 400, "used")
  end

  for {grant, token_type} <- [
        {"authorization_code", "code"},
        {"authorization_code", "preauthorized_code"},
        {"refresh_token", "access_token"}
      ],
      carrier <- [:form, :request] do
    @tag grant: grant, token_type: token_type, carrier: carrier
    test "#{grant} (#{token_type}) via #{carrier} serializes independent connections", %{
      grant: grant,
      token_type: token_type,
      carrier: carrier
    } do
      value = Ecto.UUID.generate()

      token =
        Sandbox.unboxed_run(Repo, fn ->
          Repo.insert!(%Token{
            type: token_type,
            value: value,
            refresh_token: value,
            expires_at: System.system_time(:second) + 60
          })
        end)

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          hash = :crypto.hash(:sha256, value)
          Repo.delete_all(from(r in "refresh_replays", where: r.kind == "oauth" and r.token_hash == ^hash))
          Repo.delete_all(from(t in Token, where: t.id == ^token.id))
        end)
      end)

      parent = self()

      run = fn first? ->
        Sandbox.unboxed_run(Repo, fn ->
          %{rows: [[pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:database_connection, first?, pid})

          params = %{
            "grant_type" => grant,
            "client_id" => Ecto.UUID.generate(),
            "redirect_uri" => "https://example.test/callback"
          }

          key = if grant == "authorization_code", do: "code", else: "refresh_token"
          params = Map.put(params, key, value)
          body = if carrier == :request, do: %{"request" => jwt(params)}, else: params
          conn = :post |> Plug.Test.conn("/oauth2/token", body) |> Plug.Conn.fetch_query_params()

          authorize = fn request ->
            assert Map.fetch!(request, String.to_existing_atom(key)) == value
            current = Repo.get!(Token, token.id)
            revoked = if grant == "authorization_code", do: current.revoked_at, else: current.refresh_token_revoked_at

            if is_nil(revoked) do
              if first? do
                send(parent, {:entered, self()})

                receive do
                  :release -> :ok
                after
                  3_000 -> raise "test release missing"
                end
              end

              field = if grant == "authorization_code", do: :revoked_at, else: :refresh_token_revoked_at
              current |> Ecto.Changeset.change(%{field => DateTime.utc_now()}) |> Repo.update!()

              {:ok,
               %{
                 token: %Boruta.Oauth.Token{
                   type: "access_token",
                   value: "issued",
                   expires_at: System.system_time(:second) + 60
                 }
               }}
            else
              {:error, %Boruta.Oauth.Error{error: :invalid_grant, status: :bad_request, error_description: "used"}}
            end
          end

          Exchange.token(conn, Response, authorize: authorize).status
        end)
      end

      first = Task.async(fn -> run.(true) end)
      assert_receive {:database_connection, true, first_db}
      assert_receive {:entered, first_pid}
      second = Task.async(fn -> run.(false) end)

      try do
        assert_receive {:database_connection, false, second_db}
        refute first_db == second_db
        assert wait_for_lock(second_db, 100)
        send(first_pid, :release)
        assert Task.await(first) == 200
        assert Task.await(second) == 400
      after
        send(first_pid, :release)
        Task.shutdown(first, :brutal_kill)
        Task.shutdown(second, :brutal_kill)
      end
    end
  end

  defp jwt(claims) do
    Enum.map_join([%{"alg" => "none"}, claims], ".", fn value ->
      value |> JSON.encode!() |> Base.url_encode64(padding: false)
    end) <> "."
  end

  defp wait_for_lock(_pid, 0), do: false

  defp wait_for_lock(pid, remaining) do
    locked =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = $1", [pid]).rows == [[true]]
      end)

    if locked,
      do: true,
      else:
        (
          Process.sleep(10)
          wait_for_lock(pid, remaining - 1)
        )
  end
end
