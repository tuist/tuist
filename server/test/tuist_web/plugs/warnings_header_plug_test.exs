defmodule TuistWeb.WarningsHeaderPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Plug.Test

  alias Tuist.GitHub.Releases
  alias TuistWeb.Headers
  alias TuistWeb.WarningsHeaderPlug

  test "put_warning assigns the warning" do
    # Given
    conn = conn(:get, "/")

    # When
    conn =
      conn
      |> WarningsHeaderPlug.put_warning("warning 1")
      |> WarningsHeaderPlug.put_warning("warning 2")

    # Then
    assert conn.assigns[:warnings] == ["warning 2", "warning 1"]
  end

  describe "call/2" do
    test "it doesn't return the warnings if the version is lower than 4.11.0" do
      # Given
      Mimic.stub(Releases, :get_latest_cli_release, fn _opts -> %{name: "4.118.1"} end)

      conn =
        :get
        |> conn("/")
        |> WarningsHeaderPlug.put_warning("warning")
        |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.10.0")

      # When
      got = WarningsHeaderPlug.call(conn, %{})
      [before_send_hook] = got.private.before_send
      got = before_send_hook.(got)

      # Then
      assert Plug.Conn.get_resp_header(got, "x-tuist-cloud-warnings") == []
    end

    test "it returns the warnings if the version is higher or equal than 4.11.0" do
      # Given
      Mimic.stub(Releases, :get_latest_cli_release, fn _opts -> %{name: "4.118.1"} end)

      conn =
        :get
        |> conn("/")
        |> WarningsHeaderPlug.put_warning("warning")
        |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.11.0")

      # When
      got = WarningsHeaderPlug.call(conn, %{})
      [before_send_hook] = got.private.before_send
      got = before_send_hook.(got)

      # Then
      warning = got |> Plug.Conn.get_resp_header("x-tuist-cloud-warnings") |> List.first()

      assert Jason.decode!(Base.decode64!(warning)) == [
               "Your Tuist version 4.11.0 is deprecated. Please upgrade to version 4.118.1 for server-side features to continue working.",
               "warning"
             ]
    end

    test "it returns a deprecation warning if the version is lower than 4.118.1" do
      # Given
      Mimic.stub(Releases, :get_latest_cli_release, fn _opts -> %{name: "4.118.1"} end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.118.0")

      # When
      got = WarningsHeaderPlug.call(conn, %{})
      [before_send_hook] = got.private.before_send
      got = before_send_hook.(got)

      # Then
      warning = got |> Plug.Conn.get_resp_header("x-tuist-cloud-warnings") |> List.first()

      assert Jason.decode!(Base.decode64!(warning)) == [
               "Your Tuist version 4.118.0 is deprecated. Please upgrade to version 4.118.1 for server-side features to continue working."
             ]
    end

    test "it doesn't return a deprecation warning if the version is higher or equal than 4.118.1" do
      # Given
      Mimic.stub(Releases, :get_latest_cli_release, fn _opts -> %{name: "4.118.1"} end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.118.1")

      # When
      got = WarningsHeaderPlug.call(conn, %{})
      [before_send_hook] = got.private.before_send
      got = before_send_hook.(got)

      # Then
      assert Plug.Conn.get_resp_header(got, "x-tuist-cloud-warnings") == []
    end
  end
end
