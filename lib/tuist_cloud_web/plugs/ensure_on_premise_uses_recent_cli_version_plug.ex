defmodule TuistCloudWeb.EnsureOnPremiseUsesRecentCLIVersionPlug do
  @moduledoc ~S"""
  This plug ensures that the on-premise version of Tuist is up-to-date with the version of the CLI that is being used.
  """
  import Plug.Conn
  use TuistCloudWeb, :controller
  alias TuistCloud.Environment
  alias TuistCloudWeb.WarningsHeaderPlug

  def init(opts), do: opts

  def call(conn, _opts) do
    cli_release_date_string =
      conn |> get_req_header("x-tuist-cloud-cli-release-date") |> List.first()

    cli_version = conn |> get_req_header("x-tuist-cloud-cli-version") |> List.first()

    if cli_release_date_string != nil and Environment.on_premise?() do
      cli_release_date =
        cli_release_date_string |> String.replace(".", "-") |> Date.from_iso8601!()

      tuist_cloud_release_date = Environment.version().date

      diff = Date.diff(cli_release_date, tuist_cloud_release_date)

      cond do
        # Tuist is 15 days behind (warning)
        diff > 15 ->
          conn
          |> WarningsHeaderPlug.put_warning(
            "Your version of the Tuist server is 15 days behind the version of the CLI that you are using, #{cli_version}. Please update it to the latest version."
          )

        # Tuist is 4 months behind (warning)
        diff < -(30 * 4) ->
          conn
          |> WarningsHeaderPlug.put_warning(
            "Your version of the Tuist CLI is 4 months behind the version of the Tuist server that you are using. We recommend updating the CLI to the latest version."
          )

        true ->
          conn
      end
    else
      conn
    end
  end
end
