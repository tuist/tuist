defmodule TuistWeb.OrganizationAISettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts.ClaudeLinkedBilling
  alias Tuist.Accounts.OrganizationAI

  @impl true
  def mount(_params, _session, socket) do
    case OrganizationAI.settings(socket.assigns.current_user, socket.assigns.selected_account) do
      {:ok, configuration} ->
        {:ok,
         socket
         |> assign(:head_title, "#{dgettext("dashboard", "AI")} · #{socket.assigns.selected_account.name} · Tuist")
         |> assign(:provider_templates, OrganizationAI.provider_templates())
         |> assign(:configuration, configuration)
         |> assign(:claude_linking_available, ClaudeLinkedBilling.configured?())
         |> assign(:pending_removal, nil)
         |> assign(:removal_error, nil)
         |> assign(:connection_error, nil)
         |> assign(:model_error, nil)
         |> assign(:default_error, nil)
         |> assign(:route_error, nil)
         |> connection_form(%{})
         |> model_form(%{})
         |> route_form(%{})
         |> default_form(configuration)}

      {:error, _} ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_account", "The page you are looking for doesn't exist or has been moved.")
    end
  end

  @impl true
  def handle_event("change-connection", %{"_target" => ["connection", "provider"], "connection" => attrs}, socket) do
    template = Enum.find(socket.assigns.provider_templates, &(&1.id == attrs["provider"]))

    attrs =
      cond do
        template -> Map.merge(attrs, %{"name" => template.name, "base_url" => template.base_url})
        attrs["_id"] in [nil, ""] -> Map.merge(attrs, %{"name" => "", "base_url" => ""})
        true -> attrs
      end

    {:noreply,
     socket
     |> connection_form(attrs)
     |> assign(:connection_error, nil)}
  end

  def handle_event("change-connection", _, socket), do: {:noreply, socket}

  def handle_event("save-connection", %{"connection" => attrs}, socket) do
    case OrganizationAI.save_connection(socket.assigns.current_user, socket.assigns.selected_account, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh()
         |> connection_form(%{})
         |> assign(:connection_error, nil)
         |> push_event("close-modal", %{id: "organization-ai-connection-modal"})}

      {:error, :invalid_configuration} ->
        {:noreply,
         socket
         |> connection_form(attrs)
         |> assign(
           :connection_error,
           dgettext(
             "dashboard_account",
             "Check the provider details and enter a valid API key. Changing the provider or API base URL requires entering the key again."
           )
         )}

      {:error, _} ->
        {:noreply, unavailable(socket)}
    end
  end

  def handle_event("save-model", %{"model" => attrs}, socket) do
    case OrganizationAI.save_model(socket.assigns.current_user, socket.assigns.selected_account, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh()
         |> model_form(%{})
         |> assign(:model_error, nil)
         |> push_event("close-modal", %{id: "organization-ai-model-modal"})}

      {:error, :invalid_configuration} ->
        {:noreply,
         socket
         |> model_form(attrs)
         |> assign(
           :model_error,
           dgettext(
             "dashboard_account",
             "Enter a name and model ID, and select a provider. The model ID must be unique for the provider."
           )
         )}

      {:error, _} ->
        {:noreply, unavailable(socket)}
    end
  end

  def handle_event("change-route", %{"_target" => ["route", "category"], "route" => attrs}, socket) do
    {:noreply, socket |> route_form(Map.put(attrs, "task", "none")) |> assign(:route_error, nil)}
  end

  def handle_event("change-route", _, socket), do: {:noreply, socket}

  def handle_event("save-route", %{"route" => attrs}, socket) do
    case OrganizationAI.save_route(socket.assigns.current_user, socket.assigns.selected_account, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh()
         |> route_form(%{})
         |> assign(:route_error, nil)
         |> push_event("close-modal", %{id: "organization-ai-route-modal"})}

      {:error, :invalid_configuration} ->
        {:noreply,
         socket
         |> refresh()
         |> route_form(attrs)
         |> assign(
           :route_error,
           dgettext(
             "dashboard_account",
             "Choose a task and a model. Each task can have only one route."
           )
         )}

      {:error, _} ->
        {:noreply, unavailable(socket)}
    end
  end

  def handle_event("save-default", %{"default" => %{"model_id" => id}}, socket) do
    id = if id == "none", do: nil, else: id

    case OrganizationAI.set_default(socket.assigns.current_user, socket.assigns.selected_account, id) do
      {:ok, _} ->
        {:noreply, socket |> refresh() |> assign(:default_error, nil)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> refresh()
         |> assign(
           :default_error,
           dgettext("dashboard_account", "That model is no longer available. Choose another model.")
         )}

      {:error, _} ->
        {:noreply, unavailable(socket)}
    end
  end

  def handle_event("edit-connection", %{"id" => id}, socket), do: edit(socket, :connections, id)
  def handle_event("edit-model", %{"id" => id}, socket), do: edit(socket, :models, id)
  def handle_event("edit-route", %{"id" => id}, socket), do: edit(socket, :routes, id)

  def handle_event("add-connection", _, socket) do
    {:noreply,
     socket
     |> connection_form(%{})
     |> assign(:connection_error, nil)
     |> push_event("open-modal", %{id: "organization-ai-connection-modal"})}
  end

  def handle_event("add-model", _, socket) do
    {:noreply,
     socket
     |> model_form(%{})
     |> assign(:model_error, nil)
     |> push_event("open-modal", %{id: "organization-ai-model-modal"})}
  end

  def handle_event("add-route", _, socket) do
    {:noreply,
     socket
     |> route_form(%{})
     |> assign(:route_error, nil)
     |> push_event("open-modal", %{id: "organization-ai-route-modal"})}
  end

  def handle_event("cancel-route", _, socket) do
    {:noreply,
     socket
     |> route_form(%{})
     |> assign(:route_error, nil)
     |> push_event("close-modal", %{id: "organization-ai-route-modal"})}
  end

  def handle_event("cancel-connection", _, socket) do
    {:noreply,
     socket
     |> connection_form(%{})
     |> assign(:connection_error, nil)
     |> push_event("close-modal", %{id: "organization-ai-connection-modal"})}
  end

  def handle_event("cancel-model", _, socket) do
    {:noreply,
     socket
     |> model_form(%{})
     |> assign(:model_error, nil)
     |> push_event("close-modal", %{id: "organization-ai-model-modal"})}
  end

  def handle_event("remove-connection", %{"id" => id}, socket), do: confirm_removal(socket, :connections, id)
  def handle_event("remove-model", %{"id" => id}, socket), do: confirm_removal(socket, :models, id)
  def handle_event("remove-route", %{"id" => id}, socket), do: confirm_removal(socket, :routes, id)

  def handle_event("cancel-removal", _, socket) do
    {:noreply,
     socket
     |> assign(:pending_removal, nil)
     |> assign(:removal_error, nil)
     |> push_event("close-modal", %{id: "organization-ai-removal"})}
  end

  def handle_event("confirm-removal", _, %{assigns: %{pending_removal: %{kind: kind, id: id}}} = socket) do
    result =
      case kind do
        :connections -> OrganizationAI.remove_connection(socket.assigns.current_user, socket.assigns.selected_account, id)
        :models -> OrganizationAI.remove_model(socket.assigns.current_user, socket.assigns.selected_account, id)
        :routes -> OrganizationAI.remove_route(socket.assigns.current_user, socket.assigns.selected_account, id)
      end

    case result do
      {:ok, :ok} ->
        {:noreply,
         socket
         |> refresh()
         |> assign(:pending_removal, nil)
         |> assign(:removal_error, nil)
         |> connection_form(%{})
         |> model_form(%{})
         |> route_form(%{})
         |> push_event("close-modal", %{id: "organization-ai-removal"})}

      {:error, :unlink_failed} ->
        {:noreply,
         assign(
           socket,
           :removal_error,
           dgettext("dashboard_account", "Claude couldn't unlink your organization right now. Try again later.")
         )}

      {:error, _} ->
        {:noreply, unavailable(socket)}
    end
  end

  def handle_event("confirm-removal", _, socket), do: {:noreply, socket}

  defp edit(socket, kind, id) do
    with {:ok, configuration} <- OrganizationAI.settings(socket.assigns.current_user, socket.assigns.selected_account),
         record when not is_nil(record) <- Enum.find(configuration[kind], &(to_string(&1.id) == id)) do
      data = record |> Map.put(:_id, record.id) |> Map.new(fn {key, value} -> {to_string(key), value} end)
      socket = assign(socket, :configuration, configuration)

      {form, modal, error} =
        case kind do
          :connections -> {&connection_form/2, "organization-ai-connection-modal", :connection_error}
          :models -> {&model_form/2, "organization-ai-model-modal", :model_error}
          :routes -> {&route_form/2, "organization-ai-route-modal", :route_error}
        end

      {:noreply, socket |> form.(data) |> assign(error, nil) |> push_event("open-modal", %{id: modal})}
    else
      _ -> {:noreply, unavailable(socket)}
    end
  end

  defp confirm_removal(socket, kind, id) do
    with {:ok, configuration} <- OrganizationAI.settings(socket.assigns.current_user, socket.assigns.selected_account),
         record when not is_nil(record) <- Enum.find(configuration[kind], &(to_string(&1.id) == id)) do
      {:noreply,
       socket
       |> assign(:pending_removal, %{
         kind: kind,
         id: record.id,
         name: if(kind == :routes, do: task_label(record.task), else: record.name),
         linked?: Map.get(record, :kind) == "claude_linked_billing"
       })
       |> assign(:removal_error, nil)
       |> push_event("open-modal", %{id: "organization-ai-removal"})}
    else
      _ -> {:noreply, unavailable(socket)}
    end
  end

  defp refresh(socket) do
    case OrganizationAI.settings(socket.assigns.current_user, socket.assigns.selected_account) do
      {:ok, configuration} -> socket |> assign(:configuration, configuration) |> default_form(configuration)
      {:error, _} -> unavailable(socket)
    end
  end

  defp connection_form(socket, attrs) do
    # Passwords never survive a submission, even on validation failure.
    data =
      Map.merge(
        %{"_id" => "", "name" => "OpenAI", "base_url" => "https://api.openai.com/v1"},
        Map.take(attrs, ["_id", "name", "base_url", "provider"])
      )

    provider =
      Enum.find_value(socket.assigns.provider_templates, "custom", fn template ->
        if template.base_url == data["base_url"], do: template.id
      end)

    data = Map.put_new(data, "provider", provider)

    socket
    |> assign(:connection_form, to_form(Map.put(data, "api_key", ""), as: "connection"))
    |> assign(:connection_form_version, System.unique_integer([:positive]))
  end

  defp model_form(socket, attrs) do
    data =
      %{"_id" => "", "name" => "", "connection_id" => "none", "model_id" => ""}
      |> Map.merge(Map.take(attrs, ["_id", "name", "connection_id", "model_id"]))
      |> Map.update!("connection_id", &to_string/1)

    socket
    |> assign(:model_form, to_form(data, as: "model"))
    |> assign(:model_form_version, System.unique_integer([:positive]))
  end

  defp route_form(socket, attrs) do
    data =
      %{"_id" => "", "task" => "none", "model_id" => "none"}
      |> Map.merge(Map.take(attrs, ["_id", "category", "task", "model_id"]))
      |> Map.new(fn {key, value} -> {key, to_string(value)} end)

    # An edited route opens on its task's category; a new one on the first category.
    category =
      data["category"] ||
        Enum.find_value(OrganizationAI.tasks(), fn {task, category} ->
          if to_string(task) == data["task"], do: category
        end) ||
        hd(categories())

    socket
    |> assign(:route_form, to_form(Map.put(data, "category", to_string(category)), as: "route"))
    |> assign(:route_form_version, System.unique_integer([:positive]))
  end

  defp default_form(socket, configuration),
    do:
      assign(
        socket,
        :default_form,
        to_form(%{"model_id" => to_string(configuration.default_model_id || "none")}, as: "default")
      )

  defp claude_linked?(configuration), do: Enum.any?(configuration.connections, &(&1.kind == "claude_linked_billing"))

  defp connection_name(configuration, id), do: Enum.find(configuration.connections, &(&1.id == id)).name

  defp model(configuration, id), do: Enum.find(configuration.models, &(&1.id == id))

  defp model_label(configuration, model), do: "#{model.name} · #{connection_name(configuration, model.connection_id)}"

  defp categories, do: OrganizationAI.tasks() |> Keyword.values() |> Enum.uniq()

  defp category_of(task), do: Keyword.fetch!(OrganizationAI.tasks(), task)

  # Tasks in the form's category without a route other than the one being edited.
  defp route_task_options(configuration, form) do
    routed = for route <- configuration.routes, to_string(route.id) != form[:_id].value, do: route.task

    for {task, category} <- OrganizationAI.tasks(),
        to_string(category) == form[:category].value,
        task not in routed,
        do: task
  end

  defp unrouted_tasks?(configuration), do: length(configuration.routes) < length(OrganizationAI.tasks())

  defp category_label(:pulse), do: "Pulse"

  defp task_label(:pulse_grouping), do: dgettext("dashboard_account", "Group related observations")
  defp task_label(:pulse_explanation), do: dgettext("dashboard_account", "Name and explain symptoms")

  defp unavailable(socket), do: push_navigate(socket, to: ~p"/#{socket.assigns.selected_account.name}/settings")
end
