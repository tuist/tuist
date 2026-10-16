defmodule AtlasWeb.GTMEmailLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.EmailHeader
  import AtlasWeb.Widget
  import Noora.Filter

  alias Atlas.GTM
  alias Atlas.GTM.Audience
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Subscriber
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter
  alias Phoenix.HTML.Form

  @audiences_page_size 25
  @subscribers_page_size 25
  @audiences_page_param "audiences-page"
  @subscribers_page_param "subscribers-page"
  # Audiences and subscribers share one query string, so every filter id is
  # prefixed with its section. Without it both sections would fight over
  # `filter_source_*`.
  @audiences_source_filter "audiences_source"
  @audiences_subscribers_filter "audiences_subscribers"
  @audiences_broadcasts_filter "audiences_broadcasts"
  @subscribers_status_filter "subscribers_status"
  @subscribers_source_filter "subscribers_source"
  @memberships_status_filter "members_status"
  @memberships_page_param "members-page"
  @broadcasts_page_param "broadcasts-page"
  @memberships_page_size 25
  @broadcasts_page_size 10
  @page_params [@audiences_page_param, @subscribers_page_param, @memberships_page_param, @broadcasts_page_param]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Email"))
     |> assign(:uri, %URI{query: nil})
     |> assign(:available_filters, [])
     |> assign(:audiences_empty?, true)
     |> assign(:subscribers_empty?, true)
     |> assign(:memberships_empty?, true)
     |> assign(:broadcasts_empty?, true)}
  end

  def handle_params(params, uri, socket) do
    case socket.assigns.live_action do
      :index -> {:noreply, assign_index(socket, params, uri)}
      :audience -> {:noreply, assign_audience(socket, params, uri)}
    end
  end

  def handle_event("search_audiences", %{"search" => %{"query" => query}}, socket) do
    query_params =
      socket
      |> current_query_params()
      |> reset_page(@audiences_page_param)
      |> put_search_query("audiences-query", query)

    {:noreply, push_patch(socket, to: ~p"/outbound/email?#{query_params}", replace: true)}
  end

  def handle_event("search_subscribers", %{"search" => %{"query" => query}}, socket) do
    query_params =
      socket
      |> current_query_params()
      |> reset_page(@subscribers_page_param)
      |> put_search_query("subscribers-query", query)

    {:noreply, push_patch(socket, to: ~p"/outbound/email?#{query_params}", replace: true)}
  end

  def handle_event("search_members", %{"search" => %{"query" => query}}, socket) do
    query_params =
      socket
      |> current_query_params()
      |> reset_page(@memberships_page_param)
      |> put_search_query("members-query", query)

    {:noreply, push_patch(socket, to: audience_path(socket, query_params), replace: true)}
  end

  def handle_event("add-audience-member-modal-open-changed", %{"open" => true}, socket) do
    if socket.assigns.subscriber_options_loaded? do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:subscriber_options, GTM.list_all_email_subscribers())
       |> assign(:subscriber_options_loaded?, true)}
    end
  end

  def handle_event("add-audience-member-modal-open-changed", _params, socket), do: {:noreply, socket}

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.drop(@page_params)
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: filtered_path(socket, updated_params))
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.drop(@page_params)
      |> then(&Filter.Operations.update_filters_in_query(params, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: filtered_path(socket, updated_params))
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event("validate_subscriber", %{"subscriber" => params}, socket) do
    form =
      %Subscriber{}
      |> GTM.change_email_subscriber(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "subscriber")

    {:noreply, assign(socket, :subscriber_form, form)}
  end

  def handle_event("create_subscriber", %{"subscriber" => params}, socket) do
    case GTM.create_email_subscriber(params, socket.assigns.current_user) do
      {:ok, _subscriber} ->
        {:noreply,
         socket
         |> push_event("close-modal", %{id: "new-email-subscriber-modal"})
         |> push_patch(to: ~p"/outbound/email?#{reset_subscribers_page(socket)}", replace: true)
         |> put_flash(:info, gettext("Subscriber created."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :subscriber_form, to_form(changeset, as: "subscriber"))}
    end
  end

  def handle_event("validate_audience", %{"audience" => params}, socket) do
    form =
      %Audience{}
      |> GTM.change_email_audience(params)
      |> Map.put(:action, :validate)
      |> to_form(as: "audience")

    {:noreply, assign(socket, :audience_form, form)}
  end

  def handle_event("create_audience", %{"audience" => params}, socket) do
    case GTM.create_email_audience(params, socket.assigns.current_user) do
      {:ok, audience} ->
        {:noreply,
         socket
         |> push_event("close-modal", %{id: "new-email-audience-modal"})
         |> push_navigate(to: ~p"/outbound/email/audiences/#{audience.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :audience_form, to_form(changeset, as: "audience"))}
    end
  end

  def handle_event("delete_audience", %{"id" => id}, socket) do
    case GTM.get_email_audience(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Audience not found."))}

      audience ->
        case GTM.delete_email_audience(audience, socket.assigns.current_user) do
          {:ok, _deleted} ->
            {:noreply,
             socket
             |> push_patch(to: ~p"/outbound/email?#{reset_audiences_page(socket)}", replace: true)
             |> put_flash(:info, gettext("Audience deleted."))}

          {:error, :has_broadcasts} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Audiences with broadcast history cannot be deleted.")
             )}

          {:error, :dynamic_audience} ->
            {:noreply, put_flash(socket, :error, gettext("Dynamic audiences cannot be deleted."))}
        end
    end
  end

  def handle_event("add_subscriber", %{"membership" => %{"subscriber_id" => subscriber_id}}, socket) do
    case GTM.get_email_subscriber(subscriber_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Subscriber not found."))}

      subscriber ->
        case GTM.add_email_audience_subscriber(
               socket.assigns.audience,
               subscriber,
               socket.assigns.current_user
             ) do
          {:ok, _membership} ->
            {:noreply,
             socket
             |> refresh_audience()
             |> put_flash(:info, gettext("Subscriber added to the audience."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not add the subscriber."))}
        end
    end
  end

  def handle_event("unsubscribe_subscriber", %{"subscriber_id" => subscriber_id}, socket) do
    case GTM.get_email_subscriber(subscriber_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Subscriber not found."))}

      subscriber ->
        case GTM.unsubscribe_email_audience_subscriber(
               socket.assigns.audience,
               subscriber,
               socket.assigns.current_user
             ) do
          {:ok, _membership} ->
            {:noreply,
             socket
             |> refresh_audience()
             |> put_flash(:info, gettext("Subscriber unsubscribed from this audience."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not unsubscribe the subscriber."))}
        end
    end
  end

  def handle_event("validate_broadcast", %{"broadcast" => params}, socket) do
    form =
      socket.assigns.audience
      |> GTM.change_email_broadcast(params, socket.assigns.current_user)
      |> Map.put(:action, :validate)
      |> to_form(as: "broadcast")

    {:noreply, assign(socket, :broadcast_form, form)}
  end

  def handle_event("queue_broadcast", %{"broadcast" => params}, socket) do
    case GTM.queue_email_broadcast(socket.assigns.audience, params, socket.assigns.current_user) do
      {:ok, broadcast} ->
        {:noreply,
         socket
         |> refresh_audience()
         |> assign_broadcast_form()
         |> push_event("close-modal", %{id: "new-email-broadcast-modal"})
         |> put_flash(
           :info,
           gettext("Broadcast queued for %{count} recipients.", count: broadcast.recipients_count)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :broadcast_form, to_form(changeset, as: "broadcast"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not queue the broadcast."))}
    end
  end

  def handle_event("close-modal", %{"id" => id}, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: id})}
  end

  def handle_event("close-new-email-subscriber-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "new-email-subscriber-modal"})}
  end

  def handle_event("close-add-audience-member-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "add-audience-member-modal"})}
  end

  def handle_event("close-new-email-audience-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "new-email-audience-modal"})}
  end

  def handle_event("close-new-email-broadcast-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "new-email-broadcast-modal"})}
  end

  def render(assigns) do
    ~H"""
    <div id="email" data-part="email-page">
      <%= case @live_action do %>
        <% :index -> %>
          <.index_view
            audiences={@audiences}
            audiences_meta={@audiences_meta}
            audiences_empty?={@audiences_empty?}
            audiences_query={@audiences_query}
            audiences_active_filters={@audiences_active_filters}
            audiences_available_filters={@audiences_available_filters}
            audiences_search_form={@audiences_search_form}
            subscribers={@subscribers}
            subscribers_meta={@subscribers_meta}
            subscribers_empty?={@subscribers_empty?}
            subscribers_query={@subscribers_query}
            subscribers_active_filters={@subscribers_active_filters}
            subscribers_available_filters={@subscribers_available_filters}
            subscribers_search_form={@subscribers_search_form}
            uri={@uri}
            audience_form={@audience_form}
            subscriber_form={@subscriber_form}
          />
        <% :audience -> %>
          <.audience_view
            audience={@audience}
            memberships={@memberships}
            memberships_meta={@memberships_meta}
            memberships_query={@memberships_query}
            memberships_active_filters={@memberships_active_filters}
            memberships_available_filters={@memberships_available_filters}
            memberships_search_form={@memberships_search_form}
            broadcasts={@broadcasts}
            broadcasts_meta={@broadcasts_meta}
            subscriber_options={@subscriber_options}
            membership_form={@membership_form}
            broadcast_form={@broadcast_form}
            uri={@uri}
          />
      <% end %>
    </div>
    """
  end

  attr :audiences, :any, required: true
  attr :audiences_meta, :map, required: true
  attr :audiences_empty?, :boolean, required: true
  attr :audiences_query, :string, required: true
  attr :audiences_active_filters, :list, required: true
  attr :audiences_available_filters, :list, required: true
  attr :audiences_search_form, Form, required: true
  attr :subscribers, :any, required: true
  attr :subscribers_meta, :map, required: true
  attr :subscribers_empty?, :boolean, required: true
  attr :subscribers_query, :string, required: true
  attr :subscribers_active_filters, :list, required: true
  attr :subscribers_available_filters, :list, required: true
  attr :subscribers_search_form, Form, required: true
  attr :uri, URI, required: true
  attr :audience_form, Form, required: true
  attr :subscriber_form, Form, required: true

  defp index_view(assigns) do
    ~H"""
    <.email_header selected={:audiences} />

    <.card title={gettext("Audiences")} icon="users" data-part="email-audiences-card">
      <:actions>
        <.new_audience_modal form={@audience_form} />
      </:actions>
      <.card_section>
        <div data-part="filters">
          <div data-part="search">
            <.form
              id="email-audiences-search-form"
              for={@audiences_search_form}
              phx-change="search_audiences"
              phx-submit="search_audiences"
            >
              <.text_input
                id="email-audiences-search"
                field={@audiences_search_form[:query]}
                type="search"
                show_suffix={false}
                placeholder={gettext("Search by name or slug")}
              />
            </.form>
          </div>

          <.filter_dropdown
            id="email-audiences-filters-dropdown"
            available_filters={@audiences_available_filters}
            active_filters={@audiences_active_filters}
            on_select="add_filter"
          />
        </div>

        <div :if={@audiences_active_filters != []} data-part="active-filters">
          <.active_filter :for={filter <- @audiences_active_filters} filter={filter} />
        </div>

        <.table
          id="email-audiences-table"
          rows={@audiences}
          row_key={fn audience -> audience.id end}
          row_navigate={fn audience -> ~p"/outbound/email/audiences/#{audience.id}" end}
        >
          <:col :let={audience} label={gettext("Audience")}>
            <.text_and_description_cell
              label={audience.name}
              description={audience.description || audience.slug}
            />
          </:col>
          <:col :let={audience} label={gettext("Membership")}>
            <.badge_cell
              label={audience_membership_type_label(audience)}
              color={audience_membership_type_color(audience)}
              style="light-fill"
            />
          </:col>
          <:col :let={audience} label={gettext("Subscribers")}>
            <.text_cell label={audience.subscribers_count} />
          </:col>
          <:col :let={audience} label={gettext("Broadcasts")}>
            <.text_cell label={audience.broadcasts_count} />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="users"
              title={gettext("No matching audiences")}
              subtitle={gettext("Adjust the search or filters, or create a new audience.")}
            />
          </:empty_state>
        </.table>

        <.pagination_group
          :if={@audiences_meta.total_pages > 1}
          id="email-audiences-pagination"
          current_page={@audiences_meta.current_page}
          number_of_pages={@audiences_meta.total_pages}
          page_patch={fn page -> "?#{Query.put(@uri.query, "audiences-page", page)}" end}
        />
      </.card_section>
    </.card>

    <.card title={gettext("Subscribers")} icon="mail" data-part="email-subscribers-card">
      <:actions>
        <.new_subscriber_modal form={@subscriber_form} />
      </:actions>
      <.card_section>
        <div data-part="filters">
          <div data-part="search">
            <.form
              id="email-subscribers-search-form"
              for={@subscribers_search_form}
              phx-change="search_subscribers"
              phx-submit="search_subscribers"
            >
              <.text_input
                id="email-subscribers-search"
                field={@subscribers_search_form[:query]}
                type="search"
                show_suffix={false}
                placeholder={gettext("Search by email or name")}
              />
            </.form>
          </div>

          <.filter_dropdown
            id="email-subscribers-filters-dropdown"
            available_filters={@subscribers_available_filters}
            active_filters={@subscribers_active_filters}
            on_select="add_filter"
          />
        </div>

        <div :if={@subscribers_active_filters != []} data-part="active-filters">
          <.active_filter :for={filter <- @subscribers_active_filters} filter={filter} />
        </div>

        <.table
          id="email-subscribers-table"
          rows={@subscribers}
          row_key={fn subscriber -> subscriber.id end}
        >
          <:col :let={subscriber} label={gettext("Subscriber")}>
            <.text_and_description_cell
              label={Subscriber.display_name(subscriber)}
              description={subscriber.email}
            />
          </:col>
          <:col :let={subscriber} label={gettext("Source")}>
            <.text_cell label={subscriber.source} />
          </:col>
          <:col :let={subscriber} label={gettext("User group")}>
            <.text_cell label={subscriber.user_group || gettext("Not set")} />
          </:col>
          <:col :let={subscriber} label={gettext("Status")}>
            <.badge_cell
              label={subscriber_status_label(subscriber.status)}
              color={subscriber_status_color(subscriber.status)}
              style="light-fill"
            />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="mail"
              title={gettext("No matching subscribers")}
              subtitle={gettext("Adjust the search or filters, or create a new subscriber.")}
            />
          </:empty_state>
        </.table>

        <.pagination_group
          :if={@subscribers_meta.total_pages > 1}
          id="email-subscribers-pagination"
          current_page={@subscribers_meta.current_page}
          number_of_pages={@subscribers_meta.total_pages}
          page_patch={fn page -> "?#{Query.put(@uri.query, "subscribers-page", page)}" end}
        />
      </.card_section>
    </.card>
    """
  end

  attr :audience, Audience, required: true
  attr :memberships, :list, required: true
  attr :memberships_meta, :map, required: true
  attr :memberships_query, :string, required: true
  attr :memberships_active_filters, :list, required: true
  attr :memberships_available_filters, :list, required: true
  attr :memberships_search_form, Form, required: true
  attr :broadcasts, :list, required: true
  attr :broadcasts_meta, :map, required: true
  attr :subscriber_options, :list, required: true
  attr :membership_form, Form, required: true
  attr :broadcast_form, Form, required: true
  attr :uri, URI, required: true

  defp audience_view(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{@audience.name}</h1>
        <p data-part="description">{@audience.description || gettext("Email audience")}</p>
        <p :if={Audience.dynamic?(@audience)} data-part="description">
          {dynamic_audience_rule_summary(@audience)}
        </p>
      </div>
      <div data-part="header-actions">
        <.button
          id="email-audience-back-button"
          label={gettext("Back to email")}
          variant="secondary"
          size="medium"
          navigate={~p"/outbound/email"}
        >
          <:icon_left><.arrow_left /></:icon_left>
        </.button>
      </div>
    </div>

    <div data-part="widgets">
      <.widget
        id="email-audience-widget-subscribed"
        title={
          if(Audience.dynamic?(@audience),
            do: gettext("Matching contacts"),
            else: gettext("Subscribed")
          )
        }
        value={to_string(@audience.subscribers_count)}
        description={
          if(Audience.dynamic?(@audience),
            do: gettext("Contacts that currently match this audience's account rules."),
            else: gettext("People a broadcast would reach today.")
          )
        }
        legend_color="success"
      />
      <.widget
        id="email-audience-widget-members"
        title={
          if(Audience.dynamic?(@audience), do: gettext("Audience type"), else: gettext("Members"))
        }
        value={
          if(Audience.dynamic?(@audience),
            do: gettext("Dynamic"),
            else: to_string(@memberships_meta.total_count)
          )
        }
        description={
          if(Audience.dynamic?(@audience),
            do: gettext("Re-evaluated whenever you open or send to this audience."),
            else: gettext("Everyone ever added, including those who left.")
          )
        }
        legend_color="primary"
      />
      <.widget
        id="email-audience-widget-broadcasts"
        title={gettext("Broadcasts")}
        value={to_string(@audience.broadcasts_count)}
        description={gettext("Group emails queued to this audience.")}
        legend_color="neutral"
      />
    </div>

    <.card
      title={
        if(Audience.dynamic?(@audience), do: gettext("Matching contacts"), else: gettext("Members"))
      }
      icon="users"
      data-part="email-members-card"
    >
      <:actions :if={not Audience.dynamic?(@audience)}>
        <.add_member_modal form={@membership_form} subscriber_options={@subscriber_options} />
      </:actions>
      <.card_section>
        <div :if={not Audience.dynamic?(@audience)} data-part="filters">
          <div data-part="search">
            <.form
              id="email-members-search-form"
              for={@memberships_search_form}
              phx-change="search_members"
              phx-submit="search_members"
            >
              <.text_input
                id="email-members-search"
                field={@memberships_search_form[:query]}
                type="search"
                show_suffix={false}
                placeholder={gettext("Search by email or name")}
              />
            </.form>
          </div>

          <.filter_dropdown
            id="email-members-filters-dropdown"
            available_filters={@memberships_available_filters}
            active_filters={@memberships_active_filters}
            on_select="add_filter"
          />
        </div>

        <div :if={@memberships_active_filters != []} data-part="active-filters">
          <.active_filter :for={filter <- @memberships_active_filters} filter={filter} />
        </div>

        <%= if Audience.dynamic?(@audience) do %>
          <.table id="email-audience-members-table" rows={@memberships} row_key={& &1.id}>
            <:col :let={membership} label={gettext("Contact")}>
              <.text_and_description_cell
                label={Subscriber.display_name(membership.subscriber)}
                description={membership.subscriber.email}
              />
            </:col>
            <:col :let={membership} label={gettext("Account")}>
              <.text_cell label={membership.subscriber.user_group} />
            </:col>
            <:col :let={membership} label={gettext("Source")}>
              <.text_cell label={membership.subscriber.source} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="users"
                title={gettext("No matching contacts")}
                subtitle={
                  gettext("Update the account lifecycle, deployment, or contacts to include someone.")
                }
              />
            </:empty_state>
          </.table>
        <% else %>
          <.table id="email-audience-members-table" rows={@memberships} row_key={& &1.id}>
            <:col :let={membership} label={gettext("Subscriber")}>
              <.text_and_description_cell
                label={Subscriber.display_name(membership.subscriber)}
                description={membership.subscriber.email}
              />
            </:col>
            <:col :let={membership} label={gettext("Source")}>
              <.text_cell label={membership.subscriber.source} />
            </:col>
            <:col :let={membership} label={gettext("Status")}>
              <.badge_cell
                label={subscriber_status_label(membership.status)}
                color={subscriber_status_color(membership.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={membership} label="">
              <div data-part="row-actions">
                <.button
                  :if={membership.status == "subscribed"}
                  id={"unsubscribe-audience-subscriber-#{membership.subscriber.id}"}
                  label={gettext("Unsubscribe")}
                  size="small"
                  variant="secondary"
                  phx-click="unsubscribe_subscriber"
                  phx-value-subscriber_id={membership.subscriber.id}
                  data-confirm={
                    gettext("Unsubscribe this person from %{audience}?", audience: @audience.name)
                  }
                />
              </div>
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="users"
                title={gettext("No members yet")}
                subtitle={gettext("Add a subscribed person before sending a broadcast.")}
              />
            </:empty_state>
          </.table>
        <% end %>

        <.pagination_group
          :if={@memberships_meta.total_pages > 1}
          id="email-members-pagination"
          current_page={@memberships_meta.current_page}
          number_of_pages={@memberships_meta.total_pages}
          page_patch={fn page -> "?#{Query.put(@uri.query, "members-page", page)}" end}
        />
      </.card_section>
    </.card>

    <.card title={gettext("Broadcast history")} icon="mail" data-part="email-broadcasts-card">
      <:actions>
        <.broadcast_modal form={@broadcast_form} audience={@audience} />
      </:actions>
      <.card_section>
        <.table id="email-broadcasts-table" rows={@broadcasts} row_key={& &1.id}>
          <:col :let={broadcast} label={gettext("Broadcast")}>
            <.text_and_description_cell
              label={broadcast.subject}
              description={format_datetime(broadcast.inserted_at)}
            />
          </:col>
          <:col :let={broadcast} label={gettext("Recipients")}>
            <.text_cell label={broadcast.recipients_count} />
          </:col>
          <:col :let={broadcast} label={gettext("Delivered")}>
            <.text_cell label={broadcast.delivered_count} />
          </:col>
          <:col :let={broadcast} label={gettext("Status")}>
            <.badge_cell
              label={broadcast_status_label(broadcast.status)}
              color={broadcast_status_color(broadcast.status)}
              style="light-fill"
            />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="mail"
              title={gettext("No broadcasts yet")}
              subtitle={gettext("Every queued group email will appear here with delivery counts.")}
            />
          </:empty_state>
        </.table>

        <.pagination_group
          :if={@broadcasts_meta.total_pages > 1}
          id="email-broadcasts-pagination"
          current_page={@broadcasts_meta.current_page}
          number_of_pages={@broadcasts_meta.total_pages}
          page_patch={fn page -> "?#{Query.put(@uri.query, "broadcasts-page", page)}" end}
        />
      </.card_section>
    </.card>

    <.card
      :if={not Audience.dynamic?(@audience) and @broadcasts_meta.total_count == 0}
      id="email-delete-audience-card"
      title={gettext("Delete audience")}
      icon="trash"
      data-part="email-delete-audience-card"
    >
      <.card_section>
        <div data-part="delete-audience-action">
          <div data-part="delete-audience-copy">
            <p data-part="delete-audience-title">{gettext("Delete this audience")}</p>
            <p data-part="delete-audience-description">
              {gettext("Its manual memberships will also be removed. This cannot be undone.")}
            </p>
          </div>
          <.button
            id={"delete-email-audience-#{@audience.id}"}
            label={gettext("Delete audience")}
            variant="destructive"
            size="medium"
            phx-click="delete_audience"
            phx-value-id={@audience.id}
            data-confirm={gettext("Delete %{audience}?", audience: @audience.name)}
          />
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :form, Form, required: true
  attr :subscriber_options, :list, required: true

  defp add_member_modal(assigns) do
    ~H"""
    <.modal
      id="add-audience-member-modal"
      title={gettext("Add member")}
      description={gettext("Pick an existing subscriber to add to this audience.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close-add-audience-member-modal"
      on_open_change="add-audience-member-modal-open-changed"
    >
      <:header_icon><.user /></:header_icon>
      <:trigger :let={modal_attrs}>
        <.button label={gettext("Add member")} size="medium" {modal_attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <.form id="add-audience-subscriber-form" for={@form} phx-submit="add_subscriber">
        <div data-part="email-form-grid">
          <.select
            id="audience-subscriber-select"
            field={@form[:subscriber_id]}
            label={gettext("Subscriber")}
          >
            <:item
              :for={subscriber <- @subscriber_options}
              value={subscriber.id}
              label={subscriber.email}
            />
          </.select>
        </div>
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              phx-click="close-modal"
              phx-value-id="add-audience-member-modal"
            />
          </:action>
          <:action>
            <.button
              id="add-audience-subscriber"
              label={gettext("Add member")}
              form="add-audience-subscriber-form"
              type="submit"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :form, Form, required: true

  defp new_subscriber_modal(assigns) do
    ~H"""
    <.modal
      id="new-email-subscriber-modal"
      title={gettext("New subscriber")}
      description={gettext("Create a person who can be added to one or more audiences.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close-new-email-subscriber-modal"
    >
      <:header_icon><.user /></:header_icon>
      <:trigger :let={modal_attrs}>
        <.button label={gettext("New subscriber")} size="medium" variant="secondary" {modal_attrs}>
          <:icon_left><.user /></:icon_left>
        </.button>
      </:trigger>
      <.form
        id="new-email-subscriber-form"
        for={@form}
        phx-change="validate_subscriber"
        phx-submit="create_subscriber"
      >
        <div data-part="email-form-grid">
          <.text_input
            id="subscriber-email"
            field={@form[:email]}
            type="basic"
            label={gettext("Email")}
            required
            show_required
            show_suffix={false}
          />
          <.text_input
            id="subscriber-first-name"
            field={@form[:first_name]}
            type="basic"
            label={gettext("First name")}
            show_suffix={false}
          />
          <.text_input
            id="subscriber-last-name"
            field={@form[:last_name]}
            type="basic"
            label={gettext("Last name")}
            show_suffix={false}
          />
          <.text_input
            id="subscriber-source"
            field={@form[:source]}
            type="basic"
            label={gettext("Source")}
            required
            show_required
            show_suffix={false}
          />
          <.text_input
            id="subscriber-user-group"
            field={@form[:user_group]}
            type="basic"
            label={gettext("User group")}
            show_suffix={false}
          />
        </div>
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              phx-click="close-modal"
              phx-value-id="new-email-subscriber-modal"
            />
          </:action>
          <:action>
            <.button
              id="new-email-subscriber-submit"
              label={gettext("Create subscriber")}
              form="new-email-subscriber-form"
              type="submit"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :form, Form, required: true

  defp new_audience_modal(assigns) do
    ~H"""
    <.modal
      id="new-email-audience-modal"
      title={gettext("New audience")}
      description={
        gettext("Group subscribers manually, or keep account contacts in sync with rules.")
      }
      header_type="icon"
      header_size="large"
      on_dismiss="close-new-email-audience-modal"
    >
      <:header_icon><.users /></:header_icon>
      <:trigger :let={modal_attrs}>
        <.button label={gettext("New audience")} size="medium" {modal_attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <.form
        id="new-email-audience-form"
        for={@form}
        phx-change="validate_audience"
        phx-submit="create_audience"
      >
        <div data-part="email-form-grid">
          <.text_input
            id="audience-name"
            field={@form[:name]}
            type="basic"
            label={gettext("Name")}
            required
            show_required
            show_suffix={false}
          />
          <.text_input
            id="audience-slug"
            field={@form[:slug]}
            type="basic"
            label={gettext("Slug")}
            hint={gettext("Leave empty to derive it from the name.")}
            show_suffix={false}
          />
          <.text_area
            id="audience-description"
            field={@form[:description]}
            label={gettext("Description")}
            rows={3}
            max_length={1000}
          />
          <div data-part="email-audience-select">
            <.label label={gettext("Membership")} required />
            <.select
              id="audience-membership-type"
              name={@form[:membership_type].name}
              label={gettext("Select membership type")}
              value={@form[:membership_type].value || "static"}
            >
              <:item value="static" label={gettext("Manual subscribers")} />
              <:item value="dynamic" label={gettext("Dynamic account contacts")} />
            </.select>
          </div>
          <div :if={dynamic_audience_form?(@form)} data-part="email-audience-rules">
            <div data-part="email-audience-rules-heading">
              <.label label={gettext("Matching rules")} />
              <p data-part="email-audience-rules-description">
                {gettext("A contact is included only when every selected rule matches (AND).")}
              </p>
            </div>
            <div data-part="email-audience-select">
              <.label label={gettext("Contact source")} />
              <.select
                id="audience-recipient-source"
                name={"#{@form.name}[rules][recipient_source]"}
                label={gettext("Select contact source")}
                value={audience_rule_value(@form, "recipient_source", "account_contacts")}
              >
                <:item value="account_contacts" label={gettext("Account contacts")} />
                <:item
                  value="incident_contacts"
                  label={gettext("Security incident contacts from contracts")}
                />
              </.select>
            </div>
            <div
              :if={
                audience_rule_value(@form, "recipient_source", "account_contacts") ==
                  "account_contacts"
              }
              data-part="email-audience-select"
            >
              <.label label={gettext("Contacts per matching account")} />
              <.select
                id="audience-contacts-per-account"
                name={"#{@form.name}[rules][contacts_per_account]"}
                label={gettext("Select number of contacts")}
                value={audience_rule_value(@form, "contacts_per_account", "all")}
              >
                <:item value="all" label={gettext("All contacts")} />
                <:item value="one" label={gettext("One contact")} />
              </.select>
              <p data-part="email-audience-select-hint">
                {gettext("One contact uses the alphabetically first email for each account.")}
              </p>
            </div>
            <div data-part="email-audience-select">
              <.label label={gettext("Account lifecycle")} />
              <.select
                id="audience-account-segment"
                name={"#{@form.name}[rules][account_segment]"}
                label={gettext("Select account lifecycle")}
                value={audience_rule_value(@form, "account_segment", "customer")}
              >
                <:item value="customer" label={gettext("Customer (enterprise)")} />
                <:item value="lead" label={gettext("Lead")} />
                <:item value="prospect" label={gettext("Prospect")} />
              </.select>
            </div>
            <div data-part="email-audience-select">
              <.label label={gettext("Deployment")} />
              <.select
                id="audience-hosting"
                name={"#{@form.name}[rules][hosting]"}
                label={gettext("Select deployment")}
                value={audience_rule_value(@form, "hosting", "all")}
              >
                <:item value="all" label={gettext("Any deployment")} />
                <:item value="self_hosted" label={gettext("Self-hosted only")} />
              </.select>
            </div>
          </div>
        </div>
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              phx-click="close-modal"
              phx-value-id="new-email-audience-modal"
            />
          </:action>
          <:action>
            <.button
              id="new-email-audience-submit"
              label={gettext("Create audience")}
              form="new-email-audience-form"
              type="submit"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :form, Form, required: true
  attr :audience, Audience, required: true

  defp broadcast_modal(assigns) do
    ~H"""
    <.modal
      id="new-email-broadcast-modal"
      title={gettext("Send to %{audience}", audience: @audience.name)}
      description={
        gettext(
          "This queues an immediate email to every currently subscribed member. It cannot be scheduled."
        )
      }
      header_type="icon"
      header_size="large"
      on_dismiss="close-new-email-broadcast-modal"
    >
      <:header_icon><.mail /></:header_icon>
      <:trigger :let={modal_attrs}>
        <.button
          id="new-email-broadcast-button"
          label={gettext("New broadcast")}
          size="medium"
          {modal_attrs}
        >
          <:icon_left><.mail /></:icon_left>
        </.button>
      </:trigger>
      <.form
        id="new-email-broadcast-form"
        for={@form}
        phx-change="validate_broadcast"
        phx-submit="queue_broadcast"
      >
        <div data-part="email-form-grid">
          <.text_input
            id="broadcast-subject"
            field={@form[:subject]}
            type="basic"
            label={gettext("Subject")}
            required
            show_required
            show_suffix={false}
          />
          <.text_area
            id="broadcast-body"
            field={@form[:body_markdown]}
            label={gettext("Body in Markdown")}
            rows={10}
            max_length={100_000}
          />
          <.text_input
            id="broadcast-from-name"
            field={@form[:from_name]}
            type="basic"
            label={gettext("From name")}
            required
            show_required
            show_suffix={false}
          />
          <.text_input
            id="broadcast-from-email"
            field={@form[:from_email]}
            type="basic"
            label={gettext("From email")}
            required
            show_required
            show_suffix={false}
          />
          <.text_input
            id="broadcast-reply-to"
            field={@form[:reply_to_email]}
            type="basic"
            label={gettext("Reply-to email")}
            show_suffix={false}
          />
        </div>
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              phx-click="close-modal"
              phx-value-id="new-email-broadcast-modal"
            />
          </:action>
          <:action>
            <.button
              id="queue-email-broadcast"
              label={gettext("Queue broadcast now")}
              form="new-email-broadcast-form"
              type="submit"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp assign_index(socket, params, uri) do
    audiences_page = Query.parse_page(params[@audiences_page_param])
    audiences_query = Query.present_string(params["audiences-query"])
    audiences_available_filters = define_audience_filters()

    audiences_active_filters =
      Filter.Operations.decode_filters_from_query(params, audiences_available_filters)

    {audiences, audiences_meta} =
      GTM.list_email_audiences(
        page: audiences_page,
        page_size: @audiences_page_size,
        query: audiences_query,
        source_id: filter_value(audiences_active_filters, @audiences_source_filter),
        subscribers: filter_value(audiences_active_filters, @audiences_subscribers_filter),
        broadcasts: filter_value(audiences_active_filters, @audiences_broadcasts_filter)
      )

    subscribers_page = Query.parse_page(params[@subscribers_page_param])
    subscribers_query = Query.present_string(params["subscribers-query"])
    subscribers_available_filters = define_subscriber_filters()

    subscribers_active_filters =
      Filter.Operations.decode_filters_from_query(params, subscribers_available_filters)

    {subscribers, subscribers_meta} =
      GTM.list_email_subscribers(
        page: subscribers_page,
        page_size: @subscribers_page_size,
        query: subscribers_query,
        status: filter_value(subscribers_active_filters, @subscribers_status_filter),
        source: filter_value(subscribers_active_filters, @subscribers_source_filter)
      )

    socket
    |> assign(:page_title, gettext("Email"))
    |> assign(:uri, normalized_uri(uri))
    |> assign(:available_filters, audiences_available_filters ++ subscribers_available_filters)
    |> assign(:audiences, audiences)
    |> assign(:audiences_meta, audiences_meta)
    |> assign(:audiences_empty?, audiences == [])
    |> assign(:audiences_query, audiences_query)
    |> assign(:audiences_active_filters, audiences_active_filters)
    |> assign(:audiences_available_filters, audiences_available_filters)
    |> assign(:audiences_search_form, to_form(%{"query" => audiences_query || ""}, as: :search))
    |> assign(:subscribers, subscribers)
    |> assign(:subscribers_meta, subscribers_meta)
    |> assign(:subscribers_empty?, subscribers == [])
    |> assign(:subscribers_query, subscribers_query)
    |> assign(:subscribers_active_filters, subscribers_active_filters)
    |> assign(:subscribers_available_filters, subscribers_available_filters)
    |> assign(:subscribers_search_form, to_form(%{"query" => subscribers_query || ""}, as: :search))
    |> assign_subscriber_form()
    |> assign_audience_form()
  end

  defp assign_audience(socket, %{"id" => id} = params, uri) do
    case GTM.get_email_audience_with_counts(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Audience not found."))
        |> push_navigate(to: ~p"/outbound/email")

      audience ->
        socket
        |> assign(:page_title, audience.name)
        |> assign(:audience, audience)
        |> assign(:uri, normalized_uri(uri))
        |> assign(:subscriber_options, [])
        |> assign(:subscriber_options_loaded?, false)
        |> assign(:membership_form, to_form(%{"subscriber_id" => ""}, as: "membership"))
        |> assign_broadcast_form()
        |> assign_audience_listings(audience, params)
    end
  end

  defp assign_audience_listings(socket, audience, params) do
    memberships_query = Query.present_string(params["members-query"])
    available_filters = if Audience.dynamic?(audience), do: [], else: define_membership_filters()
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {memberships, memberships_meta} =
      GTM.list_email_audience_memberships(audience,
        page: Query.parse_page(params[@memberships_page_param]),
        page_size: @memberships_page_size,
        query: memberships_query,
        status: filter_value(active_filters, @memberships_status_filter)
      )

    {broadcasts, broadcasts_meta} =
      GTM.list_email_audience_broadcasts(audience,
        page: Query.parse_page(params[@broadcasts_page_param]),
        page_size: @broadcasts_page_size
      )

    socket
    |> assign(:available_filters, available_filters)
    |> assign(:memberships, memberships)
    |> assign(:memberships_meta, memberships_meta)
    |> assign(:memberships_query, memberships_query)
    |> assign(:memberships_active_filters, active_filters)
    |> assign(:memberships_available_filters, available_filters)
    |> assign(:memberships_search_form, to_form(%{"query" => memberships_query || ""}, as: :search))
    |> assign(:broadcasts, broadcasts)
    |> assign(:broadcasts_meta, broadcasts_meta)
  end

  # Membership changes do not alter the filters or the page, so the current
  # query string is replayed to keep the reader where they were.
  defp refresh_audience(socket) do
    audience = GTM.get_email_audience_with_counts(socket.assigns.audience.id)
    params = current_query_params(socket)

    socket
    |> assign(:audience, audience)
    |> assign(:membership_form, to_form(%{"subscriber_id" => ""}, as: "membership"))
    |> assign_audience_listings(audience, params)
  end

  defp filtered_path(socket, query_params) do
    case socket.assigns.live_action do
      :index -> ~p"/outbound/email?#{query_params}"
      :audience -> audience_path(socket, query_params)
    end
  end

  defp audience_path(socket, query_params) do
    ~p"/outbound/email/audiences/#{socket.assigns.audience.id}?#{query_params}"
  end

  defp define_membership_filters do
    [
      option_filter(
        @memberships_status_filter,
        gettext("Status"),
        AudienceMembership.statuses(),
        &subscriber_status_label/1,
        searchable: true
      )
    ]
  end

  defp assign_subscriber_form(socket) do
    form =
      %Subscriber{}
      |> GTM.change_email_subscriber(%{source: "atlas", status: "subscribed"})
      |> to_form(as: "subscriber")

    assign(socket, :subscriber_form, form)
  end

  defp assign_audience_form(socket) do
    form =
      %Audience{}
      |> GTM.change_email_audience(%{})
      |> to_form(as: "audience")

    assign(socket, :audience_form, form)
  end

  defp assign_broadcast_form(socket) do
    form =
      socket.assigns.audience
      |> GTM.change_email_broadcast(%{}, socket.assigns.current_user)
      |> to_form(as: "broadcast")

    assign(socket, :broadcast_form, form)
  end

  defp define_audience_filters do
    presence_values = GTM.email_audience_presence_values()

    [
      option_filter(
        @audiences_source_filter,
        gettext("Source"),
        GTM.distinct_email_audience_source_ids(),
        & &1,
        searchable: true
      ),
      option_filter(
        @audiences_subscribers_filter,
        gettext("Subscribers"),
        presence_values,
        &subscribers_presence_label/1
      ),
      option_filter(
        @audiences_broadcasts_filter,
        gettext("Broadcasts"),
        presence_values,
        &broadcasts_presence_label/1
      )
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp define_subscriber_filters do
    statuses = Subscriber.statuses()

    [
      option_filter(
        @subscribers_status_filter,
        gettext("Status"),
        statuses,
        &subscriber_status_label/1,
        searchable: true
      ),
      option_filter(
        @subscribers_source_filter,
        gettext("Source"),
        GTM.distinct_email_subscriber_sources(),
        & &1,
        searchable: true
      )
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  # Option filters offer both "is" and "is not", so the operator travels to the
  # context alongside the value.
  defp filter_value(active_filters, filter_id) do
    with %{operator: operator, value: value} <- Enum.find(active_filters, &(&1.id == filter_id)),
         value when not is_nil(value) <- Query.present_string(value) do
      {operator, value}
    else
      _other -> nil
    end
  end

  defp normalized_uri(uri) do
    query = if is_binary(uri), do: URI.parse(uri).query, else: uri && uri.query
    %URI{query: query || ""}
  end

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp reset_page(params, page_param) do
    if Map.has_key?(params, page_param) do
      Map.delete(params, page_param)
    else
      params
    end
  end

  defp reset_subscribers_page(socket) do
    socket
    |> current_query_params()
    |> reset_page(@subscribers_page_param)
  end

  defp reset_audiences_page(socket) do
    socket
    |> current_query_params()
    |> reset_page(@audiences_page_param)
  end

  defp put_search_query(params, key, value) do
    case Query.present_string(value) do
      nil -> Map.delete(params, key)
      trimmed -> Map.put(params, key, trimmed)
    end
  end

  # Callers pass options already in the order they should be offered: the
  # queries behind them sort, and statuses read in lifecycle order.
  defp option_filter(id, display_name, options, formatter, opts \\ []) do
    options =
      options
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      options: options,
      options_display_names: Map.new(options, &{&1, formatter.(&1)}),
      operator: :==,
      searchable: Keyword.get(opts, :searchable, false),
      value: nil
    }
  end

  defp subscribers_presence_label("present"), do: gettext("Has subscribers")
  defp subscribers_presence_label("absent"), do: gettext("No subscribers")

  defp audience_membership_type_label(audience) do
    if Audience.dynamic?(audience), do: gettext("Dynamic"), else: gettext("Manual")
  end

  defp audience_membership_type_color(audience) do
    if Audience.dynamic?(audience), do: "primary", else: "neutral"
  end

  defp dynamic_audience_rule_summary(audience) do
    rules = audience.rules || %{}

    gettext("Includes %{contacts} from active %{lifecycle} accounts %{deployment}.",
      contacts: contacts_per_account_label(rules),
      lifecycle: lifecycle_label(Map.get(rules, "account_segment")),
      deployment: deployment_label(Map.get(rules, "hosting"))
    )
  end

  defp recipient_source_label("incident_contacts"), do: gettext("security incident contacts extracted from contracts")
  defp recipient_source_label(_source), do: gettext("account contacts")

  defp contacts_per_account_label(rules) do
    case {Map.get(rules, "recipient_source"), Map.get(rules, "contacts_per_account", "all")} do
      {"account_contacts", "one"} -> gettext("one account contact per account")
      {_recipient_source, _contacts_per_account} -> recipient_source_label(Map.get(rules, "recipient_source"))
    end
  end

  defp lifecycle_label("customer"), do: gettext("customer")
  defp lifecycle_label("lead"), do: gettext("lead")
  defp lifecycle_label("prospect"), do: gettext("prospect")
  defp lifecycle_label(_segment), do: gettext("customer")

  defp deployment_label("self_hosted"), do: gettext("with self-hosted deployments")
  defp deployment_label(_hosting), do: gettext("across every deployment")

  defp audience_rule_value(form, rule, default) do
    case form[:rules].value do
      rules when is_map(rules) -> Map.get(rules, rule, default)
      _rules -> default
    end
  end

  defp dynamic_audience_form?(form), do: form[:membership_type].value == "dynamic"

  defp broadcasts_presence_label("present"), do: gettext("Has broadcasts")
  defp broadcasts_presence_label("absent"), do: gettext("Never broadcast")

  defp subscriber_status_label("pending"), do: gettext("Pending")
  defp subscriber_status_label("subscribed"), do: gettext("Subscribed")
  defp subscriber_status_label("unsubscribed"), do: gettext("Unsubscribed")
  defp subscriber_status_label(_status), do: gettext("Unknown")

  defp subscriber_status_color("subscribed"), do: "success"
  defp subscriber_status_color("pending"), do: "warning"
  defp subscriber_status_color(_status), do: "neutral"

  defp broadcast_status_label("pending"), do: gettext("Pending")
  defp broadcast_status_label("sending"), do: gettext("Sending")
  defp broadcast_status_label("sent"), do: gettext("Sent")
  defp broadcast_status_label("failed"), do: gettext("Failed")
  defp broadcast_status_label(_status), do: gettext("Unknown")

  defp broadcast_status_color("sent"), do: "success"
  defp broadcast_status_color("failed"), do: "destructive"
  defp broadcast_status_color(_status), do: "warning"

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  defp format_datetime(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")

  defp format_datetime(_datetime), do: gettext("Not yet")
end
