defmodule TuistWeb.ProjectAuthenticationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Ecto.Changeset
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.OIDCTrustPolicy
  alias TuistWeb.Errors.UnauthorizedError
  alias TuistWeb.Helpers.OpenGraph

  @policy_fields [:name, :issuer, :jwks_url, :audience, :claims]

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_project: project, current_user: user}} = socket) do
    authorize_project_update!(user, project)

    socket =
      socket
      |> assign(oidc_trust_policies: Projects.list_oidc_trust_policies(project))
      |> assign_empty_form()
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Authentication")} · #{project.name} · Tuist")
      |> assign(
        OpenGraph.project_image_assigns(project,
          title: dgettext("dashboard_projects", "Authentication"),
          fallback: "settings"
        )
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create_oidc_trust_policy", %{"oidc_trust_policy" => attrs}, socket) when is_map(attrs) do
    project = authorize_project_update!(socket)
    claims_input = Map.get(attrs, "claims", "")

    with {:ok, claims} <- decode_claims(claims_input),
         {:ok, _policy} <- Projects.create_oidc_trust_policy(project, Map.put(attrs, "claims", claims)) do
      {:noreply,
       socket
       |> assign(oidc_trust_policies: Projects.list_oidc_trust_policies(project))
       |> assign_empty_form()
       |> put_flash(:info, dgettext("dashboard_projects", "Trust policy added."))}
    else
      {:error, :invalid_claims_json, message} ->
        changeset =
          attrs
          |> Map.delete("claims")
          |> OIDCTrustPolicy.changeset()
          |> Changeset.add_error(:claims, message)
          |> Map.put(:action, :insert)

        {:noreply, assign_form(socket, changeset, claims_input)}

      # Errors added while rolling back a transaction, such as the policy
      # limit, come back without an action, and forms hide errors until one
      # is set.
      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, %{changeset | action: changeset.action || :insert}, claims_input)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(claims_input: claims_input)
         |> put_flash(:error, dgettext("dashboard_projects", "The trust policy could not be added."))}
    end
  end

  def handle_event("delete_oidc_trust_policy", %{"policy-id" => policy_id}, socket) do
    project = authorize_project_update!(socket)

    with {id, ""} <- Integer.parse(to_string(policy_id)),
         {:ok, _policy} <- Projects.delete_oidc_trust_policy(project, id) do
      {:noreply,
       socket
       |> assign(oidc_trust_policies: Projects.list_oidc_trust_policies(project))
       |> put_flash(:info, dgettext("dashboard_projects", "Trust policy removed."))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_projects", "Trust policy not found."))}
    end
  end

  # Claims are edited as a JSON object. Only the shape is checked here; the
  # changeset owns the rules for keys, value types, and size.
  defp decode_claims(input) when is_binary(input) and byte_size(input) <= 8192 do
    case input |> String.trim() |> JSON.decode() do
      {:ok, claims} when is_map(claims) ->
        {:ok, claims}

      {:ok, _other} ->
        {:error, :invalid_claims_json, dgettext("dashboard_projects", "Claims must be a JSON object.")}

      {:error, _reason} ->
        {:error, :invalid_claims_json, dgettext("dashboard_projects", "Claims must be valid JSON.")}
    end
  end

  defp decode_claims(_input) do
    {:error, :invalid_claims_json, dgettext("dashboard_projects", "Claims must be valid JSON of at most 8 KiB.")}
  end

  defp assign_empty_form(socket) do
    assign_form(socket, OIDCTrustPolicy.changeset(%{}), "")
  end

  defp assign_form(socket, changeset, claims_input) do
    socket
    |> assign(oidc_trust_policy_form: to_form(changeset, as: :oidc_trust_policy))
    |> assign(claims_input: claims_input)
    |> assign(form_errors: unrendered_errors(changeset))
  end

  # Errors that don't belong to an editable field would otherwise be invisible
  # in the form.
  defp unrendered_errors(%Changeset{action: nil}), do: []

  defp unrendered_errors(%Changeset{errors: errors}) do
    for {field, error} <- errors, field not in @policy_fields, do: translate_error(error)
  end

  defp field_error(%Phoenix.HTML.FormField{errors: [error | _]}), do: translate_error(error)
  defp field_error(_field), do: nil

  defp format_claims(claims) when is_map(claims) do
    claims
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key} = #{JSON.encode!(value)}" end)
  end

  defp format_claims(_claims), do: ""

  defp authorize_project_update!(socket) do
    project = Projects.get_project_by_id(socket.assigns.selected_project.id)
    authorize_project_update!(socket.assigns.current_user, project)
    project
  end

  defp authorize_project_update!(user, project) do
    if Authorization.authorize(:project_update, user, project) != :ok do
      raise UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end
  end
end
