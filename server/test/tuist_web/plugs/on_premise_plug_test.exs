defmodule TuistWeb.OnPremisePlugTest do
  use TuistTestSupport.Cases.ConnCase
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.OnPremisePlug

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    %{
      current_user: user,
      conn: conn
    }
  end

  describe "api_license_validation" do
    test "returns the same connection if it's not on-premise", %{conn: conn} do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      opts = OnPremisePlug.init(:api_license_validation)

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      assert got == conn
    end

    test "returns a halted connection with a JSON error if the license has expired", %{conn: conn} do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      stub(Tuist.License, :get_license, fn -> {:ok, %{valid: false}} end)
      opts = OnPremisePlug.init(:api_license_validation)

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      assert got.halted == true

      assert json_response(got, 422) == %{
               "message" => "The license has expired. Please, contact contact@tuist.dev to renovate it."
             }
    end

    test "includes a warning in the connection if the license will expire in less than 30 days",
         %{
           conn: conn
         } do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      now = Timex.set(DateTime.utc_now(), hour: 12, minute: 0, second: 0, microsecond: {0, 0})
      stub(Tuist.Time, :utc_now, fn -> now end)
      expiration_date = DateTime.shift(now, day: 15)

      stub(Tuist.License, :get_license, fn ->
        {:ok, %{valid: true, expiration_date: expiration_date}}
      end)

      opts = OnPremisePlug.init(:api_license_validation)

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      assert TuistWeb.WarningsHeaderPlug.get_warnings(got) ==
               [
                 "The license will expire in 15 days. Please, contact contact@tuist.dev to renovate it."
               ]
    end

    test "returns the same connection if it's on-premise and the license will expire in more than 30 days",
         %{conn: conn} do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      expiration_date = DateTime.shift(Tuist.Time.utc_now(), day: 35)

      stub(Tuist.License, :get_license, fn ->
        {:ok, %{valid: true, expiration_date: expiration_date}}
      end)

      opts = OnPremisePlug.init(:api_license_validation)

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      assert got == conn
    end
  end

  describe "warn_on_outdated_cli" do
    test "returns the same connection if the environment is not on premise", %{conn: conn} do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      opts = OnPremisePlug.init(:warn_on_outdated_cli)

      conn =
        conn
        |> put_req_header("x-tuist-cli-release-date", "2024.04.11")
        |> put_req_header("x-tuist-cli-version", "1.2.3")

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      assert got == conn
    end

    test "returns the same connection if the environment is on premise but the release date header is missing",
         %{conn: conn} do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      opts = OnPremisePlug.init(:warn_on_outdated_cli)
      conn = put_req_header(conn, "x-tuist-cli-version", "1.2.3")

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      assert got == conn
    end

    test "returns the same connection with a warning if the environment is on premise, the deprecated headers are used, and Tuist is more than 15 days behind",
         %{conn: conn} do
      # Given
      Tuist.Environment
      |> stub(:tuist_hosted?, fn -> false end)
      |> stub(:version, fn ->
        %Tuist.Environment.Version{major: 1, date: Date.from_iso8601!("2024-01-01")}
      end)

      opts = OnPremisePlug.init(:warn_on_outdated_cli)

      conn =
        conn
        |> put_req_header("x-tuist-cloud-cli-release-date", "2024.02.01")
        |> put_req_header("x-tuist-cloud-cli-version", "1.2.3")

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      [warning] = TuistWeb.WarningsHeaderPlug.get_warnings(got)

      assert warning ==
               "Your version of the Tuist server is 15 days behind the version of the CLI that you are using, 1.2.3. Please update it to the latest version."
    end

    test "returns the connection with a warning when it's on premise and Tuist is more than 15 days behind",
         %{conn: conn} do
      # Given
      Tuist.Environment
      |> stub(:tuist_hosted?, fn -> false end)
      |> stub(:version, fn ->
        %Tuist.Environment.Version{major: 1, date: Date.from_iso8601!("2024-01-01")}
      end)

      opts = OnPremisePlug.init(:warn_on_outdated_cli)

      conn =
        conn
        |> put_req_header("x-tuist-cli-release-date", "2024.02.01")
        |> put_req_header("x-tuist-cli-version", "1.2.3")

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      [warning] = TuistWeb.WarningsHeaderPlug.get_warnings(got)

      assert warning ==
               "Your version of the Tuist server is 15 days behind the version of the CLI that you are using, 1.2.3. Please update it to the latest version."
    end

    test "returns the connection with a warning when it's on premise and the CLI is more than one month behind",
         %{conn: conn} do
      # Given
      Tuist.Environment
      |> stub(:tuist_hosted?, fn -> false end)
      |> stub(:version, fn ->
        %Tuist.Environment.Version{major: 1, date: Date.from_iso8601!("2024-06-01")}
      end)

      opts = OnPremisePlug.init(:warn_on_outdated_cli)

      conn =
        conn
        |> put_req_header("x-tuist-cli-release-date", "2024.01.01")
        |> put_req_header("x-tuist-cli-version", "1.2.3")

      # When
      got = OnPremisePlug.call(conn, opts)

      # Then
      [warning] = TuistWeb.WarningsHeaderPlug.get_warnings(got)

      assert warning ==
               "Your version of the Tuist CLI is 4 months behind the version of the Tuist server that you are using. We recommend updating the CLI to the latest version."
    end
  end

  describe "forward_marketing_to_dashboard" do
    test "redirects to the login route when the user is not authenticated", %{
      conn: conn
    } do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      plug_opts = OnPremisePlug.init(:forward_marketing_to_dashboard)

      # When
      conn = OnPremisePlug.call(conn, plug_opts)

      # Then
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "redirects to the user's account projects page when the user is authenticated", %{
      current_user: current_user,
      conn: conn
    } do
      # Given
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      plug_opts = OnPremisePlug.init(:forward_marketing_to_dashboard)

      # When
      conn =
        conn
        |> Authentication.put_current_user(current_user)
        |> OnPremisePlug.call(plug_opts)

      # Then
      assert redirected_to(conn) == "/#{current_user.account.name}/projects"
    end
  end
end
