defmodule TuistWeb.Headers do
  @moduledoc ~S"""
  Utilities to read headers from requests.
  """
  @cli_version_header "x-tuist-cloud-cli-version"

  def cli_version_header, do: @cli_version_header

  def get_cli_version(conn) do
    with {:version_string, version_string} when not is_nil(version_string) <-
           {:version_string, conn |> Plug.Conn.get_req_header(cli_version_header()) |> List.first()},
         {:version, {:ok, version}} <- {:version, Version.parse(version_string)} do
      version
    else
      _ -> nil
    end
  end
end
