defmodule AtlasWeb.Admin.InferenceLive do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.Admin.InferenceHelpers,
    only: [
      atlas_role_badges: 1,
      model_identifier_placeholder: 1,
      provider_select_options: 0
    ]

  import AtlasWeb.CoreComponents, only: []
  import Noora.Filter

  alias Atlas.Audit
  alias Atlas.Inference
  alias Atlas.Inference.ModelBinding
  alias Atlas.Inference.Token
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(
         :error,
         gettext("Log in to manage inference profiles.")
       )
       |> redirect(to: ~p"/login")}
    else
      {:ok,
       socket
       |> assign(:page_title, gettext("Inference profiles · Atlas"))
       |> assign(:available_filters, [])
       |> assign(:active_filters, [])
       |> assign(:profiles_meta, %{
         current_page: 1,
         page_size: @page_size,
         total_entries: 0,
         total_pages: 1
       })
       |> assign(:profiles, [])
       |> assign(:query, "")
       |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
       |> assign(:uri, URI.parse("/admin/inference/profiles"))
       |> assign_profile_form(Inference.change_profile(%ModelBinding{}, %{}))
       |> assign_provider_options()}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    available_filters = define_filters()
    query_params = Query.query_params(uri)

    page = Query.parse_page(params["page"])
    query = params["q"] || ""
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {profiles, meta} =
      Inference.list_profiles(profile_list_opts(query, active_filters, page))

    socket =
      socket
      |> assign(:uri, uri_from_query_params(query_params))
      |> assign(:profiles_meta, meta)
      |> assign(:profiles, profiles)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:query, query)
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_profile", %{"profile" => params}, socket) do
    changeset =
      %ModelBinding{}
      |> Inference.change_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_profile_form(socket, changeset)}
  end

  def handle_event("profile_provider_changed", params, socket) do
    params =
      socket.assigns.profile_form
      |> form_params()
      |> Map.put("upstream_provider", selected_value(params))

    {:noreply, assign_profile_form(socket, Inference.change_profile(%ModelBinding{}, params))}
  end

  def handle_event("create_profile", %{"profile" => params}, socket) do
    case Inference.create_profile(params) do
      {:ok, profile} ->
        record_profile_audit(:"inference_profile.created", profile)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Profile created."))
         |> assign_profile_form(Inference.change_profile(%ModelBinding{}, %{}))
         |> assign_profiles()
         |> push_event("close-modal", %{id: "new-inference-profile-modal"})}

      {:error, changeset} ->
        {:noreply, assign_profile_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("open_new_profile", _params, socket) do
    {:noreply,
     socket
     |> assign_profile_form(Inference.change_profile(%ModelBinding{}, %{}))
     |> push_event("open-modal", %{id: "new-inference-profile-modal"})}
  end

  def handle_event("close_new_profile", _params, socket) do
    {:noreply,
     socket
     |> assign_profile_form(Inference.change_profile(%ModelBinding{}, %{}))
     |> push_event("close-modal", %{id: "new-inference-profile-modal"})}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/inference/profiles?#{profile_query_params(query, socket.assigns.active_filters)}",
       replace: true
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/admin/inference/profiles?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.update_filters_in_query(params, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/admin/inference/profiles?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="admin-inference">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>{gettext("Profiles")}</h1>
          <p>
            {gettext(
              "Create stable model profiles for repositories and Atlas itself. Each profile points at one upstream provider and model, and tokens created under it can only use that profile."
            )}
          </p>
        </div>
      </div>

      <.card title={gettext("Profiles")} icon="lock" data-part="profiles-card">
        <:actions>
          <.new_profile_modal
            profile_form={@profile_form}
            provider_options={@provider_options}
          />
        </:actions>
        <.card_section>
          <p data-part="card-intro">
            {gettext(
              "Stable model names that repositories and Atlas's own workflows can request through the gateway."
            )}
          </p>

          <div data-part="table-toolbar">
            <.filter_dropdown
              id="inference-profiles-filter"
              label={gettext("Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
              on_select="add_filter"
            />

            <div data-part="search">
              <.form
                id="inference-profiles-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="inference-profiles-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search profiles...")}
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <.table
            id="inference-profiles-table"
            rows={@profiles}
            row_key={fn profile -> "inference-profile-#{profile.id}" end}
            row_navigate={fn profile -> ~p"/admin/inference/profiles/#{profile.id}" end}
          >
            <:col :let={profile} label={gettext("Profile")}>
              <.text_and_description_cell
                icon="lock"
                label={profile.name}
                description={profile.description || gettext("No description")}
              />
            </:col>
            <:col :let={profile} label={gettext("Status")}>
              <% status = profile_status(profile) %>
              <.badge_cell label={status.label} color={status.color} style="light-fill" />
            </:col>
            <:col :let={profile} label={gettext("Atlas use")}>
              <div data-part="role-cell">
                <.badge
                  :for={role <- atlas_role_badges(profile)}
                  label={role.label}
                  color={role.color}
                  style="light-fill"
                />
                <span :if={atlas_role_badges(profile) == []}>
                  {gettext("Not used")}
                </span>
              </div>
            </:col>
            <:col :let={profile} label={gettext("Upstream")}>
              <div data-part="route-cell">
                <span>{profile.upstream_provider}</span>
                <code>{profile.upstream_model}</code>
              </div>
            </:col>
            <:col :let={profile} label={gettext("Tokens")}>
              <div data-part="token-count-cell">
                <span>{token_count_label(profile)}</span>
                <small>{active_token_count_label(profile)}</small>
              </div>
            </:col>
            <:col :let={profile} label={gettext("Last used")}>
              <.text_cell label={last_used_label(profile.last_used_at)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="lock"
                title={gettext("No inference profiles")}
                subtitle={
                  gettext("Create a profile to expose a stable model name to repository automation.")
                }
              />
            </:empty_state>
          </.table>

          <div :if={@profiles_meta.total_pages > 1} data-part="pagination">
            <.button
              variant="secondary"
              label={gettext("Prev")}
              disabled={@profiles_meta.current_page <= 1}
              patch={page_link(@uri, max(1, @profiles_meta.current_page - 1))}
            >
              <:icon_left><.chevron_left /></:icon_left>
            </.button>
            <.button
              variant="secondary"
              label={gettext("Next")}
              disabled={@profiles_meta.current_page >= @profiles_meta.total_pages}
              patch={
                page_link(
                  @uri,
                  min(@profiles_meta.total_pages, @profiles_meta.current_page + 1)
                )
              }
            >
              <:icon_right><.chevron_right /></:icon_right>
            </.button>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :profile_form, :map, required: true
  attr :provider_options, :list, required: true

  defp new_profile_modal(assigns) do
    ~H"""
    <.modal
      id="new-inference-profile-modal"
      title={gettext("Create profile")}
      description={
        gettext(
          "Expose a stable model name that Atlas can retarget later without changing repositories."
        )
      }
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_profile"
    >
      <:trigger :let={attrs}>
        <.button
          label={gettext("Create profile")}
          size="medium"
          variant="primary"
          phx-click="open_new_profile"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="lock" />
      </:header_icon>

      <.form
        id="new-inference-profile-form"
        for={@profile_form}
        phx-change="validate_profile"
        phx-submit="create_profile"
        data-part="form"
      >
        <.text_input
          id="new-inference-profile-name"
          field={@profile_form[:name]}
          label={gettext("Profile name")}
          placeholder="blick-code-review"
        />
        <.text_area
          id="new-inference-profile-description"
          field={@profile_form[:description]}
          label={gettext("Description")}
          placeholder={gettext("Repository code review profile")}
        />
        <div data-part="select-field">
          <span>{gettext("Upstream provider")}</span>
          <.select
            id="new-inference-profile-provider"
            name={@profile_form[:upstream_provider].name}
            on_value_change="profile_provider_changed"
            value={
              Phoenix.HTML.Form.normalize_value(
                "select",
                @profile_form[:upstream_provider].value
              )
            }
            label={
              if @provider_options == [],
                do: gettext("No providers available"),
                else: gettext("Choose provider")
            }
            disabled={@provider_options == []}
          >
            <:item :for={provider <- @provider_options} value={provider.value} label={provider.label} />
          </.select>
        </div>
        <.text_input
          id="new-inference-profile-model"
          field={@profile_form[:upstream_model]}
          label={gettext("Upstream model")}
          placeholder={model_identifier_placeholder(@profile_form[:upstream_provider].value)}
        />
        <.text_input
          id="new-inference-profile-input-cost"
          field={@profile_form[:input_cost_per_million]}
          label={gettext("Input cost per million tokens")}
          input_type="number"
          min="0"
          step="0.000001"
          placeholder="0.15"
        />
        <.text_input
          id="new-inference-profile-output-cost"
          field={@profile_form[:output_cost_per_million]}
          label={gettext("Output cost per million tokens")}
          input_type="number"
          min="0"
          step="0.000001"
          placeholder="0.60"
        />
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_new_profile"
            />
          </:action>
          <:action>
            <.button
              label={gettext("Create")}
              size="medium"
              variant="primary"
              type="submit"
              form="new-inference-profile-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp assign_profiles(socket) do
    {profiles, meta} =
      Inference.list_profiles(profile_list_opts(socket.assigns.query, socket.assigns.active_filters, 1))

    socket
    |> assign(:profiles_meta, meta)
    |> assign(:profiles, profiles)
  end

  defp assign_provider_options(socket) do
    assign(socket, :provider_options, provider_select_options())
  end

  defp assign_profile_form(socket, changeset) do
    assign(socket, :profile_form, to_form(changeset, as: :profile))
  end

  defp form_params(form) do
    form
    |> Map.get(:params, %{})
    |> case do
      params when is_map(params) -> params
      _params -> %{}
    end
  end

  defp selected_value(%{"value" => [value | _rest]}), do: value
  defp selected_value(%{"value" => value}) when is_binary(value), do: value
  defp selected_value(_params), do: nil

  defp token_count(%ModelBinding{tokens: tokens}) when is_list(tokens), do: length(tokens)
  defp token_count(_profile), do: 0

  defp token_count_label(profile) do
    count = token_count(profile)

    if count == 1 do
      gettext("1 token")
    else
      gettext("%{count} tokens", count: count)
    end
  end

  defp active_token_count_label(%ModelBinding{tokens: tokens}) when is_list(tokens) do
    count = Enum.count(tokens, &active_token?/1)
    gettext("%{count} active", count: count)
  end

  defp active_token_count_label(_profile), do: gettext("0 active")

  defp profile_status(%ModelBinding{enabled: true}), do: %{label: gettext("Enabled"), color: "success"}

  defp profile_status(%ModelBinding{}), do: %{label: gettext("Disabled"), color: "neutral"}

  defp active_token?(%Token{enabled: false}), do: false

  defp active_token?(%Token{expires_at: %DateTime{} = expires_at}) do
    DateTime.after?(expires_at, DateTime.utc_now())
  end

  defp active_token?(%Token{}), do: true

  defp last_used_label(nil), do: gettext("Never used")
  defp last_used_label(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp page_link(uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end

  defp profile_query_params(query, active_filters) do
    active_filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
  end

  defp profile_list_opts(query, active_filters, page) do
    [page: page, page_size: @page_size, query: Query.present_string(query)]
    |> put_status_filter(active_filters)
  end

  defp put_status_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "status")) do
      %{operator: :==, value: "enabled"} -> Keyword.put(opts, :enabled, true)
      %{operator: :==, value: "disabled"} -> Keyword.put(opts, :enabled, false)
      _filter -> opts
    end
  end

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp uri_from_query_params(params) do
    case URI.encode_query(params) do
      "" -> URI.parse("")
      query -> URI.parse("?" <> query)
    end
  end

  defp define_filters do
    options = ["enabled", "disabled"]

    [
      %Filter.Filter{
        id: "status",
        display_name: gettext("Status"),
        type: :option,
        options: options,
        options_display_names: Map.new(options, &{&1, status_filter_label(&1)}),
        operator: :==,
        searchable: false,
        value: nil
      }
    ]
  end

  defp status_filter_label("enabled"), do: gettext("Enabled")
  defp status_filter_label("disabled"), do: gettext("Disabled")
  defp status_filter_label(status), do: status

  defp record_profile_audit(action, %ModelBinding{} = profile) do
    Audit.record(action, %{
      target_type: "inference_profile",
      target_id: profile.id,
      target_label: profile.name,
      metadata: %{
        "upstream_provider" => profile.upstream_provider,
        "upstream_model" => profile.upstream_model,
        "input_cost_per_million" => profile.input_cost_per_million,
        "output_cost_per_million" => profile.output_cost_per_million,
        "path" => "/admin/inference/profiles/#{profile.id}"
      }
    })
  end
end
