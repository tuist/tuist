defmodule AtlasWeb.DocumentsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.PaginationComponents
  import Noora.Filter

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  @upload_accept ~w(.pdf .docx .xlsx .txt .md)
  @page_size 25
  @sortable_fields ~w(document_date inserted_at)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Documents"))
     |> assign(:query, "")
     |> assign(:available_filters, [])
     |> assign(:active_filters, [])
     |> assign(:sort_by, nil)
     |> assign(:sort_order, "desc")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign_library_counts()
     |> allow_upload(:document,
       accept: @upload_accept,
       max_entries: 1,
       max_file_size: 50_000_000,
       auto_upload: true,
       progress: &handle_upload_progress/3
     )}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    available_filters = define_filters()
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    query = Query.present_string(params["search"]) || ""
    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])

    offset =
      if query == "" do
        parse_offset(params["after"] || params["before"])
      else
        0
      end

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:available_filters, available_filters)
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> assign(:documents_offset, offset)
     |> load_documents(offset)}
  end

  def handle_upload_progress(:document, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          upload = %{path: path, client_name: entry.client_name, client_type: entry.client_type}

          case Documents.create_from_upload(socket.assigns.current_user, upload) do
            {:ok, document} -> {:ok, {:ok, document}}
            {:error, reason} -> {:ok, {:error, reason}}
          end
        end)

      socket =
        case result do
          {:ok, _document} ->
            socket
            |> put_flash(:info, gettext("Document uploaded. Atlas is processing its pages."))
            |> refresh_documents()

          {:error, reason} ->
            put_flash(socket, :error, gettext("Could not upload document: %{reason}", reason: inspect(reason)))
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # The upload form needs a phx-change handler for LiveView to wire up the file
  # input and start the auto_upload. Entry validation (accept, max size) is
  # declared in allow_upload/3, so there is nothing to do per change here.
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_document", _params, socket) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        upload = %{path: path, client_name: entry.client_name, client_type: entry.client_type}

        case Documents.create_from_upload(socket.assigns.current_user, upload) do
          {:ok, document} -> {:ok, {:ok, document}}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    socket =
      case results do
        [{:ok, _document} | _] ->
          socket
          |> put_flash(:info, gettext("Document uploaded. Atlas is processing its pages."))
          |> refresh_documents()

        [] ->
          socket

        [{:error, reason} | _] ->
          put_flash(socket, :error, gettext("Could not upload document: %{reason}", reason: inspect(reason)))
      end

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query = String.trim(query || "")

    query_string =
      socket.assigns.uri.query
      |> put_search_param(query)
      |> Query.drop("after")
      |> Query.drop("before")

    {:noreply, push_patch(socket, to: documents_path(query_string))}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> reset_pagination()
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/library/documents?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket, current_query_params(socket) |> reset_pagination())

    {:noreply,
     socket
     |> push_patch(to: ~p"/library/documents?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def render(assigns) do
    ~H"""
    <div id="documents">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Documents")}</h1>
          <p data-part="description">
            {gettext(
              "Executive document library with page-level text and meaning search and automated metadata extraction."
            )}
          </p>
          <div data-part="summary">
            <span id="documents-count" data-part="summary-item">
              {gettext("%{count} documents", count: @document_count)}
            </span>
            <span id="documents-type-count" data-part="summary-item">
              {gettext("%{count} types", count: @type_count)}
            </span>
            <span id="documents-correspondent-count" data-part="summary-item">
              {gettext("%{count} correspondents", count: @correspondent_count)}
            </span>
            <span id="documents-tag-count" data-part="summary-item">
              {gettext("%{count} tags", count: @tag_count)}
            </span>
          </div>
        </div>
        <div data-part="actions">
          <form id="documents-upload-form" phx-change="validate_upload" phx-submit="validate_upload">
            <label
              id="documents-add-file"
              class="noora-button"
              data-part="upload-button"
              data-variant="primary"
              data-size="medium"
            >
              <.live_file_input upload={@uploads.document} id="documents-file-input" />
              <span>{gettext("Add file")}</span>
            </label>
          </form>
        </div>
      </div>

      <.card title={gettext("Library")} icon="file" data-part="library-card">
        <.card_section data-part="library-section">
          <div data-part="filters">
            <.filter_dropdown
              id="documents-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <div data-part="search">
              <.form
                id="documents-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="documents-search-input"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search title, metadata, or page text")}
                  phx-debounce="300"
                />
              </.form>
            </div>
          </div>

          <div
            :if={@query != "" or @active_filters != []}
            id="documents-active-filters"
            data-part="active-filters"
          >
            <.active_filter :for={filter <- @active_filters} filter={filter} />
            <div :if={@query != ""} id="documents-search-filter" data-part="search-filter">
              <span data-part="label">{gettext("Search")}</span>
              <span data-part="label">{gettext("contains")}</span>
              <span data-part="badge">{@query}</span>
              <.link
                id="documents-clear-search"
                patch={clear_search_patch(assigns)}
                data-part="delete-icon"
              >
                <.close />
              </.link>
            </div>
          </div>

          <div
            :if={@uploads.document.entries != [] or upload_errors(@uploads.document) != []}
            id="documents-upload-status"
            data-part="upload-status"
          >
            <p :for={entry <- @uploads.document.entries} data-part="upload-entry">
              {entry.client_name}
            </p>
            <p :for={error <- upload_errors(@uploads.document)} data-part="upload-error">
              {upload_error(error)}
            </p>
          </div>

          <.table
            id="documents-table"
            rows={@document_rows}
            row_key={fn row -> "documents-table-row-#{row.document.id}" end}
            row_navigate={fn row -> ~p"/library/documents/#{row.document.id}" end}
          >
            <:col :let={row} label={gettext("Document")}>
              <.text_and_description_cell
                label={row.document.title}
                description={subtitle(row.document)}
              />
            </:col>
            <:col :let={row} :if={@query != ""} label={gettext("Match")}>
              <div data-part="match-cell">
                <div data-part="match-badges">
                  <.badge
                    :for={source <- row.match.sources}
                    label={match_source_label(source)}
                    color={match_source_color(source)}
                    style="light-fill"
                    size="small"
                  />
                </div>
                <p data-part="match-excerpt">
                  <%= for fragment <- highlight_fragments(match_excerpt(row, @query), @query) do %>
                    <mark :if={fragment.matched} data-part="highlight">{fragment.text}</mark>
                    <span :if={!fragment.matched}>{fragment.text}</span>
                  <% end %>
                </p>
              </div>
            </:col>
            <:col :let={row} label={gettext("Type")}>
              <.badge_cell
                label={type_label(row.document.document_type)}
                color={if(row.document.document_type, do: "information", else: "neutral")}
              />
            </:col>
            <:col :let={row} label={gettext("Correspondent")}>
              <.text_cell label={correspondent_label(row.document.correspondent)} />
            </:col>
            <:col :let={row} label={gettext("Account")}>
              <div data-part="account-cell">
                <.link
                  :if={row.document.account}
                  id={"documents-account-link-#{row.document.id}"}
                  data-part="account-link"
                  navigate={~p"/commercial/sales/accounts/#{row.document.account.id}"}
                >
                  {row.document.account.name}
                </.link>
                <span :if={is_nil(row.document.account)} data-part="muted">{"—"}</span>
              </div>
            </:col>
            <:col :let={row} label={gettext("Tags")}>
              <div data-part="tag-list">
                <.badge
                  :for={tag <- row.document.tags}
                  label={tag.name}
                  color={tag.color}
                  style="light-fill"
                  size="small"
                />
                <span :if={row.document.tags == []} data-part="muted">{"—"}</span>
              </div>
            </:col>
            <:col
              :let={row}
              label={gettext("Document date")}
              patch={column_patch_sort(assigns, "document_date")}
              sort_order={@sort_by == "document_date" && @sort_order}
            >
              <.text_cell label={format_date(row.document.document_date)} />
            </:col>
            <:col
              :let={row}
              label={gettext("Added")}
              patch={column_patch_sort(assigns, "inserted_at")}
              sort_order={@sort_by == "inserted_at" && @sort_order}
            >
              <.text_cell label={format_datetime(row.document.inserted_at)} />
            </:col>
            <:col :let={row} label={gettext("Status")}>
              <.badge_cell
                label={status_label(row.document.status)}
                color={status_color(row.document.status)}
              />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={empty_title(@query)}
                subtitle={empty_subtitle(@query)}
              />
            </:empty_state>
          </.table>

          <.pagination
            :if={@documents_meta.has_previous_page? or @documents_meta.has_next_page?}
            uri={@uri}
            has_previous_page={@documents_meta.has_previous_page?}
            has_next_page={@documents_meta.has_next_page?}
            start_cursor={@documents_meta.start_cursor}
            end_cursor={@documents_meta.end_cursor}
          />
        </.card_section>
      </.card>
    </div>
    """
  end

  defp status_label("uploaded"), do: gettext("Uploaded")
  defp status_label("processing"), do: gettext("Processing")
  defp status_label("ready"), do: gettext("Ready")
  defp status_label("failed"), do: gettext("Failed")
  defp status_label(status), do: status

  defp status_color("ready"), do: "success"
  defp status_color("failed"), do: "destructive"
  defp status_color("processing"), do: "attention"
  defp status_color(_status), do: "neutral"

  defp type_label(nil), do: gettext("Pending")
  defp type_label(%{name: name}), do: AtlasWeb.DocumentsLive.humanize(name)

  defp correspondent_label(nil), do: "—"
  defp correspondent_label(%{name: name}), do: name

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_datetime(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")

  @doc false
  def humanize(name) when is_binary(name) do
    name
    |> String.replace(~r/[_-]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Secondary label shown under a document's title. Prefers the curated Paperless
  title (for imported documents) over the raw source filename.
  """
  def subtitle(%{attributes: %{"paperless_title" => title}}) when is_binary(title) and title != "", do: title
  def subtitle(%{original_filename: filename}), do: filename

  defp refresh_documents(socket) do
    socket
    |> assign_library_counts()
    |> load_documents(socket.assigns[:documents_offset] || 0)
  end

  defp load_documents(socket, offset) do
    query = socket.assigns[:query] || ""

    list_opts =
      socket
      |> documents_list_opts()
      |> Keyword.put(:limit, @page_size)

    {document_rows, meta} =
      if query == "" do
        {documents, meta} =
          list_opts
          |> Keyword.put(:offset, offset)
          |> Documents.list_documents_page()

        {Enum.map(documents, &document_row/1), meta}
      else
        search_opts =
          list_opts
          |> Keyword.put(:query, nil)
          |> Keyword.put(:limit, @page_size)

        {:ok, rows} = Documents.search_document_matches(query, search_opts)

        {rows,
         %{
           total_count: length(rows),
           has_next_page?: false,
           has_previous_page?: false,
           start_cursor: "0",
           end_cursor: "0"
         }}
      end

    socket
    |> assign(:document_rows, document_rows)
    |> assign(:documents_meta, meta)
  end

  defp document_row(document), do: %{document: document, match: nil}

  defp parse_offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {offset, _rest} when offset > 0 -> offset
      _ -> 0
    end
  end

  defp parse_offset(_value), do: 0

  defp assign_library_counts(socket) do
    socket
    |> assign(:document_count, Documents.document_count())
    |> assign(:type_count, length(Documents.document_types()))
    |> assign(:correspondent_count, length(Documents.correspondents()))
    |> assign(:tag_count, length(Documents.tags()))
  end

  defp documents_list_opts(socket) do
    []
    |> put_active_filter(socket.assigns.active_filters, "account_id", :account_id, :exclude_account_id)
    |> put_active_filter(socket.assigns.active_filters, "document_type", :document_type, :exclude_document_type)
    |> put_active_filter(socket.assigns.active_filters, "correspondent", :correspondent, :exclude_correspondent)
    |> put_active_filter(socket.assigns.active_filters, "tag", :tag, :exclude_tag)
    |> put_active_filter(socket.assigns.active_filters, "status", :status, :exclude_status)
    |> put_sort(socket.assigns.sort_by, socket.assigns.sort_order)
  end

  defp put_active_filter(opts, active_filters, filter_id, include_key, exclude_key) do
    case Enum.find(active_filters, &(&1.id == filter_id)) do
      %{operator: :==, value: value} -> put_option(opts, include_key, Query.present_string(value))
      %{operator: :!=, value: value} -> put_option(opts, exclude_key, Query.present_string(value))
      _filter -> opts
    end
  end

  defp put_option(opts, _key, nil), do: opts
  defp put_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp put_sort(opts, nil, _sort_order), do: opts

  defp put_sort(opts, sort_by, sort_order),
    do: opts |> Keyword.put(:sort_by, sort_by) |> Keyword.put(:sort_order, sort_order)

  defp put_search_param(query_string, ""), do: Query.drop(query_string, "search")
  defp put_search_param(query_string, query), do: Query.put(query_string, "search", query)

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp reset_pagination(params) when is_map(params), do: Map.drop(params, ["after", "before"])

  defp column_patch_sort(%{uri: uri, sort_by: current_sort_by, sort_order: current_sort_order}, column) do
    next_order =
      case {current_sort_by == column, current_sort_order} do
        {true, "asc"} -> "desc"
        {true, _order} -> "asc"
        {false, _order} -> "desc"
      end

    query_params =
      uri.query
      |> Kernel.||("")
      |> URI.decode_query()
      |> Map.drop(["after", "before"])
      |> Map.put("sort-by", column)
      |> Map.put("sort-order", next_order)

    "?" <> URI.encode_query(query_params)
  end

  defp clear_search_patch(assigns) do
    query_params =
      assigns.uri.query
      |> Kernel.||("")
      |> URI.decode_query()
      |> Map.drop(["search", "after", "before"])

    ~p"/library/documents?#{query_params}"
  end

  defp normalize_sort_by(value) when value in @sortable_fields, do: value
  defp normalize_sort_by(_value), do: nil

  defp normalize_sort_order("asc"), do: "asc"
  defp normalize_sort_order(_value), do: "desc"

  defp define_filters do
    [
      named_option_filter("document_type", gettext("Type"), Documents.document_types(), &type_label/1),
      named_option_filter("correspondent", gettext("Correspondent"), Documents.correspondents(), & &1.name),
      named_option_filter("tag", gettext("Tag"), Documents.tags(), & &1.name),
      account_filter(),
      option_filter("status", gettext("Status"), Document.statuses(), &status_label/1)
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp named_option_filter(id, display_name, records, formatter) do
    options = Enum.map(records, & &1.name)

    option_filter(id, display_name, options, fn name ->
      record = Enum.find(records, &(&1.name == name))
      formatter.(record || %{name: name})
    end)
  end

  defp account_filter do
    accounts = Documents.document_accounts()

    %Filter.Filter{
      id: "account_id",
      field: :account_id,
      display_name: gettext("Account"),
      type: :option,
      searchable: true,
      options: Enum.map(accounts, & &1.id),
      options_display_names: Map.new(accounts, &{&1.id, &1.name}),
      operator: :==,
      value: nil
    }
  end

  defp option_filter(id, display_name, options, formatter) do
    options =
      options
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      searchable: true,
      options: options,
      options_display_names: Map.new(options, &{&1, formatter.(&1)}),
      operator: :==,
      value: nil
    }
  end

  defp documents_path(""), do: ~p"/library/documents"

  defp documents_path(query_string) do
    ~p"/library/documents"
    |> URI.parse()
    |> Map.put(:query, query_string)
    |> URI.to_string()
  end

  defp empty_title(""), do: gettext("No documents")
  defp empty_title(_query), do: gettext("No matches")

  defp empty_subtitle(""), do: gettext("Add a PDF or text file to start the document library.")
  defp empty_subtitle(_query), do: gettext("Try a different title, metadata value, or page phrase.")

  defp match_source_label(:metadata), do: gettext("Metadata")
  defp match_source_label(:page_text), do: gettext("Page text")
  defp match_source_label(:meaning), do: gettext("Meaning")

  defp match_source_color(:metadata), do: "neutral"
  defp match_source_color(:page_text), do: "information"
  defp match_source_color(:meaning), do: "attention"

  defp match_excerpt(%{match: %{excerpt: excerpt, page_number: page_number}}, query)
       when is_binary(excerpt) and excerpt != "" and is_integer(page_number) do
    gettext("Page %{page}: %{excerpt}", page: page_number, excerpt: contextual_excerpt(excerpt, query, 220))
  end

  defp match_excerpt(%{document: document}, query) do
    document
    |> metadata_match_value(query)
    |> case do
      nil -> subtitle(document)
      value -> shorten(value, 220)
    end
  end

  defp metadata_match_value(document, query) do
    query = String.downcase(query)

    document
    |> metadata_values()
    |> Enum.find(&metadata_value_matches?(&1, query))
  end

  defp metadata_values(document) do
    [
      document.title,
      document.original_filename,
      document.summary,
      document.document_type && type_label(document.document_type),
      document.correspondent && document.correspondent.name,
      document.account && document.account.name
    ] ++ Enum.map(document.tags, & &1.name)
  end

  defp metadata_value_matches?(nil, _query), do: false

  defp metadata_value_matches?(value, query) when is_binary(value) do
    value
    |> String.downcase()
    |> String.contains?(query)
  end

  defp highlight_fragments(text, query) do
    terms =
      query
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(String.length(&1) < 2))
      |> Enum.uniq_by(&String.downcase/1)

    if terms == [] do
      [%{text: text, matched: false}]
    else
      regex =
        terms
        |> Enum.map_join("|", &Regex.escape/1)
        |> then(&Regex.compile!("(#{&1})", "i"))

      regex
      |> Regex.split(text, include_captures: true, trim: false)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn fragment ->
        %{text: fragment, matched: Regex.match?(regex, fragment)}
      end)
    end
  end

  defp shorten(text, max_length) do
    text =
      text
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp contextual_excerpt(text, query, max_length) do
    text =
      text
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    terms =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(String.length(&1) < 2))
      |> Enum.uniq()

    match_index =
      text
      |> String.downcase()
      |> first_term_index(terms)

    case match_index do
      nil ->
        shorten(text, max_length)

      index ->
        start = max(index - div(max_length, 3), 0)
        excerpt = String.slice(text, start, max_length)
        prefix = if start > 0, do: "...", else: ""

        suffix =
          if start + String.length(excerpt) < String.length(text), do: "...", else: ""

        prefix <> excerpt <> suffix
    end
  end

  defp first_term_index(_text, []), do: nil

  defp first_term_index(text, terms) do
    terms
    |> Enum.map(fn term ->
      case String.split(text, term, parts: 2) do
        [before, _after] -> String.length(before)
        [_text] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp upload_error(:too_large), do: gettext("The file is too large.")
  defp upload_error(:not_accepted), do: gettext("Only PDF files are accepted.")
  defp upload_error(error), do: inspect(error)
end
