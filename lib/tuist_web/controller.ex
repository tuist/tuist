defmodule TuistWeb.Controller do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Ecto.Changeset

  def handle_error(conn, :unauthorized) do
    render_error_response(conn, :unauthorized, "You are not authorized to view this resource.")
  end

  def handle_error(conn, :forbidden) do
    render_error_response(conn, :forbidden, "You are not authorized to view this resource.")
  end

  def handle_error(conn, :not_found) do
    render_error_response(conn, :not_found, "The resource could not be found.")
  end

  def handle_error(conn, %Changeset{} = changeset) do
    render_error_response(conn, :bad_request, changeset)
  end

  def handle_error(conn, reason) when is_binary(reason) do
    render_error_response(conn, :internal_server_error, reason)
  end

  def handle_error(conn, _) do
    render_error_response(conn, :internal_server_error, "An unexpected error occurred.")
  end

  defp render_error_response(conn, status, reason) do
    conn
    |> put_status(status)
    |> json(format_error(reason))
  end

  defp format_error(%Changeset{} = changeset) do
    fields =
      Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", safe_to_string(value))
        end)
      end)

    %{message: "There was an error handling your request.", fields: fields}
  end

  defp format_error(reason) when is_binary(reason) do
    %{message: reason}
  end

  defp safe_to_string(value) when is_binary(value), do: value
  defp safe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp safe_to_string(value) when is_float(value), do: Float.to_string(value)
  defp safe_to_string(_value), do: "Unknown"
end
