defmodule TuistCloudWeb.WarningsHeaderPlug do
  @moduledoc ~S"""
  A plug that provides an interface for storing warnings in the connection,
  which are then sent as a base64 encoded JSON in the `x-cloud-warnings` header.
  """
  use TuistCloudWeb, :controller

  @assign_key :warnings

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      warnings = conn.assigns[@assign_key] || []

      case length(warnings) do
        0 ->
          conn

        _ ->
          put_resp_header(conn, "x-tuist-cloud-warnings", Base.encode64(Jason.encode!(warnings)))
      end
    end)
  end

  def put_warning(conn, warning) do
    conn |> assign(@assign_key, [warning | conn.assigns[@assign_key] || []])
  end

  def get_warnings(conn) do
    conn.assigns[@assign_key] || []
  end
end
