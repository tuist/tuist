defmodule Tuist.OAuth.ExchangeConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.OAuth.Exchange
  alias Tuist.Repo

  defmodule OAuth do
    @moduledoc false
    def token(conn, application), do: conn.private.exchange.(conn, application)
  end

  defmodule Response do
    @moduledoc false
    def token_success(conn, _), do: Plug.Conn.send_resp(conn, 200, "ok")
    def token_error(conn, _), do: Plug.Conn.send_resp(conn, 400, "used")
  end

  for grant <- ["authorization_code", "refresh_token"] do
    @tag grant: grant
    test "#{grant} serializes independent database connections", %{grant: grant} do
      value = Ecto.UUID.generate()

      token =
        Sandbox.unboxed_run(Repo, fn ->
          Repo.insert!(%Token{
            type: if(grant == "authorization_code", do: "code", else: "access_token"),
            value: value,
            refresh_token: value,
            expires_at: System.system_time(:second) + 60
          })
        end)

      on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(from(t in Token, where: t.id == ^token.id)) end) end)
      parent = self()

      run = fn first? ->
        Sandbox.unboxed_run(Repo, fn ->
          %{rows: [[pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:database_connection, first?, pid})

          params =
            if grant == "authorization_code",
              do: %{"grant_type" => grant, "code" => value},
              else: %{"grant_type" => grant, "refresh_token" => value}

          conn = :post |> Plug.Test.conn("/oauth2/token", params) |> Map.put(:params, params)

          conn =
            Plug.Conn.put_private(conn, :exchange, fn conn, application ->
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
                application.token_success(conn, %Boruta.Oauth.TokenResponse{expires_in: 60})
              else
                application.token_error(conn, %Boruta.Oauth.Error{
                  error: :invalid_grant,
                  status: :bad_request,
                  error_description: "used"
                })
              end
            end)

          Exchange.token(conn, OAuth, Response).status
        end)
      end

      first = Task.async(fn -> run.(true) end)
      assert_receive {:database_connection, true, first_db}
      assert_receive {:entered, first_pid}
      second = Task.async(fn -> run.(false) end)
      assert_receive {:database_connection, false, second_db}
      refute first_db == second_db
      assert wait_for_lock(second_db, 100)
      send(first_pid, :release)
      assert Task.await(first) == 200
      assert Task.await(second) == 400
    end
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
