defmodule TuistWeb.Headers do
  @moduledoc ~S"""
  Utilities to read headers from requests.
  """
  @cli_version_header "x-tuist-cloud-cli-version"

  def cli_version_header, do: @cli_version_header

  def get_cli_version(conn) do
    if cli_version_string = Plug.Conn.get_req_header(conn, cli_version_header()) |> List.first() do
      Version.parse!(cli_version_string)
    else
      nil
    end
  end
end
