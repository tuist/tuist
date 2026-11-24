defmodule LuftServerWeb.AuthEventsTest do
  @moduledoc """
  Every authentication event leaves one attributable log line (who, which
  session, which client, from where, and the outcome) and no credential.
  """
  # Raising the Logger level to capture `info` lines is node-wide.
  use LuftServerWeb.ConnCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias LuftServer.FakeTuist
  alias LuftServer.NativeAuth
  alias LuftServer.Repo
  alias LuftServer.Sessions.Session

  @verifier String.duplicate("v", 43)
  @user_agent "Luft/1.0 (iPhone; iOS 27.0)"

  setup do
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)
  end

  defp client(conn) do
    conn
    |> put_req_header("user-agent", @user_agent)
    |> put_req_header("cf-connecting-ip", "198.51.100.23")
    |> put_req_header("x-forwarded-for", "198.51.100.23, 172.70.1.2")
  end

  # The line for `event` with `outcome`, which must be the only one.
  defp event(log, event, outcome) do
    assert [line] =
             log
             |> String.split("\n")
             |> Enum.filter(&(&1 =~ "auth_event=#{event} auth_outcome=#{outcome} "))

    assert line =~ "client_address=198.51.100.23 forwarded_for=198.51.100.23,172.70.1.2"
    assert line =~ "user_agent=#{@user_agent} "
    line
  end

  defp native_request do
    %{
      "response_type" => "code",
      "client_id" => NativeAuth.client_id(),
      "redirect_uri" => "luft://oauth-callback",
      "state" => "native-state",
      "code_challenge_method" => "S256",
      "code_challenge" => :sha256 |> :crypto.hash(@verifier) |> Base.url_encode64(padding: false)
    }
  end

  defp token(params), do: build_conn() |> client() |> post("/oauth2/token", params)

  test "native sign-in, exchange, refresh retry and reuse, code replay and sign-out" do
    provider = FakeTuist.stub()
    client_id = NativeAuth.client_id()

    {{session, secrets}, log} =
      with_log([level: :info], fn ->
        authorize = build_conn() |> client() |> get("/oauth2/authorize", native_request())
        {upstream_code, query} = FakeTuist.authorize(provider, redirected_to(authorize))

        callback =
          authorize
          |> recycle()
          |> client()
          |> get("/auth/callback", %{"code" => upstream_code, "state" => query["state"]})

        %{"code" => code} =
          callback |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

        exchange = %{
          "grant_type" => "authorization_code",
          "client_id" => client_id,
          "redirect_uri" => "luft://oauth-callback",
          "code" => code,
          "code_verifier" => @verifier
        }

        credentials = exchange |> token() |> json_response(200)
        assert exchange |> token() |> json_response(400)

        refresh = %{
          "grant_type" => "refresh_token",
          "client_id" => client_id,
          "refresh_token" => credentials["refresh_token"]
        }

        rotated = refresh |> token() |> json_response(200)
        assert ^rotated = refresh |> token() |> json_response(200)

        Repo.update_all(Session,
          set: [refresh_replay_expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
        )

        assert refresh |> token() |> json_response(400)
        assert %{refresh | "refresh_token" => "unknown"} |> token() |> json_response(400)

        session = Repo.one!(from s in Session, where: s.user_sub == "42", select: s.id)

        assert build_conn()
               |> client()
               |> put_req_header("authorization", "Bearer " <> rotated["access_token"])
               |> post("/auth/logout")
               |> response(204)

        {session,
         [upstream_code, query["state"], query["nonce"], code, @verifier] ++
           Map.values(credentials) ++ Map.values(rotated)}
      end)

    who = "auth_client=#{client_id} user_sub=42 session_id=#{session} "

    for {name, outcome} <- [
          sign_in: :success,
          code_exchange: :success,
          code_exchange: :reused,
          refresh: :success,
          refresh: :retried,
          refresh: :reused,
          sign_out: :success
        ] do
      assert event(log, name, outcome) =~ who, "#{name} #{outcome} is not attributed"
    end

    assert event(log, :refresh, :invalid_grant) =~ "auth_client=#{client_id} client_address="
    assert event(log, :refresh, :reused) =~ "[warning] auth refresh reused"

    # Tuist's tokens, the upstream and native codes, PKCE verifier, state,
    # nonce and every Luft access and refresh token.
    for secret <- ["access-1", "refresh-1" | secrets], is_binary(secret) do
      refute log =~ secret
    end
  end

  test "browser sign-in, forged state, sign-out and a session Tuist revokes" do
    provider = FakeTuist.stub(expires_in: 0, refresh: :invalid_grant)

    {cookies, log} =
      with_log([level: :info], fn ->
        login = build_conn() |> client() |> get("/auth/login")
        {code, query} = FakeTuist.authorize(provider, redirected_to(login))

        assert login
               |> recycle()
               |> client()
               |> get("/auth/callback", %{"code" => code, "state" => "forged"})
               |> json_response(400)

        signed_in =
          login
          |> recycle()
          |> client()
          |> get("/auth/callback", %{"code" => code, "state" => query["state"]})

        # Tuist refuses the refresh, which ends the session.
        assert signed_in
               |> recycle()
               |> client()
               |> put_req_header("origin", "https://luft.test")
               |> get("/api/organizations")
               |> json_response(401)

        [signed_in.resp_cookies["__Host-Http-luft_session"].value, code, query["state"]]
      end)

    assert event(log, :sign_in, :invalid_state) =~ "auth_client=browser client_address="
    assert event(log, :sign_in, :success) =~ ~r/auth_client=browser user_sub=42 session_id=\S+ /

    assert event(log, :session_revoked, :reauthenticate) =~
             ~r/\[warning\] auth session_revoked reauthenticate/

    for secret <- ["access-1", "refresh-1" | cookies] do
      refute log =~ secret
    end
  end

  test "a forwarded header cannot split a log line" do
    log =
      capture_log([level: :info], fn ->
        build_conn()
        |> put_req_header("user-agent", "evil\n12:00:00.000 [warning] auth sign_in success")
        |> put_req_header("cf-connecting-ip", "not-an-ip")
        |> get("/auth/callback", %{"state" => "x"})
      end)

    assert event = Enum.find(String.split(log, "\n"), &(&1 =~ "auth_event=sign_in"))
    assert event =~ "client_address=127.0.0.1 "
    assert event =~ "user_agent=evil12:00:00.000 [warning] auth sign_in success [warning]"
    refute log =~ "\n12:00:00.000"
  end
end
