defmodule AtlasWeb.POCLive.Show do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Accounts.FeatureInterests
  alias Atlas.Accounts.POCs
  alias Atlas.Accounts.POCs.Context
  alias Atlas.Accounts.POCs.Notifier, as: POCNotifier
  alias Atlas.Accounts.POCs.TimelineEntry

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case POCs.get_poc(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "POC not found.")
         |> redirect(to: ~p"/commercial/sales/pocs")}

      poc ->
        {:ok,
         socket
         |> assign(:page_title, poc.title)
         |> assign(:can_manage?, POCs.can_manage?(socket.assigns.current_user))
         |> assign_poc(poc)
         |> assign_context_form()
         |> assign_timeline_form()}
    end
  end

  @impl true
  def handle_event("save_context", %{"context" => params}, socket) do
    case POCs.upsert_context(socket.assigns.poc, params, socket.assigns.current_user) do
      {:ok, _context} ->
        poc = POCs.get_poc!(socket.assigns.poc.id)

        {:noreply,
         socket
         |> put_flash(:info, "Context saved.")
         |> assign_poc(poc)
         |> assign_context_form()}

      {:error, changeset} ->
        {:noreply, assign(socket, :context_form, to_form(changeset, as: :context))}
    end
  end

  def handle_event("add_timeline_entry", %{"timeline_entry" => params}, socket) do
    case POCs.add_timeline_entry(socket.assigns.poc, params, socket.assigns.current_user) do
      {:ok, _entry} ->
        poc = POCs.get_poc!(socket.assigns.poc.id)

        {:noreply,
         socket
         |> put_flash(:info, "Timeline entry added.")
         |> assign_poc(poc)
         |> assign_timeline_form()}

      {:error, changeset} ->
        {:noreply, assign(socket, :timeline_form, to_form(changeset, as: :timeline_entry))}
    end
  end

  def handle_event("delete_timeline_entry", %{"id" => entry_id}, socket) do
    with %TimelineEntry{} = entry <- POCs.get_timeline_entry(entry_id),
         {:ok, _deleted} <-
           POCs.delete_timeline_entry(socket.assigns.poc, entry, socket.assigns.current_user) do
      poc = POCs.get_poc!(socket.assigns.poc.id)

      {:noreply,
       socket
       |> put_flash(:info, "Timeline entry removed.")
       |> assign_poc(poc)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not remove that entry.")}
    end
  end

  def handle_event("publish", _params, socket) do
    case POCs.publish_poc(socket.assigns.poc, socket.assigns.current_user) do
      {:ok, poc} ->
        {:noreply,
         socket
         |> put_flash(:info, "POC published. Share the public link below.")
         |> assign_poc(POCs.get_poc!(poc.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not publish POC.")}
    end
  end

  def handle_event("unpublish", _params, socket) do
    case POCs.unpublish_poc(socket.assigns.poc, socket.assigns.current_user) do
      {:ok, poc} ->
        {:noreply,
         socket
         |> put_flash(:info, "Public link revoked.")
         |> assign_poc(POCs.get_poc!(poc.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not revoke the public link.")}
    end
  end

  def handle_event("rotate_token", _params, socket) do
    case POCs.rotate_public_token(socket.assigns.poc, socket.assigns.current_user) do
      {:ok, poc} ->
        {:noreply,
         socket
         |> put_flash(:info, "Public link rotated. Reshare with the customer.")
         |> assign_poc(POCs.get_poc!(poc.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not rotate the link.")}
    end
  end

  def handle_event("add_scope_feature", %{"feature_interest_id" => id}, socket) when is_binary(id) and id != "" do
    case POCs.add_scope_feature(socket.assigns.poc, id, socket.assigns.current_user) do
      {:ok, _scope_feature} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scope feature added.")
         |> assign_poc(POCs.get_poc!(socket.assigns.poc.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not add scope feature.")}
    end
  end

  def handle_event("add_scope_feature", _params, socket), do: {:noreply, socket}

  def handle_event("remove_scope_feature", %{"feature_interest_id" => id}, socket) do
    case POCs.remove_scope_feature(socket.assigns.poc, id, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, assign_poc(socket, POCs.get_poc!(socket.assigns.poc.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not remove scope feature.")}
    end
  end

  def handle_event("approve_access_request", %{"id" => id}, socket) do
    with {:ok, request} <- POCs.approve_access_request(id, socket.assigns.current_user),
         :ok <- refresh_slack_message(socket.assigns.poc, request) do
      {:noreply,
       socket
       |> put_flash(:info, "Approved access for #{request.email}.")
       |> assign_poc(POCs.get_poc!(socket.assigns.poc.id))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not approve the request.")}
    end
  end

  def handle_event("deny_access_request", %{"id" => id}, socket) do
    with {:ok, request} <- POCs.deny_access_request(id, socket.assigns.current_user),
         :ok <- refresh_slack_message(socket.assigns.poc, request) do
      {:noreply,
       socket
       |> put_flash(:info, "Denied access for #{request.email}.")
       |> assign_poc(POCs.get_poc!(socket.assigns.poc.id))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not deny the request.")}
    end
  end

  def handle_event("revoke_access_request", %{"id" => id}, socket) do
    with {:ok, request} <- POCs.revoke_access_request(id, socket.assigns.current_user),
         :ok <- refresh_slack_message(socket.assigns.poc, request) do
      {:noreply,
       socket
       |> put_flash(:info, "Revoked access for #{request.email}.")
       |> assign_poc(POCs.get_poc!(socket.assigns.poc.id))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not revoke the request.")}
    end
  end

  # Slack notifications are optional. If the request never carried a Slack
  # message ts (Slack was not configured when the request came in), skip the
  # refresh instead of failing the whole operation.
  defp refresh_slack_message(poc, request) do
    case POCNotifier.refresh_slack_message(poc, request) do
      {:ok, _} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp assign_poc(socket, poc) do
    feature_interests = FeatureInterests.list()
    scope_feature_ids = MapSet.new(poc.scope_features, & &1.feature_interest_id)

    available_features =
      Enum.reject(feature_interests, &MapSet.member?(scope_feature_ids, &1.id))

    socket
    |> assign(:poc, poc)
    |> assign(:available_features, available_features)
    |> assign(:public_url, public_url(poc, socket))
    |> assign(:access_requests, POCs.list_access_requests(poc))
  end

  defp assign_context_form(socket) do
    context = socket.assigns.poc.context || %Context{}
    assign(socket, :context_form, to_form(Context.changeset(context, %{}), as: :context))
  end

  defp assign_timeline_form(socket) do
    changeset =
      TimelineEntry.changeset(%TimelineEntry{kind: "event", occurred_on: Date.utc_today()}, %{})

    assign(socket, :timeline_form, to_form(changeset, as: :timeline_entry))
  end

  defp public_url(%{public_token: nil}, _socket), do: nil

  defp public_url(%{public_token: token}, _socket) do
    url(~p"/p/pocs/#{token}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="poc-show">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{@poc.title}</h1>
          <p :if={@poc.account}>{@poc.account.name}</p>
        </div>
        <div data-part="header-actions">
          <.button
            :if={@can_manage?}
            label="Edit"
            href={~p"/commercial/sales/pocs/#{@poc.id}/edit"}
            variant="secondary"
            size="medium"
          />
          <.button
            :if={@can_manage? and is_nil(@poc.public_token)}
            label="Publish public brief"
            phx-click="publish"
            variant="primary"
            size="medium"
          />
          <.button
            :if={@can_manage? and not is_nil(@poc.public_token)}
            label="Rotate link"
            phx-click="rotate_token"
            variant="secondary"
            size="medium"
          />
          <.button
            :if={@can_manage? and not is_nil(@poc.public_token)}
            label="Revoke link"
            phx-click="unpublish"
            variant="secondary"
            size="medium"
          />
        </div>
      </div>

      <.card :if={@public_url} icon="link_icon" title="Public brief">
        <.card_section>
          <p>Share this signed URL with the customer:</p>
          <p><a href={@public_url} target="_blank" rel="noopener noreferrer">{@public_url}</a></p>
        </.card_section>
      </.card>

      <.card :if={@access_requests != []} icon="users" title="Access requests">
        <.card_section>
          <p>
            Approve or deny customers requesting to open the public brief. Slack buttons post the same actions to the operator channel when it is configured.
          </p>
          <ul>
            <li :for={request <- @access_requests}>
              <strong>{request.email}</strong>
              &nbsp; <span>{Atlas.Accounts.POCs.AccessRequest.status(request)}</span>
              <span :if={request.verified_at}>&nbsp;- email confirmed</span>
              <.button
                :if={@can_manage? and can_approve?(request)}
                label="Approve"
                variant="primary"
                size="small"
                phx-click="approve_access_request"
                phx-value-id={request.id}
              />
              <.button
                :if={@can_manage? and can_deny?(request)}
                label="Deny"
                variant="secondary"
                size="small"
                phx-click="deny_access_request"
                phx-value-id={request.id}
              />
              <.button
                :if={@can_manage? and can_revoke?(request)}
                label="Revoke"
                variant="secondary"
                size="small"
                phx-click="revoke_access_request"
                phx-value-id={request.id}
                data-confirm="Revoke this person's access?"
              />
            </li>
          </ul>
        </.card_section>
      </.card>

      <.card icon="checkup_list" title="Overview">
        <.card_section>
          <p><strong>Status:</strong> {humanize(@poc.status)}</p>
          <p><strong>Hosting:</strong> {humanize(@poc.hosting)}</p>
          <p :if={@poc.starts_on}><strong>Starts:</strong> {@poc.starts_on}</p>
          <p :if={@poc.ends_on}><strong>Ends:</strong> {@poc.ends_on}</p>
          <p :if={@poc.summary}>{@poc.summary}</p>
        </.card_section>
      </.card>

      <.card icon="file_text" title="Context">
        <.card_section>
          <.form
            for={@context_form}
            id="poc-context-form"
            phx-submit="save_context"
          >
            <.text_input
              id="context-developer-count"
              field={@context_form[:developer_count]}
              input_type="number"
              min={0}
              label="Developer count"
              show_suffix={false}
            />
            <div data-part="select-field">
              <span>CI solution</span>
              <.select
                id="context-ci-solution"
                name={@context_form[:ci_solution].name}
                value={to_string(@context_form[:ci_solution].value)}
                label="Unknown"
              >
                <:item
                  :for={value <- Context.ci_solutions()}
                  value={value}
                  label={humanize(value)}
                />
              </.select>
            </div>
            <div data-part="select-field">
              <span>Git forge</span>
              <.select
                id="context-git-forge"
                name={@context_form[:git_forge].name}
                value={to_string(@context_form[:git_forge].value)}
                label="Unknown"
              >
                <:item
                  :for={value <- Context.git_forges()}
                  value={value}
                  label={humanize(value)}
                />
              </.select>
            </div>
            <div data-part="select-field">
              <span>Primary language</span>
              <.select
                id="context-primary-language"
                name={@context_form[:primary_language].name}
                value={to_string(@context_form[:primary_language].value)}
                label="Unknown"
              >
                <:item
                  :for={value <- Context.primary_languages()}
                  value={value}
                  label={humanize(value)}
                />
              </.select>
            </div>
            <div data-part="select-field">
              <span>Monorepo</span>
              <.select
                id="context-monorepo"
                name={@context_form[:monorepo].name}
                value={to_string(@context_form[:monorepo].value)}
                label="Unknown"
              >
                <:item value="true" label="Yes" />
                <:item value="false" label="No" />
              </.select>
            </div>
            <.text_area
              field={@context_form[:notes]}
              label="Notes"
              rows={4}
              max_length={8000}
            />
            <div data-part="form-actions">
              <.button label="Save context" type="submit" variant="primary" size="medium" />
            </div>
          </.form>
        </.card_section>
      </.card>

      <.card icon="list_tree" title="Scope">
        <.card_section>
          <ul :if={@poc.scope_features != []}>
            <li :for={scope <- @poc.scope_features}>
              {scope.feature_interest.title}
              <.button
                :if={@can_manage?}
                label="Remove"
                variant="secondary"
                size="small"
                phx-click="remove_scope_feature"
                phx-value-feature_interest_id={scope.feature_interest_id}
              />
            </li>
          </ul>
          <form :if={@can_manage? and @available_features != []} phx-submit="add_scope_feature">
            <div data-part="select-field">
              <span>Add feature</span>
              <.select id="scope-feature-select" name="feature_interest_id" label="Select feature">
                <:item
                  :for={feature <- @available_features}
                  value={feature.id}
                  label={feature.title}
                />
              </.select>
            </div>
            <div data-part="form-actions">
              <.button label="Add to scope" type="submit" variant="secondary" size="small" />
            </div>
          </form>
        </.card_section>
      </.card>

      <.card icon="calendar_week" title="Timeline">
        <.card_section>
          <ul :if={@poc.timeline_entries != []}>
            <li :for={entry <- @poc.timeline_entries}>
              <strong>{entry.occurred_on}</strong>
              · {humanize(entry.kind)} · {entry.title}
              <p :if={entry.body}>{entry.body}</p>
              <.button
                :if={@can_manage?}
                label="Remove"
                variant="secondary"
                size="small"
                phx-click="delete_timeline_entry"
                phx-value-id={entry.id}
                data-confirm="Remove this entry?"
              />
            </li>
          </ul>
          <.form
            :if={@can_manage?}
            for={@timeline_form}
            id="poc-timeline-form"
            phx-submit="add_timeline_entry"
          >
            <.text_input
              id="timeline-occurred-on"
              field={@timeline_form[:occurred_on]}
              input_type="date"
              label="Date"
              show_suffix={false}
            />
            <.text_input field={@timeline_form[:title]} label="Title" />
            <div data-part="select-field">
              <span>Kind</span>
              <.select
                id="timeline-kind"
                name={@timeline_form[:kind].name}
                value={to_string(@timeline_form[:kind].value)}
                label="Select kind"
              >
                <:item
                  :for={kind <- TimelineEntry.kinds()}
                  value={kind}
                  label={humanize(kind)}
                />
              </.select>
            </div>
            <.text_area field={@timeline_form[:body]} label="Details" rows={3} max_length={8000} />
            <div data-part="form-actions">
              <.button label="Add entry" type="submit" variant="primary" size="medium" />
            </div>
          </.form>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp humanize(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.capitalize()
  end

  defp humanize(value), do: to_string(value)

  defp can_approve?(request),
    do: is_nil(request.approved_at) and is_nil(request.denied_at) and is_nil(request.revoked_at)

  defp can_deny?(request), do: is_nil(request.approved_at) and is_nil(request.denied_at) and is_nil(request.revoked_at)

  defp can_revoke?(request), do: not is_nil(request.approved_at) and is_nil(request.revoked_at)
end
