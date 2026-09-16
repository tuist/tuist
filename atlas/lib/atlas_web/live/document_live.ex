defmodule AtlasWeb.DocumentLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias AtlasWeb.DocumentLinks

  def mount(%{"id" => id}, _session, socket) do
    case Documents.get_document(id) do
      %Document{} = document ->
        {:ok,
         socket
         |> assign(:page_title, document.title)
         |> assign(:document, document)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Document not found."))
         |> push_navigate(to: ~p"/documents")}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="document">
      <div data-part="header">
        <div data-part="text">
          <.breadcrumbs data-part="breadcrumbs">
            <.breadcrumb
              id="document-breadcrumb-documents"
              label={gettext("Documents")}
              phx-click={JS.navigate(~p"/documents")}
            />
            <.breadcrumb id="document-breadcrumb-current" label={@document.title} />
          </.breadcrumbs>
          <h1 data-part="title">{@document.title}</h1>
          <p data-part="subtitle">{AtlasWeb.DocumentsLive.subtitle(@document)}</p>
        </div>
        <div data-part="actions">
          <.button
            :if={@document.account}
            id="document-view-account-button"
            label={gettext("View account")}
            variant="secondary"
            size="medium"
            navigate={~p"/sales/accounts/#{@document.account.id}"}
          >
            <:icon_left>
              <.icon name="user" />
            </:icon_left>
          </.button>
          <.button
            label={gettext("Open document")}
            variant="primary"
            size="medium"
            href={DocumentLinks.download_path(@document)}
            target="_blank"
          />
        </div>
      </div>

      <.card title={gettext("Details")} icon="file" data-part="details-card">
        <.card_section data-part="details-section">
          <dl data-part="details">
            <div data-part="detail">
              <dt>{gettext("Type")}</dt>
              <dd>
                <.badge
                  :if={@document.document_type}
                  label={AtlasWeb.DocumentsLive.humanize(@document.document_type.name)}
                  color="information"
                  style="light-fill"
                />
                <span :if={is_nil(@document.document_type)} data-part="muted">{"—"}</span>
              </dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Correspondent")}</dt>
              <dd>{value_or_dash(@document.correspondent && @document.correspondent.name)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Account")}</dt>
              <dd>
                <.link
                  :if={@document.account}
                  id="document-account-link"
                  data-part="account-link"
                  navigate={~p"/sales/accounts/#{@document.account.id}"}
                >
                  {@document.account.name}
                </.link>
                <span :if={is_nil(@document.account)} data-part="muted">{"—"}</span>
              </dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Date")}</dt>
              <dd>{format_date(@document.document_date)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Archive serial number")}</dt>
              <dd>{value_or_dash(@document.archive_serial_number)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Status")}</dt>
              <dd>
                <.badge label={status_label(@document.status)} color={status_color(@document.status)} />
              </dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Tags")}</dt>
              <dd>
                <div data-part="tag-list">
                  <.badge
                    :for={tag <- @document.tags}
                    label={tag.name}
                    color={tag.color}
                    style="light-fill"
                    size="small"
                  />
                  <span :if={@document.tags == []} data-part="muted">{"—"}</span>
                </div>
              </dd>
            </div>
          </dl>
        </.card_section>
      </.card>

      <.card
        :if={@document.summary}
        title={gettext("Summary")}
        icon="file_text"
        data-part="summary-card"
      >
        <.card_section>
          <p data-part="summary">{@document.summary}</p>
        </.card_section>
      </.card>

      <.card title={gettext("Content")} icon="file_text" data-part="content-card">
        <.card_section data-part="content-section">
          <article
            :for={page <- @document.pages}
            id={"document-page-#{page.page_number}"}
            data-part="page"
          >
            <header data-part="page-header">{gettext("Page %{page}", page: page.page_number)}</header>
            <pre data-part="page-content">{page.content}</pre>
          </article>
          <p :if={@document.pages == []} data-part="muted">
            {gettext("No extracted page text yet.")}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp value_or_dash(nil), do: "—"
  defp value_or_dash(value), do: to_string(value)

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  defp status_label("uploaded"), do: gettext("Uploaded")
  defp status_label("processing"), do: gettext("Processing")
  defp status_label("ready"), do: gettext("Ready")
  defp status_label("failed"), do: gettext("Failed")
  defp status_label(status), do: status

  defp status_color("ready"), do: "success"
  defp status_color("failed"), do: "destructive"
  defp status_color("processing"), do: "attention"
  defp status_color(_status), do: "neutral"
end
