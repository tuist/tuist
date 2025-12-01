defmodule TuistWeb.Headers do
  @moduledoc ~S"""
  Utilities to read headers from requests.
  """
  @cli_version_header "x-tuist-cli-version"

  def cli_version_header, do: @cli_version_header

  def get_cli_version_string(conn) do
    case {:version_string, conn |> Plug.Conn.get_req_header(cli_version_header()) |> List.first()} do
      {:version_string, version_string} when not is_nil(version_string) -> version_string
      _ -> nil
    end
  end

  def get_cli_version(conn) do
    with version_string when not is_nil(version_string) <- get_cli_version_string(conn),
         {:ok, version} <- Version.parse(version_string) do
      version
    else
      _ ->
        nil
    end
  end

  def put_cli_version(conn, version) do
    Plug.Conn.put_req_header(conn, "x-tuist-cli-version", version)
  end
end
