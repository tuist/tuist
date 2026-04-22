defmodule TuistWeb.Headers do
  @moduledoc ~S"""
  Utilities to read headers from requests.
  """
  @cli_version_header "x-tuist-cli-version"
  @client_feature_flags_header "x-tuist-feature-flags"

  def cli_version_header, do: @cli_version_header
  def client_feature_flags_header, do: @client_feature_flags_header

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

  def get_client_feature_flags(conn) do
    conn
    |> Plug.Conn.get_req_header(client_feature_flags_header())
    |> List.first()
    |> decode_client_feature_flags()
  end

  def get_client_feature_flag(conn, feature_name) do
    case normalize_client_feature_flag_name(feature_name) do
      normalized_feature_name when not is_nil(normalized_feature_name) ->
        MapSet.member?(get_client_feature_flags(conn), normalized_feature_name)

      _ ->
        false
    end
  end

  def put_client_feature_flags(conn, feature_flags) when is_list(feature_flags) or is_map(feature_flags) do
    encoded_feature_flags =
      feature_flags
      |> client_feature_flag_names()
      |> Enum.map(&normalize_client_feature_flag_name/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.join(",")

    if encoded_feature_flags == "" do
      conn
    else
      Plug.Conn.put_req_header(conn, client_feature_flags_header(), encoded_feature_flags)
    end
  end

  defp decode_client_feature_flags(nil), do: MapSet.new()

  defp decode_client_feature_flags(feature_flags) when is_binary(feature_flags) do
    feature_flags
    |> String.split(",", trim: true)
    |> Enum.reduce(MapSet.new(), fn feature_name, acc ->
      case normalize_client_feature_flag_name(feature_name) do
        nil -> acc
        normalized_feature_name -> MapSet.put(acc, normalized_feature_name)
      end
    end)
  end

  defp normalize_client_feature_flag_name(feature_name) when is_atom(feature_name) do
    feature_name
    |> Atom.to_string()
    |> normalize_client_feature_flag_name()
  end

  defp normalize_client_feature_flag_name(feature_name) when is_binary(feature_name) do
    feature_name
    |> String.trim()
    |> String.upcase()
    |> case do
      "" -> nil
      normalized_feature_name -> normalized_feature_name
    end
  end

  defp normalize_client_feature_flag_name(_), do: nil

  defp client_feature_flag_names(feature_flags) when is_map(feature_flags), do: Map.keys(feature_flags)
  defp client_feature_flag_names(feature_flags) when is_list(feature_flags), do: feature_flags
end
