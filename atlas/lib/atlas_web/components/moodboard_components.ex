defmodule AtlasWeb.MoodboardComponents do
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Moodboard
  alias Phoenix.HTML.Form

  def kind_label("article"), do: gettext("Article")
  def kind_label("image"), do: gettext("Image")
  def kind_label("video"), do: gettext("Video")
  def kind_label("text"), do: gettext("Text")
  def kind_label(_kind), do: gettext("Link")

  def resource_form(resource), do: resource |> Moodboard.change_resource() |> resource_form(resource.tags)

  def resource_form(%Ecto.Changeset{} = changeset, tags) do
    form = to_form(changeset, as: :resource)
    %{form | params: Map.put(form.params, "tags", Enum.join(tags || [], ", "))}
  end

  attr :status, :string, required: true

  def preview_status(assigns) do
    {label, status} =
      case assigns.status do
        "pending" -> {gettext("Finding a preview…"), "in_progress"}
        "ready" -> {gettext("Preview ready"), "success"}
        _ -> {gettext("Preview unavailable"), "disabled"}
      end

    assigns = assign(assigns, label: label, badge_status: status)

    ~H"""
    <.status_badge label={@label} status={@badge_status} type="dot" />
    """
  end

  attr :form, Form, required: true
  attr :editing, :boolean, default: false
  slot :trigger, required: true

  def resource_modal(assigns) do
    ~H"""
    <.modal
      id="moodboard-resource-modal"
      title={if @editing, do: gettext("Edit resource"), else: gettext("Add resource")}
      description={gettext("Save a link, an excerpt, or an idea. Add your own context.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_resource_modal"
      on_open_change="resource_modal_changed"
      data-part="moodboard-modal"
    >
      <:header_icon><.photo /></:header_icon>
      <:trigger :let={attrs}>{render_slot(@trigger, attrs)}</:trigger>
      <div data-part="resource-modal-content">
        <.form id="moodboard-resource-form" for={@form} phx-submit="save" data-part="resource-form">
          <.text_input
            id="resource-title"
            field={@form[:title]}
            label={gettext("Title")}
            required
            show_required
            show_suffix={false}
          />
          <.text_input
            id="resource-url"
            field={@form[:url]}
            label={gettext("Link (optional for text)")}
            hint={
              gettext("Images, videos, and article text are discovered automatically after saving.")
            }
            input_type="url"
            placeholder="https://..."
            show_suffix={false}
          />
          <.text_area
            id="resource-description"
            field={@form[:description]}
            label={gettext("Why it's worth saving")}
            max_length={2000}
          />
          <.text_area
            id="resource-content"
            field={@form[:content]}
            label={gettext("Text or excerpt (optional)")}
            hint={gettext("Add original text or a quote. Required when there is no link.")}
            max_length={20_000}
            rows={5}
          />
          <.text_input
            id="resource-image-url"
            field={@form[:image_url]}
            label={gettext("Preview image override (optional)")}
            input_type="url"
            placeholder="https://..."
            show_suffix={false}
          />
          <.text_input
            id="resource-tags"
            field={@form[:tags]}
            label={gettext("Tags (comma-separated)")}
            placeholder="typography, websites, tools"
            show_suffix={false}
          />
        </.form>
      </div>
      <:footer>
        <.modal_footer>
          <:action :if={@editing}>
            <.button
              id="moodboard-delete"
              label={gettext("Remove resource")}
              variant="destructive"
              size="small"
              phx-click="delete"
              data-confirm={gettext("Remove this resource and its discussion from Moodboard?")}
            />
          </:action>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              size="small"
              phx-click="close_resource_modal"
            />
          </:action>
          <:action>
            <.button
              id="moodboard-save"
              label={gettext("Save resource")}
              size="small"
              type="submit"
              form="moodboard-resource-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end
end
