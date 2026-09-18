defmodule AtlasWeb.LicenseCheckoutController do
  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Licenses
  alias Atlas.Users

  def show(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    cond do
      not Users.executive?(user) ->
        conn
        |> put_status(:forbidden)
        |> text("Licenses are only available to executives.")

      license = Licenses.get_license(id) ->
        check_out(conn, license, user)

      true ->
        conn
        |> put_status(:not_found)
        |> text("License not found.")
    end
  end

  defp check_out(conn, license, user) do
    result =
      Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
        Licenses.check_out_air_gapped(license)
      end)

    case result do
      {:ok, %{contents: contents, filename: filename}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_resp(:ok, contents)

      {:error, reason} ->
        conn
        |> put_flash(:error, Licenses.error_message(reason))
        |> redirect(to: ~p"/commercial/sales/licenses")
    end
  end
end
