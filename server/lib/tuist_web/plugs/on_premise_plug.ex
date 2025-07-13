defmodule TuistWeb.OnPremisePlug do
  @moduledoc """
  This module contains plugs specific to on-premise customers.
  """
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.License
  alias Tuist.Time
  alias TuistWeb.Authentication
  alias TuistWeb.WarningsHeaderPlug

  def init(:api_license_validation), do: :api_license_validation
  def init(:warn_on_outdated_cli), do: :warn_on_outdated_cli
  def init(:forward_marketing_to_dashboard), do: :forward_marketing_to_dashboard

  def call(conn, opts) do
    if Environment.tuist_hosted?() do
      conn
    else
      call_on_premise(conn, opts)
    end
  end

  def call_on_premise(conn, :api_license_validation) do
    case License.get_license() do
      {:ok, %{valid: true, expiration_date: expiration_date}} ->
        if Date.diff(expiration_date, Time.utc_now()) < 30 do
          TuistWeb.WarningsHeaderPlug.put_warning(
            conn,
            "The license will expire in #{DateTime.diff(expiration_date, Time.utc_now(), :day)} days. Please, contact contact@tuist.dev to renovate it."
          )
        else
          conn
        end

      {:ok, %{valid: true}} ->
        conn

      _ ->
        conn
        |> put_status(422)
        |> json(%{
          message: "The license has expired. Please, contact contact@tuist.dev to renovate it."
        })
        |> halt()
    end
  end

  def call_on_premise(conn, :warn_on_outdated_cli) do
    cli_release_date_string =
      conn |> get_req_header("x-tuist-cli-release-date") |> List.first()

    cli_release_date_string =
      if is_nil(cli_release_date_string) do
        conn |> get_req_header("x-tuist-cloud-cli-release-date") |> List.first()
      else
        cli_release_date_string
      end

    cli_version = conn |> get_req_header("x-tuist-cli-version") |> List.first()

    cli_version =
      if is_nil(cli_version) do
        conn |> get_req_header("x-tuist-cloud-cli-version") |> List.first()
      else
        cli_version
      end

    if cli_release_date_string != nil and not Environment.tuist_hosted?() do
      cli_release_date =
        cli_release_date_string |> String.replace(".", "-") |> Date.from_iso8601!()

      tuist_cloud_release_date = Environment.version().date

      diff = Date.diff(cli_release_date, tuist_cloud_release_date)

      cond do
        # Tuist is 15 days behind (warning)
        diff > 15 ->
          WarningsHeaderPlug.put_warning(
            conn,
            "Your version of the Tuist server is 15 days behind the version of the CLI that you are using, #{cli_version}. Please update it to the latest version."
          )

        # Tuist is 4 months behind (warning)
        diff < -(30 * 4) ->
          WarningsHeaderPlug.put_warning(
            conn,
            "Your version of the Tuist CLI is 4 months behind the version of the Tuist server that you are using. We recommend updating the CLI to the latest version."
          )

        true ->
          conn
      end
    else
      conn
    end
  end

  def call_on_premise(conn, :forward_marketing_to_dashboard) do
    current_user = Authentication.current_user(conn)

    if is_nil(current_user) do
      conn |> redirect(to: ~p"/users/log_in") |> halt()
    else
      conn |> redirect(to: Authentication.signed_in_path(current_user)) |> halt()
    end
  end
end
