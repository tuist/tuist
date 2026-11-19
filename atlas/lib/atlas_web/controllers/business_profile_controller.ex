defmodule AtlasWeb.BusinessProfileController do
  use AtlasWeb, :controller

  alias Atlas.Users.BusinessProfile

  def show(conn, _params), do: respond(conn, BusinessProfile.get(conn.assigns.current_user))

  def update(conn, _params),
    do: respond(conn, BusinessProfile.update(conn.assigns.current_user, conn.body_params, interface: "api"))

  defp respond(conn, {:ok, profile}), do: json(conn, %{business_profile: profile})
  defp respond(conn, {:error, _}), do: conn |> put_status(422) |> json(%{error: "invalid_business_profile"})
end
