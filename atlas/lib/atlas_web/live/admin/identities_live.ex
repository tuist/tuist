defmodule AtlasWeb.Admin.IdentitiesLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.CheckboxControl, only: [checkbox_control: 1]

  alias Atlas.Agents
  alias Atlas.Agents.Identity
  alias Atlas.Slack
  alias Atlas.Slack.AgentIdentities
  alias Phoenix.HTML.Form

  @default_params %{
    "display_name" => "",
    "slack_app" => "company",
    "channel_ids" => "",
    "memory_scope" => "channel",
    "tool_groups" => ["finance", "documents"]
  }

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Identities"))
     |> assign(:slack_channel_options, Slack.list_available_channels())
     |> assign(:form, identity_form())
     |> assign_identities()}
  end

  def handle_event("create_identity", %{"identity" => params}, socket) do
    case Agents.create_identity(identity_attrs(params)) do
      {:ok, _identity} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Identity created."))
         |> assign(:form, identity_form())
         |> assign_identities()
         |> push_event("close-modal", %{id: "create-identity-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Could not create identity."))
         |> assign(:form, to_form(changeset, as: :identity))}
    end
  end

  def handle_event("change_identity_form", %{"identity" => params}, socket) do
    {:noreply, assign(socket, :form, identity_form(params))}
  end

  def handle_event("close-create-identity-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "create-identity-modal"})}
  end

  def handle_event("delete_identity", %{"id" => id}, socket) do
    with %Identity{} = identity <- Agents.get_identity(id),
         {:ok, _identity} <- Agents.delete_identity(identity) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Identity deleted."))
       |> assign_identities()}
    else
      _error ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete identity."))}
    end
  end

  def handle_event("select_identity_slack_workspace", params, socket) do
    slack_app = select_event_value(params) || "company"

    form_params =
      socket.assigns.form
      |> form_params()
      |> Map.put("slack_app", slack_app)
      |> Map.put("channel_ids", [])

    {:noreply, assign(socket, :form, identity_form(form_params))}
  end

  def handle_event("toggle_identity_channel", %{"value" => "_all"}, socket) do
    form_params =
      socket.assigns.form
      |> form_params()
      |> Map.put("channel_ids", [])

    {:noreply,
     socket
     |> assign(:form, identity_form(form_params))
     |> open_channel_dropdown()}
  end

  def handle_event("toggle_identity_channel", %{"value" => channel_id}, socket) do
    form_params = form_params(socket.assigns.form)
    workspace_options = channel_options_for_workspace(socket.assigns.slack_channel_options, form_params["slack_app"])
    valid_channel_ids = Enum.map(workspace_options, & &1.slack_channel_id)

    channel_ids =
      if channel_id in valid_channel_ids do
        toggle_selected_channel(form_params["channel_ids"], channel_id)
      else
        form_params["channel_ids"]
      end

    {:noreply,
     socket
     |> assign(:form, identity_form(Map.put(form_params, "channel_ids", channel_ids)))
     |> open_channel_dropdown()}
  end

  def render(assigns) do
    ~H"""
    <div id="admin-identities" data-part="admin-identities">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Identities")}</h1>
          <p data-part="description">
            {gettext("Manage the identities Atlas can assume in Slack.")}
          </p>
        </div>
        <div data-part="header-actions">
          <.button
            id="admin-slack-connect"
            href={~p"/slack/install"}
            label={gettext("Connect Slack")}
            size="medium"
            variant="secondary"
          >
            <:icon_left><.brand_slack /></:icon_left>
          </.button>

          <.form
            id="admin-identity-form"
            for={@form}
            as={:identity}
            phx-change="change_identity_form"
            phx-submit="create_identity"
          >
            <.modal
              id="create-identity-modal"
              title={gettext("Create identity")}
              description={
                gettext("Choose where Atlas can use this identity and what it can access.")
              }
              on_dismiss="close-create-identity-modal"
              header_type="icon"
              header_size="large"
              data-part="create-identity-modal"
            >
              <:header_icon><.user /></:header_icon>
              <:trigger :let={modal_attrs}>
                <.button
                  {modal_attrs}
                  id="admin-identity-create-trigger"
                  label={gettext("Create identity")}
                  size="medium"
                  type="button"
                >
                  <:icon_left><.plus /></:icon_left>
                </.button>
              </:trigger>

              <div data-part="identity-modal-content">
                <.line_divider />

                <div
                  id="admin-identity-modal-form"
                  data-part="identity-modal-form"
                  phx-hook="IdentityChannelDropdownScroll"
                >
                  <div data-part="form-grid">
                    <.text_input
                      id="admin-identity-display-name"
                      field={@form[:display_name]}
                      label={gettext("Name")}
                      required
                      show_required
                      show_suffix={false}
                    />

                    <div data-part="select-field">
                      <.label label={gettext("Slack workspace")} />
                      <.select
                        id="admin-identity-slack-app"
                        name={@form[:slack_app].name}
                        label={gettext("Select Slack workspace")}
                        value={select_value(field_value(@form, :slack_app))}
                        on_value_change="select_identity_slack_workspace"
                      >
                        <:item value="company" label={gettext("Company")} />
                      </.select>
                    </div>

                    <div data-part="select-field">
                      <.label label={gettext("Slack channels")} />
                      <input type="hidden" name={@form[:channel_ids].name <> "[]"} value="" />
                      <input
                        :for={channel_id <- selected_channel_ids(@form)}
                        type="hidden"
                        name={@form[:channel_ids].name <> "[]"}
                        value={channel_id}
                      />
                      <.dropdown
                        id="admin-identity-channel-dropdown"
                        data-part="channel-dropdown"
                        label={channel_dropdown_label(@form, @slack_channel_options)}
                        close_on_select={false}
                        on_select="toggle_identity_channel"
                      >
                        <:search :if={channel_options_for_form(@form, @slack_channel_options) != []}>
                          <%!-- No `name`: NooraDropdown filters this input client-side only. --%>
                          <input
                            id="admin-identity-channel-search"
                            type="text"
                            placeholder={gettext("Search channels...")}
                            data-part="search-input"
                          />
                        </:search>
                        <.dropdown_item
                          value="_all"
                          label={gettext("Every channel")}
                          checked={selected_channel_ids(@form) == []}
                        />
                        <.dropdown_item
                          :for={option <- channel_options_for_form(@form, @slack_channel_options)}
                          value={channel_option_value(option)}
                          label={channel_option_label(option)}
                          checked={selected_channel?(@form, option.slack_channel_id)}
                        />
                      </.dropdown>
                    </div>

                    <div data-part="select-field">
                      <.label label={gettext("Memory")} />
                      <.select
                        id="admin-identity-memory-scope"
                        name={@form[:memory_scope].name}
                        label={gettext("Select memory")}
                        value={select_value(field_value(@form, :memory_scope))}
                      >
                        <:item value="channel" label={gettext("Remember per channel")} />
                        <:item value="global" label={gettext("Share across channels")} />
                        <:item value="disabled" label={gettext("Do not remember")} />
                      </.select>
                    </div>

                    <div data-part="tool-access-field">
                      <.label label={gettext("Tool access")} />
                      <input type="hidden" name={@form[:tool_groups].name <> "[]"} value="" />
                      <div data-part="tool-option-list">
                        <label
                          :for={option <- tool_access_options()}
                          id={"admin-identity-tool-option-#{option.value}"}
                          data-part="tool-option"
                          for={"admin-identity-tool-#{option.value}"}
                        >
                          <input
                            id={"admin-identity-tool-#{option.value}"}
                            data-part="tool-input"
                            type="checkbox"
                            name={@form[:tool_groups].name <> "[]"}
                            value={option.value}
                            checked={selected_tool_group?(@form, option.value)}
                          />
                          <.checkbox_control
                            checked={selected_tool_group?(@form, option.value)}
                            data-part="tool-checkbox"
                          />
                          <span data-part="body">
                            <span data-part="label">{option.label}</span>
                            <span data-part="description">{option.description}</span>
                          </span>
                        </label>
                      </div>
                    </div>
                  </div>
                </div>

                <.line_divider />
              </div>

              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      label={gettext("Cancel")}
                      variant="secondary"
                      type="button"
                      phx-click="close-create-identity-modal"
                    />
                  </:action>
                  <:action>
                    <.button
                      id="admin-identity-create"
                      label={gettext("Create identity")}
                      type="submit"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </.form>
        </div>
      </div>

      <.card
        title={gettext("Persisted identities")}
        icon="user"
        data-part="persisted-identities-card"
      >
        <.card_section data-part="identities-table-section">
          <div
            :if={@identities_empty?}
            id="admin-persisted-identities-empty-state"
            data-part="identity-empty-state"
          >
            <.table_empty_state
              icon="user"
              title={gettext("No identities yet")}
              subtitle={gettext("Create the first identity from this panel.")}
            />
          </div>

          <.table
            :if={!@identities_empty?}
            id="admin-identities-table"
            rows={@streams.identities}
            row_key={fn {id, _identity} -> id end}
          >
            <:col :let={{_id, identity}} label={gettext("Identity")}>
              <.text_and_description_cell
                label={identity.display_name}
                description={slack_binding_label(identity)}
                icon="user"
              />
            </:col>
            <:col :let={{_id, identity}} label={gettext("Tools")}>
              <.text_cell label={tool_groups_label(identity)} />
            </:col>
            <:col :let={{_id, identity}} label={gettext("Memory")}>
              <.badge_cell
                id={"identity-memory-#{identity.id}"}
                label={memory_scope_label(identity.memory_scope)}
                color={memory_scope_color(identity.memory_scope)}
                style="light-fill"
              />
            </:col>
            <:col :let={{_id, identity}} label={gettext("Status")}>
              <.badge_cell
                id={"identity-status-#{identity.id}"}
                label={status_label(identity)}
                color={status_color(identity)}
                style="light-fill"
              />
            </:col>
            <:col :let={{_id, identity}} label={gettext("Actions")}>
              <.button_cell>
                <:button>
                  <.button
                    id={"delete-identity-#{identity.id}"}
                    label={gettext("Delete")}
                    variant="destructive"
                    size="small"
                    type="button"
                    phx-click="delete_identity"
                    phx-value-id={identity.id}
                    data-confirm={gettext("Delete this identity? This cannot be undone.")}
                  />
                </:button>
              </.button_cell>
            </:col>
          </.table>
        </.card_section>
      </.card>

      <.card
        title={gettext("Configured identities")}
        icon="settings"
        data-part="configured-identities-card"
      >
        <.card_section id="admin-configured-identities-list" data-part="identities-table-section">
          <div
            :if={@configured_identities_empty?}
            id="admin-configured-identities-empty-state"
            data-part="identity-empty-state"
          >
            <.table_empty_state
              icon="settings"
              title={gettext("No configured identities")}
              subtitle={gettext("Configured identities will appear here.")}
            />
          </div>

          <.table
            :if={!@configured_identities_empty?}
            id="admin-configured-identities-table"
            rows={@configured_identity_rows}
            row_key={fn {_identity, index} -> "configured-identities-#{index}" end}
          >
            <:col :let={{identity, _index}} label={gettext("Identity")}>
              <.text_and_description_cell
                label={identity.display_name}
                description={slack_binding_label(identity)}
                icon="user"
              />
            </:col>
            <:col :let={{identity, _index}} label={gettext("Tools")}>
              <.text_cell label={tool_groups_label(identity)} />
            </:col>
            <:col :let={{identity, _index}} label={gettext("Memory")}>
              <.badge_cell
                label={memory_scope_label(identity.memory_scope)}
                color={memory_scope_color(identity.memory_scope)}
                style="light-fill"
              />
            </:col>
            <:col :let={{_identity, index}} label={gettext("Source")}>
              <.badge_cell
                id={"configured-identity-source-#{index}"}
                label={gettext("Configured")}
                color="information"
                style="light-fill"
              />
            </:col>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp assign_identities(socket) do
    identities = Agents.list_identities()
    configured_identities = AgentIdentities.configured_identities()

    socket
    |> assign(:identities_empty?, identities == [])
    |> assign(:configured_identities_empty?, configured_identities == [])
    |> assign(:configured_identity_rows, Enum.with_index(configured_identities))
    |> stream(:identities, identities, reset: true)
  end

  defp identity_form(params \\ @default_params), do: to_form(params, as: :identity)

  defp form_params(form) do
    %{
      "display_name" => field_value(form, :display_name) || "",
      "slack_app" => field_value(form, :slack_app) || "company",
      "channel_ids" => selected_channel_ids(form),
      "memory_scope" => field_value(form, :memory_scope) || "channel",
      "tool_groups" => selected_tool_groups(field_value(form, :tool_groups))
    }
  end

  defp identity_attrs(params) do
    tool_groups = selected_tool_groups(params["tool_groups"])
    conversation_groups = Enum.filter(tool_groups, &(&1 in ["finance", "documents"]))
    systems_groups = Enum.filter(tool_groups, &(&1 in ["observability"]))
    channel_ids = split_list(params["channel_ids"])

    %{
      key: key_from_display_name(params["display_name"]),
      display_name: params["display_name"],
      enabled: true,
      bindings: %{
        slack: %{
          app: params["slack_app"],
          channel_ids: channel_ids,
          match_all_channels: channel_ids == []
        }
      },
      persona: :leadership,
      tool_groups: Enum.uniq(conversation_groups ++ systems_groups),
      tool_groups_by_agent: %{
        conversation: conversation_groups,
        systems_investigator: systems_groups
      },
      service_user_email: nil,
      memory_scope: params["memory_scope"],
      requester_rules: %{"finance" => "executive"}
    }
  end

  defp key_from_display_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-_")
  end

  defp key_from_display_name(_value), do: ""

  defp selected_tool_groups(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp selected_tool_groups(value) when is_binary(value), do: split_list(value)
  defp selected_tool_groups(_value), do: []

  defp selected_channel_ids(form), do: form |> field_value(:channel_ids) |> split_list()

  defp selected_channel?(form, channel_id), do: channel_id in selected_channel_ids(form)

  defp toggle_selected_channel(channel_ids, channel_id) do
    channel_ids = split_list(channel_ids)

    if channel_id in channel_ids do
      Enum.reject(channel_ids, &(&1 == channel_id))
    else
      channel_ids ++ [channel_id]
    end
  end

  defp split_list(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp split_list(values) when is_list(values) do
    values
    |> Enum.flat_map(&split_list/1)
    |> Enum.uniq()
  end

  defp split_list(_value), do: []

  defp field_value(form, field), do: Form.input_value(form, field)

  defp select_event_value(%{"value" => [value | _values]}), do: value
  defp select_event_value(%{"value" => value}) when is_binary(value), do: value
  defp select_event_value(_params), do: nil

  defp selected_tool_group?(form, group), do: group in selected_tool_groups(field_value(form, :tool_groups))

  defp select_value(nil), do: nil
  defp select_value(value) when is_atom(value), do: Atom.to_string(value)
  defp select_value(value), do: to_string(value)

  defp open_channel_dropdown(socket) do
    push_event(socket, "open-dropdown", %{id: "admin-identity-channel-dropdown"})
  end

  defp channel_options_for_form(form, options) do
    channel_options_for_workspace(options, field_value(form, :slack_app))
  end

  defp channel_options_for_workspace(options, workspace) do
    workspace = select_value(workspace)

    options
    |> Enum.filter(&(select_value(&1.slack_app) == workspace))
    |> Enum.sort_by(&channel_option_sort_key/1)
  end

  defp channel_option_sort_key(option) do
    name = option.name || ""
    {String.downcase(name), name, option.slack_channel_id}
  end

  defp channel_option_value(option), do: option.slack_channel_id
  defp channel_option_label(option), do: "##{option.name}"

  defp channel_dropdown_label(form, options) do
    case selected_channel_ids(form) do
      [] ->
        gettext("Every channel")

      [channel_id] ->
        form
        |> channel_options_for_form(options)
        |> Enum.find(&(channel_option_value(&1) == channel_id))
        |> case do
          nil -> channel_id
          option -> channel_option_label(option)
        end

      channel_ids ->
        gettext("%{count} channels", count: length(channel_ids))
    end
  end

  defp memory_scope_label(:channel), do: gettext("Channel memory")
  defp memory_scope_label("channel"), do: gettext("Channel memory")
  defp memory_scope_label(:disabled), do: gettext("Memory disabled")
  defp memory_scope_label("disabled"), do: gettext("Memory disabled")
  defp memory_scope_label(_scope), do: gettext("Global memory")

  defp memory_scope_color(scope) when scope in [:disabled, "disabled"], do: "neutral"
  defp memory_scope_color(_scope), do: "information"

  defp status_label(%Identity{enabled: true}), do: gettext("Enabled")
  defp status_label(%Identity{}), do: gettext("Disabled")

  defp status_color(%Identity{enabled: true}), do: "success"
  defp status_color(%Identity{}), do: "neutral"

  defp slack_binding_label(%Identity{} = identity) do
    binding = AgentIdentities.slack_binding(identity)
    app = Map.get(binding, "app") || "company"
    channel_ids = Map.get(binding, "channel_ids") || []

    cond do
      match_all_channels?(binding) ->
        gettext("%{app} Slack, all channels", app: app)

      channel_ids != [] ->
        gettext("%{app} Slack, %{channels}", app: app, channels: Enum.join(channel_ids, ", "))

      true ->
        gettext("%{app} Slack", app: app)
    end
  end

  defp match_all_channels?(binding), do: Map.get(binding, "match_all_channels") in [true, "true"]

  defp tool_groups_label(%Identity{} = identity) do
    groups =
      identity
      |> Identity.all_tool_groups()
      |> Enum.map_join(", ", &tool_group_label/1)

    if groups == "", do: gettext("No tools"), else: groups
  end

  defp tool_group_label("finance"), do: gettext("Finance")
  defp tool_group_label("documents"), do: gettext("Documents")
  defp tool_group_label("observability"), do: gettext("Production systems")
  defp tool_group_label(group), do: group

  defp tool_access_options do
    [
      %{
        value: "finance",
        label: gettext("Finance"),
        description: gettext("Revenue, invoices, cash, and transactions.")
      },
      %{
        value: "documents",
        label: gettext("Documents"),
        description: gettext("Contracts, board materials, invoices, and uploaded files.")
      },
      %{
        value: "observability",
        label: gettext("Production systems"),
        description: gettext("Production incidents, errors, and infrastructure signals.")
      }
    ]
  end
end
