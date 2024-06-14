defmodule TuistCloudWeb.EnsureOnPremiseUsesRecentCLIVersionPlugTest do
  alias TuistCloudWeb.EnsureOnPremiseUsesRecentCLIVersionPlug
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  test "returns the same connection if the environment is not on premise", %{conn: conn} do
    # Given
    TuistCloud.Environment
    |> stub(:on_premise?, fn -> false end)

    opts = EnsureOnPremiseUsesRecentCLIVersionPlug.init([])

    conn =
      conn
      |> put_req_header("x-tuist-cloud-cli-release-date", "2024.04.11")
      |> put_req_header("x-tuist-cloud-cli-version", "1.2.3")

    # When
    got = EnsureOnPremiseUsesRecentCLIVersionPlug.call(conn, opts)

    # Then
    assert got == conn
  end

  test "returns the same connection if the environment is on premise but the release date header is missing",
       %{conn: conn} do
    # Given
    TuistCloud.Environment
    |> stub(:on_premise?, fn -> true end)

    opts = EnsureOnPremiseUsesRecentCLIVersionPlug.init([])
    conn = conn |> put_req_header("x-tuist-cloud-cli-version", "1.2.3")

    # When
    got = EnsureOnPremiseUsesRecentCLIVersionPlug.call(conn, opts)

    # Then
    assert got == conn
  end

  test "returns the connection with a warning when it's on premise and Tuist is more than 15 days behind",
       %{conn: conn} do
    # Given
    TuistCloud.Environment
    |> stub(:on_premise?, fn -> true end)
    |> stub(:version, fn ->
      %TuistCloud.Environment.Version{major: 1, date: Date.from_iso8601!("2024-01-01")}
    end)

    opts = EnsureOnPremiseUsesRecentCLIVersionPlug.init([])

    conn =
      conn
      |> put_req_header("x-tuist-cloud-cli-release-date", "2024.02.01")
      |> put_req_header("x-tuist-cloud-cli-version", "1.2.3")

    # When
    got = EnsureOnPremiseUsesRecentCLIVersionPlug.call(conn, opts)

    # Then
    [warning] = TuistCloudWeb.WarningsHeaderPlug.get_warnings(got)

    assert warning ==
             "Your version of the Tuist server is 15 days behind the version of the CLI that you are using, 1.2.3. Please update it to the latest version."
  end

  test "returns the connection with a warning when it's on premise and the CLI is more than one month behind",
       %{conn: conn} do
    # Given
    TuistCloud.Environment
    |> stub(:on_premise?, fn -> true end)
    |> stub(:version, fn ->
      %TuistCloud.Environment.Version{major: 1, date: Date.from_iso8601!("2024-06-01")}
    end)

    opts = EnsureOnPremiseUsesRecentCLIVersionPlug.init([])

    conn =
      conn
      |> put_req_header("x-tuist-cloud-cli-release-date", "2024.01.01")
      |> put_req_header("x-tuist-cloud-cli-version", "1.2.3")

    # When
    got = EnsureOnPremiseUsesRecentCLIVersionPlug.call(conn, opts)

    # Then
    [warning] = TuistCloudWeb.WarningsHeaderPlug.get_warnings(got)

    assert warning ==
             "Your version of the Tuist CLI is 4 months behind the version of the Tuist server that you are using. We recommend updating the CLI to the latest version."
  end
end
