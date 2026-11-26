defmodule AtlasWeb.SocialPublishingLive do
  @moduledoc """
  Drafts, approves and schedules posts and threads for the X accounts Atlas
  holds. Approval covers the saved revision on screen; unsaved edits must be
  saved, which returns the publication to draft, before anyone approves it.
  """

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.GTM.SocialAccounts
  alias Atlas.GTM.SocialMedia
  alias Atlas.GTM.SocialPublication
  alias Atlas.GTM.SocialPublishing

  @max_items 25

  def mount(_params, _session, socket) do
    socket =
      Enum.reduce(0..(@max_items - 1), socket, fn index, socket ->
        allow_upload(socket, upload_name(index),
          accept: ~w(.jpg .jpeg .png .webp .gif .mp4 .mov),
          max_entries: 4,
          max_file_size: SocialMedia.max_bytes("video"),
          auto_upload: true,
          progress: &handle_progress/3
        )
      end)

    {:ok,
     socket
     |> assign(:page_title, gettext("Publishing"))
     |> assign(:can_manage, SocialAccounts.can_manage?(socket.assigns.current_user))
     |> assign(:accounts, Enum.filter(SocialAccounts.list(), &(&1.platform == "x")))}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:publication, nil)
    |> assign(:publications, SocialPublishing.list())
  end

  defp apply_action(socket, :new, _params) do
    account_id = socket.assigns.accounts |> List.first(%{}) |> Map.get(:id)

    socket
    |> assign(:publication, nil)
    |> assign_draft(%{
      "social_account_id" => account_id,
      "scheduled_at" => nil,
      "items" => [%{"text" => "", "media_ids" => []}]
    })
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    case SocialPublishing.get(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Publication not found."))
        |> push_navigate(to: ~p"/commercial/gtm/social/publishing")

      publication ->
        socket
        |> assign(:publication, publication)
        |> assign_draft(%{
          "social_account_id" => publication.social_account_id,
          "scheduled_at" => DateTime.to_iso8601(publication.scheduled_at),
          "items" => publication.items
        })
    end
  end

  defp assign_draft(socket, draft) do
    socket
    |> assign(:draft, draft)
    |> assign(:dirty, false)
    |> assign(:error, nil)
    |> assign_media()
  end

  defp assign_media(socket) do
    ids = Enum.flat_map(socket.assigns.draft["items"], & &1["media_ids"])
    assign(socket, :media, Map.new(SocialPublishing.media(ids), &{&1.id, &1}))
  end

  def handle_event("change", %{"publication" => params}, socket) do
    texts = Map.get(params, "items", %{})

    items =
      socket.assigns.draft["items"]
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        Map.put(item, "text", get_in(texts, [to_string(index), "text"]) || item["text"])
      end)

    draft =
      socket.assigns.draft
      |> Map.merge(Map.take(params, ["social_account_id", "scheduled_at"]))
      |> Map.put("items", items)

    {:noreply, socket |> assign(:draft, draft) |> assign(:dirty, true)}
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  def handle_event("add_item", _params, socket) do
    items = socket.assigns.draft["items"]

    if length(items) < @max_items do
      {:noreply, update_items(socket, items ++ [%{"text" => "", "media_ids" => []}])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_item", %{"index" => index}, socket) do
    {:noreply, update_items(socket, List.delete_at(socket.assigns.draft["items"], String.to_integer(index)))}
  end

  def handle_event("remove_media", %{"index" => index, "id" => id}, socket) do
    items =
      List.update_at(
        socket.assigns.draft["items"],
        String.to_integer(index),
        &Map.update!(&1, "media_ids", fn ids -> ids -- [id] end)
      )

    {:noreply, update_items(socket, items)}
  end

  def handle_event("save", _params, socket) do
    %{current_user: user, draft: draft, publication: publication} = socket.assigns

    result =
      Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
        if publication,
          do: SocialPublishing.update(user, publication.id, draft),
          else: SocialPublishing.create(user, draft)
      end)

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Saved. Approve it to schedule publishing."))
         |> push_patch(to: ~p"/commercial/gtm/social/publishing/#{saved.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  def handle_event("approve", %{"revision" => revision}, socket) do
    %{current_user: user, publication: publication} = socket.assigns

    result =
      Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
        SocialPublishing.approve(user, publication.id, String.to_integer(revision))
      end)

    case result do
      {:ok, _approved} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Approved. Atlas publishes it at the scheduled time."))
         |> push_patch(to: ~p"/commercial/gtm/social/publishing/#{publication.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  def handle_event("cancel", _params, socket) do
    %{current_user: user, publication: publication} = socket.assigns

    case Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
           SocialPublishing.cancel(user, publication.id)
         end) do
      {:ok, _cancelled} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Cancelled. It will not publish."))
         |> push_patch(to: ~p"/commercial/gtm/social/publishing/#{publication.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  defp handle_progress(name, entry, socket) do
    if entry.done? do
      index = name |> Atom.to_string() |> String.replace_prefix("media_", "") |> String.to_integer()
      user = socket.assigns.current_user

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, SocialPublishing.store_media(user, entry.client_name, entry.client_type, File.read!(path))}
        end)

      case result do
        {:ok, media} ->
          items =
            List.update_at(
              socket.assigns.draft["items"],
              index,
              &Map.update!(&1, "media_ids", fn ids -> ids ++ [media.id] end)
            )

          {:noreply, update_items(socket, items)}

        {:error, reason} ->
          {:noreply, assign(socket, :error, error_message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  defp update_items(socket, items) do
    socket
    |> assign(:draft, Map.put(socket.assigns.draft, "items", items))
    |> assign(:dirty, true)
    |> assign_media()
  end

  def render(assigns) do
    ~H"""
    <div id="gtm-social-publishing" data-part="gtm-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Publishing")}</h1>
          <p data-part="description">
            {gettext(
              "Posts and threads for the X accounts Atlas holds. Nothing publishes until a person approves the exact post; any edit needs a new approval."
            )}
          </p>
        </div>
        <div :if={@can_manage and @live_action == :index} data-part="header-actions">
          <.button
            id="social-publication-new"
            label={gettext("New post")}
            variant="primary"
            size="medium"
            patch={~p"/commercial/gtm/social/publishing/new"}
          />
        </div>
      </div>

      <section :if={@live_action == :index} data-part="page-section">
        <.card title={gettext("Publications")} icon="calendar_week" data-part="ideas-card">
          <.card_section data-part="ideas-table-section">
            <.table id="social-publications" rows={@publications} row_key={& &1.id}>
              <:col :let={publication} label={gettext("Post")}>
                <div data-part="source-entry">
                  <.link
                    patch={~p"/commercial/gtm/social/publishing/#{publication.id}"}
                    data-part="source-title"
                  >
                    {preview(publication)}
                  </.link>
                  <span data-part="source-description">
                    {account_label(publication.social_account)}
                  </span>
                </div>
              </:col>
              <:col :let={publication} label={gettext("Scheduled")}>
                <.local_time
                  id={"social-publication-time-#{publication.id}"}
                  time={publication.scheduled_at}
                />
              </:col>
              <:col :let={publication} label={gettext("Status")}>
                <.status_badge_cell
                  status={status_color(publication)}
                  label={status_label(publication)}
                />
              </:col>
              <:col :let={publication} label={gettext("Approved by")}>
                <.text_cell label={person(publication.approved_by)} />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="calendar_week"
                  title={gettext("Nothing scheduled")}
                  subtitle={
                    gettext(
                      "Draft a post here, or ask an agent to draft one with save_social_publication."
                    )
                  }
                />
              </:empty_state>
            </.table>
          </.card_section>
        </.card>
      </section>

      <section :if={@live_action in [:new, :show]} data-part="page-section">
        <.alert :if={@error} id="social-publication-error" status="error" title={@error} />
        <.approval_panel
          :if={@publication}
          publication={@publication}
          dirty={@dirty}
          current_user={@current_user}
          can_manage={@can_manage}
        />

        <.card title={gettext("Post")} icon="brand_x" data-part="ideas-card">
          <.card_section>
            <.form
              :if={editable?(@publication) and @can_manage}
              for={%{}}
              as={:publication}
              id="social-publication-form"
              phx-change="change"
              phx-submit="save"
              data-part="publication-form"
            >
              <div data-part="publication-fields">
                <div data-part="publication-time">
                  <.label label={gettext("Account")} />
                  <.select
                    id="social-publication-account"
                    name="publication[social_account_id]"
                    label={
                      account_label(Enum.find(@accounts, &(&1.id == @draft["social_account_id"])))
                    }
                    value={@draft["social_account_id"]}
                  >
                    <:item
                      :for={account <- @accounts}
                      value={account.id}
                      label={account_label(account)}
                    />
                  </.select>
                </div>
                <div data-part="publication-time">
                  <.label label={gettext("Publish at (your time)")} />
                  <input
                    type="datetime-local"
                    id="social-publication-local-time"
                    phx-hook=".LocalDateTime"
                    phx-update="ignore"
                    data-target="social-publication-scheduled-at"
                    class="noora-text-input-native"
                    data-part="native-input"
                  />
                  <input
                    type="hidden"
                    id="social-publication-scheduled-at"
                    name="publication[scheduled_at]"
                    value={@draft["scheduled_at"]}
                  />
                </div>
              </div>

              <div
                :for={{item, index} <- Enum.with_index(@draft["items"])}
                id={"social-publication-item-#{index}"}
                data-part="publication-item"
              >
                <.text_area
                  id={"social-publication-text-#{index}"}
                  name={"publication[items][#{index}][text]"}
                  value={item["text"]}
                  label={
                    if(length(@draft["items"]) > 1,
                      do: gettext("Post %{n}", n: index + 1),
                      else: gettext("Text")
                    )
                  }
                  rows={4}
                  max_length={4000}
                  show_character_count={false}
                  hint={
                    gettext("%{count} / 280", count: SocialPublishing.weighted_length(item["text"]))
                  }
                  hint_variant={
                    if(SocialPublishing.weighted_length(item["text"]) > 280,
                      do: "destructive",
                      else: "default"
                    )
                  }
                />
                <div data-part="publication-media">
                  <span :for={id <- item["media_ids"]} data-part="media-chip">
                    {media_label(@media[id])}
                    <button
                      type="button"
                      phx-click="remove_media"
                      phx-value-index={index}
                      phx-value-id={id}
                      aria-label={gettext("Remove")}
                    >
                      ×
                    </button>
                  </span>
                  <span :for={entry <- @uploads[upload_name(index)].entries} data-part="media-chip">
                    {entry.client_name} · {entry.progress}%
                  </span>
                  <label
                    class="noora-button"
                    data-variant="secondary"
                    data-size="small"
                    data-part="upload-button"
                  >
                    <.live_file_input upload={@uploads[upload_name(index)]} />
                    <span>{gettext("Add image or video")}</span>
                  </label>
                  <.button
                    :if={length(@draft["items"]) > 1}
                    type="button"
                    label={gettext("Remove post")}
                    variant="secondary"
                    size="small"
                    phx-click="remove_item"
                    phx-value-index={index}
                  />
                </div>
              </div>

              <div data-part="publication-actions">
                <.button
                  type="button"
                  id="social-publication-add-item"
                  label={gettext("Add post to thread")}
                  variant="secondary"
                  size="medium"
                  phx-click="add_item"
                />
                <.button
                  type="submit"
                  id="social-publication-save"
                  label={gettext("Save draft")}
                  variant="primary"
                  size="medium"
                />
              </div>
            </.form>

            <div :if={not (editable?(@publication) and @can_manage)} data-part="publication-preview">
              <div
                :for={{item, index} <- Enum.with_index(@draft["items"])}
                id={"social-publication-preview-#{index}"}
                data-part="publication-item"
              >
                <p data-part="publication-text">{item["text"]}</p>
                <div data-part="publication-media">
                  <span :for={id <- item["media_ids"]} data-part="media-chip">
                    {media_label(@media[id])}
                  </span>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalDateTime">
        const pad = (n) => String(n).padStart(2, "0")
        const toLocalInput = (iso) => {
          const d = new Date(iso)
          return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
        }
        export default {
          mounted() {
            const target = document.getElementById(this.el.dataset.target)
            if (target.value) this.el.value = toLocalInput(target.value)
            this.el.addEventListener("change", () => {
              target.value = this.el.value ? new Date(this.el.value).toISOString() : ""
              target.dispatchEvent(new Event("input", {bubbles: true}))
            })
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
        const render = (el) => {
          el.textContent = new Date(el.dateTime).toLocaleString(undefined, {dateStyle: "medium", timeStyle: "short"})
        }
        export default { mounted() { render(this.el) }, updated() { render(this.el) } }
      </script>
    </div>
    """
  end

  attr :publication, SocialPublication, required: true
  attr :dirty, :boolean, required: true
  attr :current_user, :any, required: true
  attr :can_manage, :boolean, required: true

  defp approval_panel(assigns) do
    assigns =
      assigns
      |> assign(:blocker, approval_blocker(assigns.publication, assigns.current_user, assigns.dirty))
      |> assign(:approvable, approvable?(assigns.publication))

    ~H"""
    <.card title={gettext("Approval")} icon="circle_check" data-part="ideas-card">
      <.card_section>
        <div id="social-publication-status" data-part="publication-status">
          <.status_badge status={status_color(@publication)} label={status_label(@publication)} />
          <span>
            {account_label(@publication.social_account)} ·
            <.local_time id="social-publication-scheduled" time={@publication.scheduled_at} />
          </span>
          <span :if={@publication.approved_by}>
            {gettext("Approved by %{name}", name: person(@publication.approved_by))}
          </span>
          <.link
            :if={SocialPublication.url(@publication)}
            href={SocialPublication.url(@publication)}
            target="_blank"
            rel="noopener"
          >
            {gettext("View on X")}
          </.link>
        </div>
        <p
          :if={@publication.last_error}
          id="social-publication-last-error"
          data-part="publication-error"
        >
          {@publication.last_error}
        </p>
        <p
          :if={@approvable and @blocker}
          id="social-publication-blocker"
          data-part="publication-blocker"
        >
          {@blocker}
        </p>
        <div :if={@can_manage} data-part="publication-actions">
          <.button
            :if={@approvable}
            id="social-publication-approve"
            label={approve_label(@publication)}
            variant="primary"
            size="medium"
            disabled={@blocker != nil}
            phx-click="approve"
            phx-value-revision={@publication.revision}
            data-confirm={
              gettext("Publish this exact post to %{account}? Atlas cannot unpublish it.",
                account: account_label(@publication.social_account)
              )
            }
          />
          <.button
            :if={@publication.status in ~w(draft approved failed)}
            id="social-publication-cancel"
            label={gettext("Cancel publication")}
            variant="secondary"
            size="medium"
            phx-click="cancel"
          />
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :id, :string, required: true
  attr :time, DateTime, required: true

  defp local_time(assigns) do
    ~H"""
    <time id={@id} phx-hook=".LocalTime" datetime={DateTime.to_iso8601(@time)}>
      {Calendar.strftime(@time, "%Y-%m-%d %H:%M UTC")}
    </time>
    """
  end

  defp upload_name(index), do: String.to_atom("media_#{index}")

  defp editable?(nil), do: true
  defp editable?(publication), do: SocialPublication.editable?(publication)

  defp approvable?(publication), do: publication.status in ~w(draft failed) or SocialPublication.stalled?(publication)

  defp approval_blocker(publication, user, dirty) do
    account = publication.social_account

    cond do
      dirty ->
        gettext("Save your changes before approving.")

      account && account.kind == "personal" && account.connected_by_id != user.id ->
        gettext("Only the person who connected %{account} can approve its posts.", account: account.handle)

      true ->
        case SocialPublishing.can_publish(publication) do
          :ok -> nil
          {:error, reason} -> error_message(reason)
        end
    end
  end

  defp approve_label(publication) do
    if DateTime.after?(publication.scheduled_at, DateTime.utc_now()),
      do: gettext("Approve and schedule"),
      else: gettext("Approve and publish now")
  end

  defp status_label(publication) do
    if SocialPublication.stalled?(publication) do
      gettext("Stalled")
    else
      case publication.status do
        "draft" -> gettext("Draft")
        "approved" -> gettext("Scheduled")
        "publishing" -> gettext("Publishing")
        "published" -> gettext("Published")
        "failed" -> gettext("Failed")
        "cancelled" -> gettext("Cancelled")
      end
    end
  end

  defp status_color(%SocialPublication{status: "published"}), do: "success"
  defp status_color(%SocialPublication{status: "failed"}), do: "error"
  defp status_color(%SocialPublication{status: status}) when status in ~w(approved publishing), do: "in_progress"
  defp status_color(%SocialPublication{status: "cancelled"}), do: "disabled"
  defp status_color(_publication), do: "attention"

  defp preview(%SocialPublication{items: [first | rest]}) do
    text = if String.length(first["text"]) > 80, do: String.slice(first["text"], 0, 80) <> "…", else: first["text"]
    text = if text == "", do: gettext("(media only)"), else: text
    if rest == [], do: text, else: gettext("%{text} · %{count} posts", text: text, count: length(rest) + 1)
  end

  defp account_label(nil), do: gettext("Disconnected account")
  defp account_label(account), do: account.handle

  defp person(nil), do: "–"
  defp person(%{name: name}) when is_binary(name) and name != "", do: name
  defp person(%{email: email}), do: email

  defp media_label(nil), do: gettext("Missing media")
  defp media_label(media), do: "#{media.filename} (#{SocialMedia.kind(media)})"

  defp error_message(:needs_publish_scope),
    do: gettext("Reconnect this X account in Post performance so Atlas may publish and upload media for it.")

  defp error_message(:needs_authorization), do: gettext("This X account needs to be reconnected in Post performance.")
  defp error_message(:account_disconnected), do: gettext("This account is no longer connected.")

  defp error_message(:personal_account),
    do: gettext("Only the person who connected a personal account can approve its posts.")

  defp error_message(:stale_revision),
    do: gettext("The post changed since you opened it. Review it again before approving.")

  defp error_message(:not_approvable), do: gettext("This publication cannot be approved in its current state.")
  defp error_message(:not_editable), do: gettext("This publication already started publishing and cannot change.")
  defp error_message(:not_cancellable), do: gettext("This publication can no longer be cancelled.")
  defp error_message(:invalid_scheduled_at), do: gettext("Choose when to publish.")
  defp error_message(:forbidden), do: gettext("Publishing requires GTM write access.")

  defp error_message({:media_too_large, kind, max}),
    do: gettext("The %{kind} is empty or larger than %{max} MB.", kind: kind, max: div(max, 1_000_000))

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join("; ")
  end

  defp error_message(_reason), do: gettext("Something went wrong. Please try again.")
end
