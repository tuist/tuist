defmodule TuistWeb.WarningsHeaderPlug do
  @moduledoc ~S"""
  A plug that provides an interface for storing warnings in the connection,
  which are then sent as a base64 encoded JSON in the `x-tuist-warnings` and
  `x-tuist-cloud-warnings` headers.
  """
  use TuistWeb, :controller

  alias Tuist.GitHub.Releases
  alias TuistWeb.Headers

  @assign_key :warnings

  @minimum_supported_cli_version Version.parse!("4.56.1")

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, &call_before_send/1)
  end

  defp call_before_send(conn) do
    warnings = conn.assigns[@assign_key] || []
    cli_version = Headers.get_cli_version(conn)

    latest_cli_version = get_latest_cli_version()
    warnings = maybe_add_cli_deprecation_warning(warnings, cli_version, latest_cli_version)

    cond do
      is_nil(cli_version) ->
        conn

      # There was a bug fixed in version 4.11.0 caused by the client-logic not base64-decoding
      # the header.
      not Enum.empty?(warnings) and
          Version.compare(cli_version, Version.parse!("4.10.2")) == :gt ->
        conn
        |> put_resp_header(
          "x-tuist-cloud-warnings",
          Base.encode64(Jason.encode!(warnings))
        )
        |> put_resp_header(
          "x-tuist-warnings",
          Base.encode64(Jason.encode!(warnings))
        )

      true ->
        conn
    end
  end

  defp get_latest_cli_version do
    case Releases.get_latest_cli_release(update_if_needed: false) do
      nil -> nil
      release -> release.name
    end
  end

  defp maybe_add_cli_deprecation_warning(warnings, cli_version, latest_cli_version) do
    if should_show_cli_deprecation_warning?(cli_version) do
      message =
        if latest_cli_version do
          "Your Tuist version #{cli_version} is deprecated. Please upgrade to version #{latest_cli_version} for server-side features to continue working."
        else
          "Your Tuist version #{cli_version} is deprecated. Please upgrade to the latest version for server-side features to continue working."
        end

      [message | warnings]
    else
      warnings
    end
  end

  defp should_show_cli_deprecation_warning?(nil), do: false

  defp should_show_cli_deprecation_warning?(cli_version) do
    Version.compare(cli_version, @minimum_supported_cli_version) == :lt
  end

  def put_warning(conn, warning) do
    assign(conn, @assign_key, [warning | conn.assigns[@assign_key] || []])
  end

  def get_warnings(conn) do
    conn.assigns[@assign_key] || []
  end
end
