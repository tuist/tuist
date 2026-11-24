defmodule TuistCommon.SentryHTTPClientTest do
  # The Pulse DSN is application config, which every test here changes.
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias TuistCommon.SentryHTTPClient

  defmodule Stub do
    @moduledoc false
    @behaviour Plug

    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(opts[:test], {opts[:name], conn.request_path, conn.req_headers, body})
      if delay = opts[:delay], do: Process.sleep(delay)
      Plug.Conn.send_resp(conn, 200, ~s({"id":"#{opts[:name]}"}))
    end
  end

  @body ~s({"event_id":"0f8e"}\n{"type":"event"}\n{"event_id":"0f8e","level":"error"}\n)
  @atlas_auth "Sentry sentry_version=7, sentry_client=sentry-elixir/11.0.4, sentry_timestamp=1, sentry_key=atlas-key, sentry_secret=atlas-secret"

  setup do
    on_exit(fn -> Application.delete_env(:tuist_common, :sentry_pulse_dsn) end)
    :ok
  end

  test "posts only to the Sentry DSN when no Pulse DSN is configured" do
    atlas = start_stub(:atlas)

    assert {:ok, 200, _headers, ~s({"id":"atlas"})} =
             SentryHTTPClient.post(
               "#{atlas}/api/1/envelope/",
               [{"X-Sentry-Auth", @atlas_auth}],
               @body
             )

    assert_receive {:atlas, "/api/1/envelope/", _headers, @body}
    refute_receive {:pulse, _, _, _}, 200
  end

  test "copies each envelope to Pulse with Pulse's credentials" do
    atlas = start_stub(:atlas)
    pulse = start_stub(:pulse)
    pulse_dsn("http://sentry:pulse-secret@#{URI.parse(pulse).authority}/v1/sentry/server/1")

    assert {:ok, 200, _headers, ~s({"id":"atlas"})} =
             SentryHTTPClient.post(
               "#{atlas}/api/1/envelope/",
               [{"X-Sentry-Auth", @atlas_auth}],
               @body
             )

    assert_receive {:atlas, "/api/1/envelope/", atlas_headers, @body}
    assert header(atlas_headers, "x-sentry-auth") == @atlas_auth

    assert_receive {:pulse, "/v1/sentry/server/api/1/envelope/", pulse_headers, @body}

    assert header(pulse_headers, "x-sentry-auth") ==
             "Sentry sentry_version=7, sentry_client=sentry-elixir/11.0.4, sentry_timestamp=1, " <>
               "sentry_key=sentry, sentry_secret=pulse-secret"
  end

  test "copies with only a key when the Pulse DSN has no secret, as the public endpoint's does" do
    atlas = start_stub(:atlas)
    pulse = start_stub(:pulse)
    # An account token's base64 `/`, `+` and `=` stay percent-encoded; the
    # server's SentryAuthPlug decodes them.
    pulse_dsn(
      "http://tuist_ab%2Bc%2Fd%3D@#{URI.parse(pulse).authority}/api/accounts/tuist/pulse/sentry/server/1"
    )

    SentryHTTPClient.post("#{atlas}/api/1/envelope/", [{"X-Sentry-Auth", @atlas_auth}], @body)

    assert_receive {:pulse, "/api/accounts/tuist/pulse/sentry/server/api/1/envelope/",
                    pulse_headers, @body}

    assert header(pulse_headers, "x-sentry-auth") ==
             "Sentry sentry_version=7, sentry_client=sentry-elixir/11.0.4, sentry_timestamp=1, " <>
               "sentry_key=tuist_ab%2Bc%2Fd%3D"
  end

  test "returns Atlas's response without waiting for a slow Pulse" do
    atlas = start_stub(:atlas)
    pulse = start_stub(:pulse, delay: 3_000)
    pulse_dsn("http://sentry:pulse-secret@#{URI.parse(pulse).authority}/v1/sentry/server/1")

    {elapsed_us, result} =
      :timer.tc(fn ->
        SentryHTTPClient.post("#{atlas}/api/1/envelope/", [{"X-Sentry-Auth", @atlas_auth}], @body)
      end)

    assert {:ok, 200, _headers, ~s({"id":"atlas"})} = result
    assert elapsed_us < 1_000_000
    assert_receive {:pulse, _path, _headers, @body}
  end

  test "delivers to Atlas without crash reports when Pulse is unreachable or its DSN is malformed" do
    atlas = start_stub(:atlas)

    for dsn <- [
          "http://sentry:pulse-secret@127.0.0.1:1/v1/sentry/server/1",
          "http://127.0.0.1:1/v1/sentry/server/1",
          "not a dsn"
        ] do
      pulse_dsn(dsn)

      # A crash report from the copy would reach Sentry's logger handler and be
      # reported, and copied, again.
      log =
        capture_log(fn ->
          assert {:ok, 200, _headers, ~s({"id":"atlas"})} =
                   SentryHTTPClient.post(
                     "#{atlas}/api/1/envelope/",
                     [{"X-Sentry-Auth", @atlas_auth}],
                     @body
                   )

          Process.sleep(200)
        end)

      assert_receive {:atlas, _path, _headers, @body}
      refute log =~ "terminating", "#{dsn}: #{log}"
    end
  end

  test "delivers to Atlas when the copy cannot be started" do
    atlas = start_stub(:atlas)
    pulse_dsn("http://sentry:pulse-secret@127.0.0.1:1/v1/sentry/server/1")

    stub(Task.Supervisor, :start_child, fn _supervisor, _fun ->
      exit({:noproc, {GenServer, :call, []}})
    end)

    assert {:ok, 200, _headers, ~s({"id":"atlas"})} =
             SentryHTTPClient.post(
               "#{atlas}/api/1/envelope/",
               [{"X-Sentry-Auth", @atlas_auth}],
               @body
             )

    assert_receive {:atlas, _path, _headers, @body}
  end

  defp start_stub(name, opts \\ []) do
    pid =
      start_supervised!(
        {Bandit,
         plug: {Stub, [name: name, test: self()] ++ opts},
         ip: :loopback,
         port: 0,
         startup_log: false},
        id: name
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  defp pulse_dsn(dsn), do: Application.put_env(:tuist_common, :sentry_pulse_dsn, dsn)

  defp header(headers, name), do: headers |> List.keyfind(name, 0) |> elem(1)
end
