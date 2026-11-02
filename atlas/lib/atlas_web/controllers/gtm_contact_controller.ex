defmodule AtlasWeb.GTMContactController do
  @moduledoc """
  Loops-compatible contact endpoint for the PostHog signup destination.

  Mirrors `PUT https://app.loops.so/api/v1/contacts/update`, including the
  Bearer authentication and the `%{success: true}` response body, so the PostHog
  destination that used to write to Loops only needs a new URL and key.
  """

  use AtlasWeb, :controller

  alias Atlas.GTM
  alias AtlasWeb.GTMIngestAuth

  require Logger

  def update(conn, params) do
    with :ok <- GTMIngestAuth.authorize(conn),
         {:ok, result} <- GTM.upsert_email_contact(contact_payload(params)) do
      log_unknown_lists(result)

      conn
      |> put_status(:ok)
      |> json(%{success: true, id: result.subscriber.id, created: result.created})
    else
      {:error, :not_configured} ->
        Logger.warning("PostHog contact received but ATLAS_GTM_INGEST_TOKEN is not configured")
        conn |> put_status(:unauthorized) |> json(%{success: false, message: "not configured"})

      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{success: false, message: "invalid API key"})

      {:error, :email_missing} ->
        conn |> put_status(:bad_request) |> json(%{success: false, message: "email is required"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, message: "contact not saved", errors: changeset_errors(changeset)})
    end
  end

  # A JSON object body arrives as the params themselves. Only Phoenix's own keys
  # are dropped, so every other field stays available as a custom property. The
  # route takes no path params, so nothing else is injected here.
  defp contact_payload(params) do
    Map.drop(params, ["_json", "_format"])
  end

  defp log_unknown_lists(%{unknown_mailing_lists: [_ | _] = unknown, subscriber: subscriber}) do
    Logger.warning("Unknown mailing lists #{inspect(unknown)} for contact #{subscriber.email}")
  end

  defp log_unknown_lists(_result), do: :ok

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
