defmodule TuistWeb.WarningsHeaderPlug do
  @moduledoc ~S"""
  A plug that provides an interface for storing warnings in the connection,
  which are then sent as a base64 encoded JSON in the `x-tuist-cloud-warnings` header.
  """
  use TuistWeb, :controller

  alias TuistWeb.Headers

  @assign_key :warnings

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, &call_before_send/1)
  end

  defp call_before_send(conn) do
    warnings = conn.assigns[@assign_key] || []
    cli_version = Headers.get_cli_version(conn)

    cond do
      is_nil(cli_version) ->
        conn

      # There was a bug fixed in version 4.11.0 caused by the client-logic not base64-decoding
      # the header.
      not Enum.empty?(warnings) and Version.compare(cli_version, Version.parse!("4.10.2")) == :gt ->
        put_resp_header(
          conn,
          "x-tuist-cloud-warnings",
          Base.encode64(Jason.encode!(warnings))
        )

      true ->
        conn
    end
  end

  def put_warning(conn, warning) do
    assign(conn, @assign_key, [warning | conn.assigns[@assign_key] || []])
  end

  def get_warnings(conn) do
    conn.assigns[@assign_key] || []
  end
end
