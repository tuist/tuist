defmodule Atlas.Documents do
  @moduledoc """
  Executive-only document library with S3 storage and page-level semantic search.

  Documents carry Paperless-style normalized metadata: a correspondent, a
  document type, colored tags, a document date, and an archive serial number.
  Those entities are inferred by the classifier during ingest and find-or-created
  here so the library populates itself.

  Page embeddings are stored in the in-cluster OpenData Vector service via
  `Atlas.Vector`, keyed by `"document_page:<page_id>"`. Postgres remains the
  source of truth for document metadata and page text; the vector service only
  holds the embeddings used for nearest-neighbor search.
  """

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Workers.ExtractDocumentServiceLevels
  alias Atlas.Audit
  alias Atlas.Documents.Agents.DocumentClassifierAgent
  alias Atlas.Documents.Correspondent
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Documents.DocumentType
  alias Atlas.Documents.Embedding
  alias Atlas.Documents.Storage
  alias Atlas.Documents.Tag
  alias Atlas.Documents.TextExtractor
  alias Atlas.Documents.Workers.ProcessDocument
  alias Atlas.Finance
  alias Atlas.Finance.Agents.InvoiceExtractorAgent
  alias Atlas.LLMs.Errors, as: LLMErrors
  alias Atlas.Repo
  alias Atlas.Users.User
  alias Atlas.Vector

  require Logger

  @vector_source_type "document_page"

  @default_limit 25
  @default_document_pages_limit 10
  @default_classification_candidate_limit 100
  @search_vector_timeout 1_000
  @search_embedding_receive_timeout 1_000
  @search_vector_receive_timeout 1_000
  @match_source_order [:metadata, :page_text, :meaning]
  @classification_attribute_key "classification"
  @sortable_document_fields ~w(document_date inserted_at)
  @month_numbers %{
    "january" => 1,
    "february" => 2,
    "march" => 3,
    "april" => 4,
    "may" => 5,
    "june" => 6,
    "july" => 7,
    "august" => 8,
    "september" => 9,
    "october" => 10,
    "november" => 11,
    "december" => 12
  }

  def list_documents(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    opts
    |> documents_query()
    |> limit(^limit)
    |> preload([:account, :uploaded_by, :correspondent, :document_type, :tags])
    |> Repo.all()
  end

  @doc """
  Lists one page of the library, newest first, with the same filters as
  `list_documents/1`. Offset pagination is delegated to Flop; pass `:offset` to
  load a later page and `:limit` to size it. Returns `{documents, meta}` where
  `meta` carries `:total_count` plus cursor fields compatible with
  `AtlasWeb.PaginationComponents.pagination/1`.
  """
  def list_documents_page(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    query =
      opts
      |> documents_query()
      |> preload([:account, :uploaded_by, :correspondent, :document_type, :tags])

    {documents, flop_meta} = Flop.run(query, %Flop{limit: limit, offset: offset}, for: Document)

    meta = %{
      total_count: flop_meta.total_count,
      has_next_page?: flop_meta.has_next_page?,
      has_previous_page?: flop_meta.has_previous_page?,
      start_cursor: Integer.to_string(flop_meta.previous_offset || 0),
      end_cursor: Integer.to_string(flop_meta.next_offset || offset + limit)
    }

    {documents, meta}
  end

  @doc """
  Counts documents in the library without applying list filters.
  """
  def document_count do
    Repo.aggregate(Document, :count, :id)
  end

  defp documents_query(opts) do
    Document
    |> maybe_filter_query(Keyword.get(opts, :query))
    |> maybe_filter(:account_id, Keyword.get(opts, :account_id))
    |> maybe_exclude(:account_id, Keyword.get(opts, :exclude_account_id))
    |> maybe_filter_by_named(:document_type, Keyword.get(opts, :document_type))
    |> maybe_exclude_by_named(:document_type, Keyword.get(opts, :exclude_document_type))
    |> maybe_filter_by_named(:correspondent, Keyword.get(opts, :correspondent))
    |> maybe_exclude_by_named(:correspondent, Keyword.get(opts, :exclude_correspondent))
    |> maybe_filter_by_named(:tag, Keyword.get(opts, :tag))
    |> maybe_exclude_by_named(:tag, Keyword.get(opts, :exclude_tag))
    |> maybe_filter(:status, Keyword.get(opts, :status))
    |> maybe_exclude(:status, Keyword.get(opts, :exclude_status))
    |> order_documents(Keyword.get(opts, :sort_by), Keyword.get(opts, :sort_order))
  end

  def get_document(id, opts \\ []) when is_binary(id) do
    id
    |> get_document_record()
    |> preload_document(Keyword.get(opts, :pages, :all))
  end

  def list_document_pages_page(%Document{id: document_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_document_pages_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    query =
      from(page in DocumentPage,
        where: page.document_id == ^document_id,
        order_by: [asc: page.page_number]
      )

    Flop.run(query, %Flop{limit: limit, offset: offset}, for: DocumentPage)
  end

  defp get_document_record(id), do: Repo.get(Document, id)

  defp preload_document(nil, _pages), do: nil

  defp preload_document(%Document{} = document, false) do
    Repo.preload(document, [:account, :uploaded_by, :correspondent, :document_type, :tags])
  end

  defp preload_document(%Document{} = document, _pages) do
    Repo.preload(document, [
      :account,
      :uploaded_by,
      :correspondent,
      :document_type,
      :tags,
      pages: pages_query()
    ])
  end

  defp pages_query, do: from(page in DocumentPage, order_by: [asc: page.page_number])

  @doc """
  Returns true when a document imported from Paperless with the given Paperless
  id already exists. Lets the Paperless importer skip duplicates on re-runs.
  """
  def imported_from_paperless?(paperless_id) do
    id = to_string(paperless_id)
    Repo.exists?(from document in Document, where: fragment("?->>'paperless_id' = ?", document.attributes, ^id))
  end

  def imported_from_qonto_attachment?(attachment_id) do
    id = to_string(attachment_id)
    Repo.exists?(from document in Document, where: fragment("?->>'qonto_attachment_id' = ?", document.attributes, ^id))
  end

  def imported_file_checksum?(checksum) when is_binary(checksum) and checksum != "" do
    Repo.exists?(from document in Document, where: document.checksum_sha256 == ^checksum)
  end

  def imported_file_checksum?(_checksum), do: false

  @doc """
  Lists documents associated with an account, newest first.
  """
  def list_account_documents(account, opts \\ [])

  def list_account_documents(%Account{id: account_id}, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    Document
    |> where([document], document.account_id == ^account_id)
    |> order_by([document], desc: document.document_date, desc: document.inserted_at, desc: document.id)
    |> limit(^limit)
    |> preload([:document_type, :correspondent, :tags])
    |> Repo.all()
  end

  def list_account_documents(account_id, opts) when is_binary(account_id) do
    list_account_documents(%Account{id: account_id}, opts)
  end

  def create_from_path(path, attrs, opts \\ []) when is_binary(path) and is_map(attrs) do
    with {:ok, body} <- File.read(path) do
      create_from_binary(body, attrs, opts)
    end
  end

  def create_from_binary(body, attrs, opts \\ []) when is_binary(body) and is_map(attrs) do
    with {:ok, object} <- store_file(body, attrs),
         {:ok, document} <- insert_document(attrs, object, byte_size(body)),
         :ok <- maybe_enqueue_processing(document, opts) do
      audit_document(
        "document.uploaded",
        document,
        %{
          "source" => document.source,
          "original_filename" => document.original_filename,
          "content_type" => document.content_type,
          "account_id" => document.account_id
        },
        actor: Keyword.get(opts, :audit_actor)
      )

      {:ok, document}
    end
  end

  @default_upload_ttl 3_600
  # Matches the interactive upload cap in `AtlasWeb.DocumentsLive`. Presigned
  # PUT URLs cannot bind Content-Length, so this is enforced server-side when
  # finalize downloads the object.
  @max_document_bytes 50 * 1024 * 1024

  @doc """
  Reserves a document row in `pending_upload` state and returns a short-lived,
  signed URL the caller can `PUT` the bytes to directly. `content_type` and
  `original_filename` are bound at reservation time so a rogue client cannot
  swap the payload out from under the row. Call `finalize_pending_upload/1`
  after the PUT succeeds to promote the row to `uploaded` and enqueue
  processing. Rows whose `upload_expires_at` passes are swept by
  `Atlas.Documents.Workers.ExpirePendingUploads`.
  """
  def create_pending_upload(attrs, opts \\ []) when is_map(attrs) do
    attrs = stringify_keys(attrs)
    ttl = Keyword.get(opts, :expires_in, @default_upload_ttl)

    with :ok <- validate_pending_upload_attrs(attrs) do
      filename = attrs["original_filename"]
      content_type = attrs["content_type"]
      key = pending_object_key(filename)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      expires_at = DateTime.add(now, ttl, :second)

      document_attrs =
        Map.merge(attrs, %{
          "title" => attrs["title"] || title_from_filename(filename),
          "storage_bucket" => Storage.bucket(),
          "storage_key" => key,
          "source" => attrs["source"] || "upload",
          "status" => "pending_upload",
          "upload_expires_at" => expires_at
        })

      changeset =
        %Document{}
        |> Document.changeset(document_attrs)
        |> Ecto.Changeset.put_change(:uploaded_by_id, document_attrs["uploaded_by_id"])
        |> Ecto.Changeset.put_change(:account_id, document_attrs["account_id"])

      with {:ok, document} <- Repo.insert(changeset),
           {:ok, upload_url} <- Storage.presigned_put_url(key, expires_in: ttl, content_type: content_type) do
        audit_document(
          "document.upload_reserved",
          document,
          %{
            "content_type" => document.content_type,
            "original_filename" => document.original_filename,
            "account_id" => document.account_id
          },
          actor: Keyword.get(opts, :audit_actor)
        )

        {:ok,
         %{
           document: document,
           upload_url: upload_url,
           upload_expires_at: expires_at,
           required_headers: %{"Content-Type" => content_type}
         }}
      end
    end
  end

  @doc """
  Verifies that the client PUT the bytes to storage, records their size and
  sha256 checksum, flips the row to `uploaded`, and enqueues text extraction.
  Fire-and-forget: returns as soon as the job is enqueued.

  The `pending_upload` -> `uploaded` transition is claimed with a conditional
  `update_all` so two concurrent callers cannot both promote the row and
  enqueue duplicate processing jobs. Presigned PUT URLs cannot bind
  Content-Length, so the download is rejected here when the client uploaded
  more than the configured document cap.
  """
  def finalize_pending_upload(document_id, opts \\ []) when is_binary(document_id) do
    case Repo.get(Document, document_id) do
      nil -> {:error, :document_not_found}
      %Document{status: "pending_upload"} = document -> finalize_pending_document(document, opts)
      %Document{status: status} -> {:error, {:unexpected_status, status}}
    end
  end

  defp finalize_pending_document(%Document{} = document, opts) do
    with :ok <- verify_uploaded_size(document.storage_key),
         {:ok, %{body: body}} <- Storage.get_object(document.storage_key),
         :ok <- enforce_document_size(document, byte_size(body)),
         :ok <- run_body_verifier(Keyword.get(opts, :verify_body), body),
         checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower),
         {:ok, updated} <- claim_pending_upload(document, byte_size(body), checksum),
         :ok <- maybe_enqueue_processing(updated, opts) do
      audit_document(
        "document.uploaded",
        updated,
        %{
          "source" => updated.source,
          "original_filename" => updated.original_filename,
          "content_type" => updated.content_type,
          "account_id" => updated.account_id
        },
        actor: Keyword.get(opts, :audit_actor)
      )

      {:ok, updated}
    end
  end

  # HEAD first when the backend supports it so we can reject an oversized
  # upload without downloading it. Backends that do not implement HEAD (or
  # cannot report Content-Length) fall through to the download-time check.
  defp verify_uploaded_size(storage_key) do
    case Storage.head_object(storage_key) do
      {:ok, response} ->
        case content_length(response) do
          size when is_integer(size) and size > @max_document_bytes -> reject_oversized(storage_key, size)
          _size -> :ok
        end

      {:error, :not_supported} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enforce_document_size(_document, byte_size) when byte_size <= @max_document_bytes, do: :ok

  defp enforce_document_size(document, byte_size) do
    reject_oversized(document.storage_key, byte_size)
  end

  # Optional finalize hook: callers pass a `verify_body` function that inspects
  # the raw bytes (already downloaded for size/checksum) before the row is
  # promoted, so an upload that satisfies the presigned Content-Type but fails
  # a content-shape check cannot advance downstream state.
  defp run_body_verifier(nil, _body), do: :ok
  defp run_body_verifier(fun, body) when is_function(fun, 1), do: fun.(body)

  defp reject_oversized(storage_key, byte_size) do
    _ = Storage.delete_object(storage_key)
    {:error, {:upload_too_large, byte_size, @max_document_bytes}}
  end

  defp content_length(%{headers: headers}) when is_list(headers) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(name) ->
        if String.downcase(name) == "content-length", do: parse_integer(value)

      _other ->
        nil
    end)
  end

  defp content_length(_response), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_value), do: nil

  # Conditional update: only one caller can flip a row out of `pending_upload`.
  # The loser gets 0 rows back, is treated as a lost race, and returns without
  # enqueuing a duplicate processing job. A follow-up `Repo.get!` returns the
  # fresh struct; the atomic transition already happened.
  defp claim_pending_upload(%Document{id: id}, byte_size, checksum) do
    query =
      from(document in Document,
        where: document.id == ^id,
        where: document.status == "pending_upload"
      )

    case Repo.update_all(query,
           set: [
             status: "uploaded",
             byte_size: byte_size,
             checksum_sha256: checksum,
             upload_expires_at: nil,
             updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
           ]
         ) do
      {1, _rows} -> {:ok, Repo.get!(Document, id)}
      {0, _rows} -> {:error, :already_finalized}
    end
  end

  @doc """
  Deletes pending-upload rows past their `upload_expires_at`, best-effort
  deleting the reserved object as well so nothing lingers in storage. Returns
  the number of rows deleted.
  """
  def delete_expired_pending_uploads(now \\ DateTime.utc_now()) do
    expired =
      Repo.all(
        from document in Document,
          where: document.status == "pending_upload",
          where: not is_nil(document.upload_expires_at),
          where: document.upload_expires_at <= ^now
      )

    Enum.each(expired, fn document ->
      _ = Storage.delete_object(document.storage_key)

      case Repo.delete(document) do
        {:ok, _document} ->
          audit_document("document.upload_expired", document, %{
            "original_filename" => document.original_filename,
            "content_type" => document.content_type
          })

        {:error, reason} ->
          Logger.warning("Could not delete expired pending document #{document.id}: #{inspect(reason)}")
      end
    end)

    length(expired)
  end

  defp validate_pending_upload_attrs(attrs) do
    cond do
      not is_binary(attrs["original_filename"]) or attrs["original_filename"] == "" ->
        {:error, :original_filename_required}

      not is_binary(attrs["content_type"]) or attrs["content_type"] == "" ->
        {:error, :content_type_required}

      true ->
        :ok
    end
  end

  defp pending_object_key(filename) do
    extension = filename |> Path.extname() |> String.downcase()
    "documents/pending/#{Ecto.UUID.generate()}#{extension}"
  end

  def create_from_upload(%User{} = user, %{path: path, client_name: filename} = upload, opts \\ []) do
    content_type = Map.get(upload, :client_type) || "application/octet-stream"
    opts = Keyword.put_new(opts, :audit_actor, user)

    create_from_path(
      path,
      %{
        "uploaded_by_id" => user.id,
        "original_filename" => filename,
        "content_type" => content_type,
        "source" => Keyword.get(opts, :source, "upload")
      },
      opts
    )
  end

  @doc """
  Re-enqueues `ProcessDocument` for every document currently in `failed`.
  Intended as a one-shot backfill after a processing bug is fixed; only
  `failed` rows are touched because they cannot have an in-flight Oban job.
  """
  def reenqueue_failed_documents do
    ids =
      Document
      |> where([document], document.status == "failed")
      |> select([document], document.id)
      |> Repo.all()

    Enum.each(ids, fn id ->
      %{document_id: id}
      |> ProcessDocument.new()
      |> Oban.insert()
    end)

    %{enqueued: length(ids)}
  end

  def process_document(document_id, opts \\ []) when is_binary(document_id) do
    with %Document{} = document <- Repo.get(Document, document_id),
         {:ok, document} <- mark_processing(document),
         {:ok, %{body: body}} <- Storage.get_object(document.storage_key),
         {:ok, path} <- write_temp(document.original_filename, body),
         {:ok, pages} <- TextExtractor.extract_pages(path, document.content_type, document.original_filename),
         {:ok, metadata} <- classify_with_fallback(document, pages, opts),
         {:ok, document} <- finalize_document(document, pages, metadata, opts) do
      audit_document("document.processed", document, %{
        "pages_count" => length(pages),
        "account_id" => document.account_id
      })

      {:ok, document}
    else
      nil -> {:error, :document_not_found}
      {:error, reason} = error -> mark_failed(document_id, reason) && error
    end
  end

  def semantic_search(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 10)

    case String.trim(query) do
      "" -> {:ok, []}
      trimmed -> {:ok, hybrid_search(trimmed, opts, limit)}
    end
  end

  def search_document_matches(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_limit)

    case String.trim(query) do
      "" -> {:ok, []}
      trimmed -> {:ok, document_matches(trimmed, opts, limit)}
    end
  end

  # Hybrid retrieval: fuse Postgres full-text ranking (lexical) with vector
  # nearest-neighbor results (semantic) using reciprocal rank fusion. Each
  # source is best-effort: an unconfigured or failing vector service simply
  # leaves the full-text results, and vice versa. Built-in full-text search is
  # used so no Postgres extension is required.
  @rrf_k 60

  defp hybrid_search(query, opts, limit) do
    candidate_pool = limit * 3
    vector_task = Task.async(fn -> vector_candidates(query, opts, candidate_pool) end)
    fulltext_results = fulltext_candidates(query, opts, candidate_pool)

    ranked_lists = [
      {:meaning, await_vector_candidates(vector_task, Keyword.get(opts, :vector_timeout, @search_vector_timeout))},
      {:page_text, fulltext_results}
    ]

    ranked_lists
    |> fuse_ranked_lists(limit)
    |> Enum.map(fn {page_id, %{score: score, sources: sources}} ->
      %{page_id: page_id, score: score, match_sources: order_match_sources(sources)}
    end)
    |> hydrate_hits(opts)
  end

  defp vector_candidates(query, opts, limit) do
    if Vector.configured?() do
      with {:ok, %{embedding: embedding}} <- Embedding.embed(query, search_embedding_opts(opts)),
           {:ok, body} <-
             Vector.search(embedding,
               k: limit,
               receive_timeout: Keyword.get(opts, :vector_receive_timeout, @search_vector_receive_timeout),
               filter: %{"eq" => %{"field" => "source_type", "value" => @vector_source_type}}
             ) do
        body |> extract_hits() |> Enum.map(&{&1.page_id, &1.score})
      else
        _ -> []
      end
    else
      []
    end
  end

  defp await_vector_candidates(task, timeout) do
    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, results} when is_list(results) -> results
      _result -> []
    end
  end

  defp search_embedding_opts(opts) do
    Keyword.put_new(opts, :receive_timeout, @search_embedding_receive_timeout)
  end

  defp fulltext_candidates(query, opts, limit) do
    DocumentPage
    |> join(:inner, [page], document in assoc(page, :document), as: :document)
    |> maybe_filter_document_page(opts)
    |> where([page], fragment("to_tsvector('english', ?) @@ websearch_to_tsquery('english', ?)", page.content, ^query))
    |> order_by([page],
      desc:
        fragment(
          "ts_rank(to_tsvector('english', ?), websearch_to_tsquery('english', ?))",
          page.content,
          ^query
        )
    )
    |> limit(^limit)
    |> select([page], {
      page.id,
      fragment(
        "ts_rank(to_tsvector('english', ?), websearch_to_tsquery('english', ?))",
        page.content,
        ^query
      )
    })
    |> Repo.all()
  end

  defp document_matches(query, opts, limit) do
    candidate_pool = limit * 3
    {:ok, page_hits} = semantic_search(query, Keyword.put(opts, :limit, candidate_pool))

    metadata_document_ids = metadata_document_candidates(query, opts, candidate_pool)

    page_ranked_documents =
      page_hits
      |> Enum.uniq_by(& &1.document_id)
      |> Enum.map(&{&1.document_id, &1.score})

    metadata_ranked_documents = Enum.map(metadata_document_ids, &{&1, 1.0})

    ranked_matches =
      [
        {:content, page_ranked_documents},
        {:metadata, metadata_ranked_documents}
      ]
      |> fuse_ranked_lists(candidate_pool)

    page_hits_by_document =
      page_hits
      |> Enum.group_by(& &1.document_id)
      |> Map.new(fn {document_id, hits} ->
        {document_id, Enum.max_by(hits, & &1.score)}
      end)

    metadata_document_ids = MapSet.new(metadata_document_ids)
    documents_by_id = documents_by_ids(Enum.map(ranked_matches, &elem(&1, 0)))

    ranked_matches
    |> Enum.map(fn {document_id, %{score: score}} ->
      document = Map.get(documents_by_id, document_id)
      page_hit = Map.get(page_hits_by_document, document_id)

      sources =
        []
        |> maybe_add_source(MapSet.member?(metadata_document_ids, document_id), :metadata)
        |> Kernel.++(if page_hit, do: page_hit.match_sources, else: [])
        |> order_match_sources()

      if document do
        %{
          document: document,
          match: %{
            score: score,
            sources: sources,
            page_number: page_hit && page_hit.page_number,
            excerpt: page_hit && page_hit.excerpt
          }
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> sort_document_match_rows(opts)
    |> Enum.take(limit)
  end

  defp metadata_document_candidates(query, opts, limit) do
    pattern = "%#{query}%"

    Document
    |> join(:left, [document], document_type in assoc(document, :document_type))
    |> join(:left, [document, _document_type], correspondent in assoc(document, :correspondent))
    |> join(:left, [document, _document_type, _correspondent], account in assoc(document, :account))
    |> join(:left, [document, _document_type, _correspondent, _account], tag in assoc(document, :tags))
    |> maybe_filter_metadata_documents(opts)
    |> where(
      [document, document_type, correspondent, account, tag],
      ilike(document.title, ^pattern) or ilike(document.original_filename, ^pattern) or
        ilike(document.summary, ^pattern) or ilike(document_type.name, ^pattern) or
        ilike(correspondent.name, ^pattern) or ilike(account.name, ^pattern) or
        ilike(tag.name, ^pattern)
    )
    |> group_by([document], [document.id, document.inserted_at])
    |> order_by([document], desc: document.inserted_at, desc: document.id)
    |> limit(^limit)
    |> select([document], document.id)
    |> Repo.all()
  end

  defp documents_by_ids([]), do: %{}

  defp documents_by_ids(ids) do
    Document
    |> where([document], document.id in ^ids)
    |> preload([:account, :uploaded_by, :correspondent, :document_type, :tags])
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # Reciprocal rank fusion: each result's contribution from a list is
  # 1 / (k + rank). Summing contributions across lists rewards records that rank
  # well in any retrieval mode without needing comparable raw scores.
  defp fuse_ranked_lists(ranked_lists, limit) do
    ranked_lists
    |> Enum.flat_map(fn {source, list} ->
      list
      |> Enum.with_index(1)
      |> Enum.map(fn {{id, _score}, rank} -> {id, 1.0 / (@rrf_k + rank), source} end)
    end)
    |> Enum.group_by(&elem(&1, 0), fn {_id, score, source} -> {score, source} end)
    |> Enum.map(fn {id, contributions} ->
      score = contributions |> Enum.map(&elem(&1, 0)) |> Enum.sum()
      sources = contributions |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      {id, %{score: score, sources: sources}}
    end)
    |> Enum.sort_by(fn {_id, %{score: score}} -> score end, :desc)
    |> Enum.take(limit)
  end

  defp maybe_add_source(sources, true, source), do: [source | sources]
  defp maybe_add_source(sources, false, _source), do: sources

  defp order_match_sources(sources) do
    Enum.filter(@match_source_order, &(&1 in sources))
  end

  defp extract_hits(%{"results" => results}) when is_list(results) do
    results
    |> Enum.map(&parse_hit/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_hits(_body), do: []

  defp parse_hit(%{"id" => @vector_source_type <> ":" <> page_id} = result) do
    parse_page_hit(page_id, result)
  end

  defp parse_hit(%{"vector" => %{"id" => @vector_source_type <> ":" <> page_id}} = result) do
    parse_page_hit(page_id, result)
  end

  defp parse_hit(_result), do: nil

  defp parse_page_hit(page_id, result) do
    %{page_id: page_id, score: result["score"] || result["distance"]}
  end

  defp hydrate_hits([], _opts), do: []

  defp hydrate_hits(hits, opts) do
    page_ids = Enum.map(hits, & &1.page_id)

    pages =
      DocumentPage
      |> where([page], page.id in ^page_ids)
      |> join(:inner, [page], document in assoc(page, :document), as: :document)
      |> maybe_filter_document_page(opts)
      |> preload([_page, document], document: {document, [:document_type, :correspondent, :account]})
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    hits
    |> Enum.map(fn hit -> hydrate_hit(Map.get(pages, hit.page_id), hit) end)
    |> Enum.reject(&is_nil/1)
  end

  defp hydrate_hit(nil, _hit), do: nil

  defp hydrate_hit(%DocumentPage{document: document} = page, hit) do
    %{
      id: page.id,
      document_id: page.document_id,
      page_number: page.page_number,
      excerpt: String.slice(page.content, 0, 1_000),
      title: document.title,
      document_type: document.document_type && document.document_type.name,
      correspondent: document.correspondent && document.correspondent.name,
      account_id: document.account_id,
      account_name: document.account && document.account.name,
      summary: document.summary,
      score: hit.score,
      match_sources: hit.match_sources
    }
  end

  @doc "Lists document types ordered by name."
  def document_types do
    Repo.all(from type in DocumentType, order_by: type.name)
  end

  @doc "Lists correspondents ordered by name."
  def correspondents do
    Repo.all(from correspondent in Correspondent, order_by: correspondent.name)
  end

  @doc "Lists tags ordered by name."
  def tags do
    Repo.all(from tag in Tag, order_by: tag.name)
  end

  @doc "Lists accounts with at least one document ordered by name."
  def document_accounts do
    Repo.all(
      from account in Account,
        join: document in assoc(account, :documents),
        where: is_nil(account.not_an_account_at),
        group_by: account.id,
        order_by: account.name
    )
  end

  @doc """
  Finds an existing correspondent by case-insensitive name or creates one.
  """
  def upsert_correspondent(name), do: find_or_create_named(Correspondent, name)

  @doc """
  Finds an existing document type by case-insensitive name or creates one.
  """
  def upsert_document_type(name), do: find_or_create_named(DocumentType, name)

  @doc """
  Finds an existing tag by case-insensitive name or creates one, assigning a
  stable color derived from the name.
  """
  def upsert_tag(name) when is_binary(name) do
    find_or_create_named(Tag, name, %{color: Tag.color_for(name)})
  end

  def upsert_tag(_name), do: nil

  def upsert_tags(names) when is_list(names) do
    names
    |> Enum.map(&upsert_tag/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  def upsert_tags(_names), do: []

  # Reuse an existing entry whose name is the same (case-insensitively) or a
  # close fuzzy match before creating a new one. Used by the document
  # classifier agent's create tools so it cannot coin near-duplicates (for
  # example "Acme" when "Acme Inc." already exists). Returns the resolved
  # record, or nil for a blank/invalid name.
  @similarity_threshold 0.9

  @doc "Finds the closest existing correspondent or creates one."
  def resolve_correspondent(name), do: fuzzy_find_or_create_named(Correspondent, name, %{})

  @doc "Finds the closest existing document type or creates one."
  def resolve_document_type(name), do: fuzzy_find_or_create_named(DocumentType, name, %{})

  @doc "Finds the closest existing tag or creates one with a stable color."
  def resolve_tag(name) when is_binary(name) do
    fuzzy_find_or_create_named(Tag, name, %{color: Tag.color_for(name)})
  end

  def resolve_tag(_name), do: nil

  defp find_or_create_named(_schema, name) when not is_binary(name), do: nil
  defp find_or_create_named(schema, name), do: find_or_create_named(schema, name, %{})

  defp find_or_create_named(schema, name, extra_attrs) when is_binary(name) do
    trimmed = String.trim(name)

    if trimmed != "" do
      fetch_by_name(schema, trimmed) || insert_named(schema, trimmed, extra_attrs)
    end
  end

  defp fuzzy_find_or_create_named(schema, name, extra_attrs) when is_binary(name) do
    trimmed = String.trim(name)

    if trimmed != "" do
      fetch_by_name(schema, trimmed) || fetch_similar_by_name(schema, trimmed) ||
        insert_named(schema, trimmed, extra_attrs)
    end
  end

  defp fuzzy_find_or_create_named(_schema, _name, _extra_attrs), do: nil

  defp insert_named(schema, name, extra_attrs) do
    attrs = Map.merge(%{name: name}, extra_attrs)

    struct(schema)
    |> schema.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} -> record
      # A concurrent ingest created the same name first; reuse it.
      {:error, _changeset} -> fetch_by_name(schema, name)
    end
  end

  defp fetch_by_name(schema, name) do
    Repo.one(from record in schema, where: fragment("lower(?)", record.name) == ^String.downcase(name))
  end

  defp fetch_similar_by_name(schema, name) do
    target = String.downcase(name)

    matches =
      schema
      |> Repo.all()
      |> Enum.map(fn record -> {record, String.jaro_distance(target, String.downcase(record.name))} end)
      |> Enum.filter(fn {_record, score} -> score >= @similarity_threshold end)

    case matches do
      [] -> nil
      _ -> matches |> Enum.max_by(fn {_record, score} -> score end) |> elem(0)
    end
  end

  defp store_file(body, attrs) do
    filename = attrs["original_filename"] || attrs[:original_filename] || "document"
    checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    key = object_key(checksum, filename)

    with {:ok, _response} <- Storage.put_object(key, body, content_type: attrs["content_type"] || attrs[:content_type]) do
      {:ok, %{bucket: Storage.bucket(), key: key, checksum_sha256: checksum}}
    end
  end

  defp insert_document(attrs, object, byte_size) do
    filename = attrs["original_filename"] || attrs[:original_filename]

    document_attrs =
      attrs
      |> stringify_keys()
      |> Map.merge(%{
        "title" => attrs["title"] || attrs[:title] || title_from_filename(filename),
        "byte_size" => byte_size,
        "checksum_sha256" => object.checksum_sha256,
        "storage_bucket" => object.bucket,
        "storage_key" => object.key,
        "status" => "uploaded",
        "content_type" => attrs["content_type"] || attrs[:content_type] || "application/octet-stream"
      })

    # Programmatic foreign keys are set explicitly rather than cast from
    # user-provided attrs.
    %Document{}
    |> Document.changeset(document_attrs)
    |> Ecto.Changeset.put_change(:uploaded_by_id, document_attrs["uploaded_by_id"])
    |> Ecto.Changeset.put_change(:account_id, document_attrs["account_id"])
    |> Repo.insert()
  end

  defp maybe_enqueue_processing(document, opts) do
    if Keyword.get(opts, :enqueue?, true) do
      %{document_id: document.id}
      |> ProcessDocument.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp mark_processing(document) do
    document
    |> Document.changeset(%{status: "processing", last_error: nil})
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_document("document.processing_started", updated, %{})
      _result -> :ok
    end)
  end

  defp mark_failed(document_id, reason) do
    case Repo.get(Document, document_id) do
      %Document{} = document ->
        document
        |> Document.changeset(%{status: "failed", last_error: inspect(reason)})
        |> Repo.update()
        |> tap(fn
          {:ok, updated} ->
            audit_document("document.processing_failed", updated, %{"reason" => inspect(reason)})

          _result ->
            :ok
        end)

      nil ->
        :ok
    end
  end

  # Classification enriches metadata but must not block ingest. When the
  # classifier fails and the caller opts into fallback (the worker's final
  # attempt), use filename-derived metadata so the document still finalizes
  # with extracted text and embeddings rather than being retried forever.
  defp classify_with_fallback(document, pages, opts) do
    case deterministic_metadata(document, pages) do
      {:ok, metadata} ->
        {:ok,
         put_classification_attribute(
           metadata,
           "classified",
           nil,
           Keyword.put(opts, :classification_source, "deterministic")
         )}

      :unknown ->
        case classify(document, pages, opts) do
          {:ok, metadata} ->
            {:ok, put_classification_attribute(metadata, "classified", nil, opts)}

          {:error, reason} ->
            if Keyword.get(opts, :classify_fallback?, false) or LLMErrors.hard_failure?(reason) do
              Logger.warning("Document #{document.id} classifier failed (#{inspect(reason)}); using filename metadata")

              {:ok,
               document
               |> DocumentClassifierAgent.fallback_metadata()
               |> put_classification_attribute("fallback", reason, opts)}
            else
              {:error, reason}
            end
        end
    end
  end

  defp classify(document, pages, opts) do
    classifier = Keyword.get_lazy(opts, :classifier, &configured_classifier/0)
    classifier.classify(document, pages)
  end

  defp configured_classifier do
    :atlas
    |> Application.get_env(:documents, [])
    |> Keyword.get(:classifier, DocumentClassifierAgent)
  end

  defp finalize_document(document, pages, metadata, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    correspondent = upsert_correspondent(metadata[:correspondent])
    document_type = upsert_document_type(metadata[:document_type])
    tags = upsert_tags(metadata[:tags] || [])
    account = document_account(document, document_type, pages, metadata)

    delete_page_vectors(existing_page_ids(document))

    result = persist_processed_document(document, pages, metadata, account, correspondent, document_type, tags, now)

    with {:ok, {updated, inserted_pages}} <- result do
      run_document_finalization_side_effects(document, updated, inserted_pages, opts)
    end
  end

  # The transaction does only DB work. Embedding each page calls out to the LLM
  # and vector service over HTTP, so it runs after the transaction commits.
  defp persist_processed_document(document, pages, metadata, account, correspondent, document_type, tags, now) do
    Repo.transaction(fn ->
      from(page in DocumentPage, where: page.document_id == ^document.id) |> Repo.delete_all()

      inserted_pages = insert_document_pages(document, pages)
      updated = update_processed_document(document, metadata, account, correspondent, document_type, tags, now)

      {updated, inserted_pages}
    end)
  end

  defp insert_document_pages(document, pages) do
    Enum.map(pages, fn page ->
      %DocumentPage{}
      |> DocumentPage.changeset(%{
        document_id: document.id,
        page_number: page.page_number,
        content: page.content,
        metadata: page.metadata
      })
      |> Repo.insert!()
    end)
  end

  defp update_processed_document(document, metadata, account, correspondent, document_type, tags, now) do
    document
    |> Repo.preload(:tags)
    |> Document.changeset(processed_document_attrs(document, metadata, now))
    |> put_classifier_associations(account, correspondent, document_type, tags)
    |> Repo.update!()
  end

  # Correspondent and document type are resolved programmatically by the
  # classifier. Account may be preassigned by the ingestion source or inferred
  # by the processing pipeline, so these fields are set explicitly.
  defp put_classifier_associations(changeset, account, correspondent, document_type, tags) do
    changeset
    |> Ecto.Changeset.put_change(:account_id, account && account.id)
    |> Ecto.Changeset.put_change(:correspondent_id, correspondent && correspondent.id)
    |> Ecto.Changeset.put_change(:document_type_id, document_type && document_type.id)
    |> Ecto.Changeset.put_assoc(:tags, tags)
  end

  defp processed_document_attrs(document, metadata, now) do
    %{
      title: metadata[:title] || document.title,
      summary: metadata[:summary],
      attributes: Map.merge(document.attributes || %{}, metadata[:attributes] || %{}),
      document_date: metadata[:document_date],
      archive_serial_number: document.archive_serial_number || next_archive_serial_number(),
      status: "ready",
      processed_at: now,
      last_error: nil
    }
  end

  defp run_document_finalization_side_effects(original_document, updated, inserted_pages, opts) do
    Enum.each(inserted_pages, fn page -> index_page_vector(page, original_document, opts) end)
    apply_classifier_side_effects(updated, inserted_pages, opts)
    {:ok, updated}
  end

  # Side effects that follow any classification write, whether the document was
  # just ingested or re-classified by the backfill. Kept separate from page
  # indexing, which only the ingest path performs.
  defp apply_classifier_side_effects(%Document{} = document, pages, opts) do
    maybe_enqueue_service_level_extraction(document)
    maybe_sync_account_from_order_form(document, pages)
    maybe_extract_finance_invoice(document, pages, opts)
    :ok
  end

  defp maybe_extract_finance_invoice(%Document{} = document, pages, opts) do
    document = Repo.preload(document, [:document_type, :correspondent])

    if extractable_invoice_document?(document) and not deterministic_classification?(document) do
      extractor = Keyword.get(opts, :invoice_extractor, InvoiceExtractorAgent)

      case extractor.extract(document, pages) do
        {:ok, %{invoice: invoice_attrs, line_items: line_items}} ->
          invoice_attrs =
            invoice_attrs
            |> Map.update(
              :metadata,
              invoice_source_metadata(document),
              &Map.merge(invoice_source_metadata(document), &1)
            )
            |> maybe_put_finance_transaction_id(document)

          Finance.upsert_extracted_invoice(document, invoice_attrs, line_items)
          :ok

        {:error, reason} ->
          Finance.mark_invoice_extraction_failed(document, reason)
          Logger.warning("Could not extract invoice breakdown from document #{document.id}: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end

  defp deterministic_classification?(%Document{attributes: %{"classification" => %{"source" => "deterministic"}}}),
    do: true

  defp deterministic_classification?(_document), do: false

  defp extractable_invoice_document?(%Document{document_type: %{name: name}}) when is_binary(name) do
    name |> String.downcase() |> String.contains?("invoice")
  end

  defp extractable_invoice_document?(%Document{original_filename: filename, attributes: attributes})
       when is_binary(filename) do
    String.contains?(String.downcase(filename), "invoice") or qonto_attachment?(attributes)
  end

  defp extractable_invoice_document?(%Document{attributes: attributes}), do: qonto_attachment?(attributes)

  defp qonto_attachment?(attributes) when is_map(attributes), do: is_binary(attributes["qonto_attachment_id"])
  defp qonto_attachment?(_attributes), do: false

  defp invoice_source_metadata(%Document{} = document) do
    %{
      "document_path" => "/documents/#{document.id}",
      "document_source" => document.source,
      "finance_transaction_id" => document.attributes && document.attributes["finance_transaction_id"],
      "qonto_transaction_id" => document.attributes && document.attributes["qonto_transaction_id"],
      "qonto_attachment_id" => document.attributes && document.attributes["qonto_attachment_id"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp maybe_put_finance_transaction_id(attrs, %Document{attributes: %{"finance_transaction_id" => transaction_id}})
       when is_binary(transaction_id) and transaction_id != "" do
    Map.put(attrs, :finance_transaction_id, transaction_id)
  end

  defp maybe_put_finance_transaction_id(attrs, _document), do: attrs

  defp maybe_sync_account_from_order_form(%Document{account_id: nil}, _pages), do: :ok

  defp maybe_sync_account_from_order_form(%Document{} = document, pages) do
    document = Repo.preload(document, [:document_type])

    case Accounts.sync_account_from_order_form(document, pages) do
      :noop ->
        :ok

      {:ok, _account} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not sync account commercial fields from document #{document.id}: #{inspect(reason)}")

        :ok
    end
  end

  defp maybe_enqueue_service_level_extraction(%Document{account_id: nil}), do: :ok

  defp maybe_enqueue_service_level_extraction(%Document{id: document_id}) do
    document_id
    |> ExtractDocumentServiceLevels.new_unique()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Could not enqueue service level extraction for document #{document_id}: #{inspect(changeset)}")
        :ok
    end
  end

  defp next_archive_serial_number do
    (Repo.one(from document in Document, select: max(document.archive_serial_number)) || 0) + 1
  end

  @doc """
  Re-runs account matching for an existing document without re-extracting text or
  re-indexing vectors. Used by backfills after the association was introduced.
  """
  def associate_document_account(document_id) when is_binary(document_id) do
    case get_document(document_id) do
      %Document{} = document ->
        case match_document_account(document) do
          %Account{} = account ->
            document
            |> Ecto.Changeset.change(account_id: account.id)
            |> Repo.update()
            |> tap(fn
              {:ok, updated} ->
                audit_document("document.account_associated", updated, %{
                  "account_id" => account.id,
                  "account_path" => "/sales/accounts/#{account.id}"
                })

              _result ->
                :ok
            end)

          nil ->
            {:ok, document}
        end

      nil ->
        {:error, :document_not_found}
    end
  end

  @doc """
  Recomputes and persists the account association for a document.

  Unlike `associate_document_account/1`, this clears an existing account when
  the current document content no longer matches any account. It is useful after
  matcher changes, where prior backfills may have been too permissive.
  """
  def reconcile_document_account(document_id) when is_binary(document_id) do
    case get_document(document_id) do
      %Document{} = document ->
        account = match_document_account(document)
        account_id = account && account.id

        if document.account_id == account_id do
          {:ok, document, :unchanged}
        else
          document
          |> Ecto.Changeset.change(account_id: account_id)
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              audit_document("document.account_reconciled", updated, %{
                "account_id" => account_id,
                "account_path" => account_id && "/sales/accounts/#{account_id}"
              })

              {:ok, updated, :updated}

            {:error, reason} ->
              {:error, reason}
          end
        end

      nil ->
        {:error, :document_not_found}
    end
  end

  @doc """
  Backfills account associations for ready documents that do not have one yet.
  """
  def backfill_document_accounts(opts \\ []) do
    limit = Keyword.get(opts, :limit)

    Document
    |> where([document], is_nil(document.account_id))
    |> where([document], document.status == "ready")
    |> order_by([document], asc: document.inserted_at)
    |> maybe_limit(limit)
    |> select([document], document.id)
    |> Repo.all()
    |> Enum.reduce(%{matched: 0, unmatched: 0, failed: 0}, fn document_id, acc ->
      case associate_document_account(document_id) do
        {:ok, %Document{account_id: nil}} -> Map.update!(acc, :unmatched, &(&1 + 1))
        {:ok, %Document{}} -> Map.update!(acc, :matched, &(&1 + 1))
        {:error, _reason} -> Map.update!(acc, :failed, &(&1 + 1))
      end
    end)
  end

  @doc """
  Recomputes account associations for ready documents, including already-linked
  documents, and clears stale links when the matcher returns no account.
  """
  def reconcile_document_accounts(opts \\ []) do
    limit = Keyword.get(opts, :limit)

    Document
    |> where([document], document.status == "ready")
    |> order_by([document], asc: document.inserted_at)
    |> maybe_limit(limit)
    |> select([document], document.id)
    |> Repo.all()
    |> Enum.reduce(%{updated: 0, unchanged: 0, failed: 0}, fn document_id, acc ->
      case reconcile_document_account(document_id) do
        {:ok, _document, :updated} -> Map.update!(acc, :updated, &(&1 + 1))
        {:ok, _document, :unchanged} -> Map.update!(acc, :unchanged, &(&1 + 1))
        {:error, _reason} -> Map.update!(acc, :failed, &(&1 + 1))
      end
    end)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  @doc """
  Lists ready documents whose page text exists but metadata has not been
  classified by the agent yet.
  """
  def list_document_classification_candidate_ids(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_classification_candidate_limit)
    include_failed? = Keyword.get(opts, :include_failed?, true)

    classification_status_filter =
      if include_failed? do
        dynamic(
          [document, _page, _document_type],
          fragment("?->?->>'status' in ('fallback', 'failed')", document.attributes, ^@classification_attribute_key)
        )
      else
        dynamic(
          [document, _page, _document_type],
          fragment("?->?->>'status' = 'fallback'", document.attributes, ^@classification_attribute_key)
        )
      end

    Document
    |> join(:inner, [document], page in assoc(document, :pages))
    |> join(:left, [document, _page], document_type in assoc(document, :document_type))
    |> where([document, _page, _document_type], document.status == "ready")
    |> maybe_exclude_failed_classifications(include_failed?)
    |> where(
      [document, _page, _document_type],
      fragment("coalesce(?->?->>'status', '') <> 'classified'", document.attributes, ^@classification_attribute_key)
    )
    |> where(
      ^dynamic(
        [document, _page, document_type],
        ^classification_status_filter or
          is_nil(document.correspondent_id) or is_nil(document.document_type_id) or
          is_nil(document.document_date) or is_nil(document.summary) or document.summary == "" or
          fragment("lower(coalesce(?, '')) = 'other'", document_type.name)
      )
    )
    |> group_by([document, _page, _document_type], [document.id, document.inserted_at])
    |> order_by([document, _page, _document_type], asc: document.inserted_at, asc: document.id)
    |> maybe_limit(limit)
    |> select([document, _page, _document_type], document.id)
    |> Repo.all()
  end

  defp maybe_exclude_failed_classifications(query, true), do: query

  defp maybe_exclude_failed_classifications(query, false) do
    where(
      query,
      [document, _page, document_type],
      fragment("coalesce(?->?->>'status', '') <> 'failed'", document.attributes, ^@classification_attribute_key)
    )
  end

  @doc """
  Re-runs only metadata classification for an already processed document.

  The existing extracted pages and vector records are kept intact. The document
  title, normalized type, correspondent, date, tags, summary, account
  association, and searchable attributes are refreshed from the classifier.
  """
  def classify_document_metadata(document_id, opts \\ []) when is_binary(document_id) do
    case get_document(document_id) do
      nil ->
        {:error, :document_not_found}

      %Document{status: status} when status != "ready" ->
        {:error, :document_not_ready}

      %Document{pages: []} ->
        {:error, :document_has_no_pages}

      %Document{} = document ->
        classify_ready_document_metadata(document, opts)
    end
  end

  defp classify_ready_document_metadata(%Document{} = document, opts) do
    pages = document.pages

    case deterministic_metadata(document, pages) do
      {:ok, metadata} ->
        metadata =
          put_classification_attribute(
            metadata,
            "classified",
            nil,
            Keyword.put(opts, :classification_source, "deterministic")
          )

        update_classified_document_metadata(document, pages, metadata, opts)

      :unknown ->
        case classify(document, pages, opts) do
          {:ok, metadata} ->
            metadata = put_classification_attribute(metadata, "classified", nil, opts)
            update_classified_document_metadata(document, pages, metadata, opts)

          {:error, reason} ->
            _ = mark_classification_failed(document, reason, opts)
            {:error, reason}
        end
    end
  end

  defp deterministic_metadata(%Document{} = document, pages) when is_list(pages) do
    text = document_text(document, pages)

    cond do
      invoice_like?(document, text) ->
        finance_document_metadata(document, text, "invoice")

      receipt_like?(document, text) ->
        finance_document_metadata(document, text, "receipt")

      true ->
        :unknown
    end
  end

  defp document_text(%Document{} = document, pages) do
    [
      document.title,
      document.original_filename,
      Enum.map_join(Enum.take(pages, 2), "\n", & &1.content)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp invoice_like?(%Document{} = document, text) do
    qonto_transaction_attachment?(document.attributes) or
      text_matches?(document, text, ["invoice", "bill to", "invoice number", "amount due"])
  end

  defp receipt_like?(%Document{} = document, text) do
    text_matches?(document, text, ["receipt", "date paid", "amount paid", "payment receipt"])
  end

  defp text_matches?(%Document{} = document, text, markers) do
    haystack =
      [
        document.title,
        document.original_filename,
        String.slice(text || "", 0, 4_000)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> String.downcase()

    Enum.any?(markers, &String.contains?(haystack, &1))
  end

  defp finance_document_metadata(%Document{} = document, text, document_type) do
    with correspondent when is_binary(correspondent) <- finance_correspondent(document, text),
         %Date{} = document_date <- finance_document_date(document, text) do
      amount = extract_amount(text)

      {:ok,
       %{
         title: document.title || title_from_filename(document.original_filename),
         document_type: document_type,
         correspondent: correspondent,
         document_date: document_date,
         tags: ["finance", document_type],
         summary: finance_summary(document_type, correspondent, amount),
         attributes: finance_attributes(amount)
       }}
    else
      _missing -> :unknown
    end
  end

  defp finance_correspondent(%Document{} = document, text) do
    [document.title, document.original_filename]
    |> Enum.find_value(&extract_correspondent_from_name/1)
    |> case do
      nil -> extract_correspondent_from_text(text)
      correspondent -> correspondent
    end
  end

  defp extract_correspondent_from_name(nil), do: nil

  defp extract_correspondent_from_name(name) do
    name =
      name
      |> Path.basename()
      |> Path.rootname()
      |> String.replace(~r/[_-]+/, " ")

    [
      ~r/\bqonto\s+(?:invoice|receipt)\s+(.+)$/i,
      ~r/\b(?:invoice|receipt)\s+(?:from\s+)?(.+)$/i,
      ~r/^(.+?)\s+(?:invoice|receipt)\b/i
    ]
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, name) do
        [_match, value] -> clean_correspondent(value)
        _other -> nil
      end
    end)
  end

  defp extract_correspondent_from_text(text) when is_binary(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.take(12)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^\s*(?:merchant|vendor|paid to|from)\s*:?\s+(.+)$/i, line) do
        [_match, value] -> clean_correspondent(value)
        _other -> nil
      end
    end)
  end

  defp extract_correspondent_from_text(_text), do: nil

  defp clean_correspondent(value) when is_binary(value) do
    value =
      value
      |> String.replace(~r/\b(?:invoice|receipt|paid|date|number|no\.?|#)\b.*$/i, "")
      |> String.replace(~r/\b20\d{2}[-\/.]\d{1,2}[-\/.]\d{1,2}\b/, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim(" -_.,")

    if String.length(value) >= 2, do: value
  end

  defp finance_document_date(%Document{document_date: %Date{} = date}, _text), do: date

  defp finance_document_date(%Document{} = document, text) do
    extract_date(text) || extract_date(document.original_filename || "")
  end

  defp extract_date(text) when is_binary(text) do
    extract_iso_date(text) || extract_month_name_date(text)
  end

  defp extract_iso_date(text) do
    case Regex.run(~r/\b(20\d{2})[-\/.](\d{1,2})[-\/.](\d{1,2})\b/, text) do
      [_match, year, month, day] -> build_date(year, month, day)
      _other -> nil
    end
  end

  defp extract_month_name_date(text) do
    case Regex.run(~r/\b([A-Z][a-z]+)\s+(\d{1,2}),\s*(20\d{2})\b/, text) do
      [_match, month, day, year] -> build_date(year, month_number(month), day)
      _other -> nil
    end
  end

  defp build_date(year, month, day) do
    with {year, ""} <- Integer.parse(to_string(year)),
         {month, ""} <- Integer.parse(to_string(month)),
         {day, ""} <- Integer.parse(to_string(day)),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _other -> nil
    end
  end

  defp month_number(month) do
    month
    |> String.downcase()
    |> then(&Map.get(@month_numbers, &1))
  end

  defp extract_amount(text) when is_binary(text) do
    Regex.run(
      ~r/(?:total|amount paid|amount due)[^\d€$£]{0,30}([€$£])?\s*([0-9][0-9,]*(?:\.\d{2})?)(?:\s*(USD|EUR|GBP))?/i,
      text
    )
    |> case do
      [_match, symbol, amount, currency] ->
        %{amount: String.replace(amount, ",", ""), currency: currency_from(symbol, currency)}

      [_match, symbol, amount] ->
        %{amount: String.replace(amount, ",", ""), currency: currency_from(symbol, nil)}

      _other ->
        nil
    end
  end

  defp extract_amount(_text), do: nil

  defp currency_from("$", _currency), do: "USD"
  defp currency_from("€", _currency), do: "EUR"
  defp currency_from("£", _currency), do: "GBP"
  defp currency_from(_symbol, currency) when is_binary(currency) and currency != "", do: String.upcase(currency)
  defp currency_from(_symbol, _currency), do: nil

  defp finance_summary(document_type, correspondent, nil) do
    "#{String.capitalize(document_type)} from #{correspondent}."
  end

  defp finance_summary(document_type, correspondent, %{amount: amount, currency: currency}) do
    amount_text = if currency, do: "#{amount} #{currency}", else: amount
    "#{String.capitalize(document_type)} from #{correspondent} for #{amount_text}."
  end

  defp finance_attributes(nil), do: %{}

  defp finance_attributes(%{amount: amount, currency: currency}) do
    %{"amount" => amount, "currency" => currency}
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp update_classified_document_metadata(document, pages, metadata, opts) do
    correspondent = upsert_correspondent(metadata[:correspondent])
    document_type = upsert_document_type(metadata[:document_type])
    tags = upsert_tags(metadata[:tags] || [])
    account = document_account(document, document_type, pages, metadata)

    result =
      document
      |> Repo.preload(:tags)
      |> Document.changeset(classified_document_attrs(document, metadata))
      |> put_classifier_associations(account, correspondent, document_type, tags)
      |> Repo.update()

    with {:ok, updated} <- result do
      apply_classifier_side_effects(updated, pages, opts)

      audit_document("document.classified", updated, %{
        "account_id" => updated.account_id,
        "document_type" => document_type && document_type.name,
        "correspondent" => correspondent && correspondent.name
      })

      {:ok, updated}
    end
  end

  defp classified_document_attrs(document, metadata) do
    # Re-classification refreshes metadata but must not erase values the document
    # already has: when the classifier omits a summary or date, keep the existing
    # one rather than overwriting it with nil.
    %{
      title: metadata[:title] || document.title,
      summary: metadata[:summary] || document.summary,
      attributes: Map.merge(document.attributes || %{}, metadata[:attributes] || %{}),
      document_date: metadata[:document_date] || document.document_date,
      last_error: nil
    }
  end

  defp mark_classification_failed(%Document{} = document, reason, opts) do
    document
    |> Document.changeset(%{
      attributes:
        put_in(
          document.attributes || %{},
          [@classification_attribute_key],
          classification_attribute("failed", reason, opts)
        )
    })
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        audit_document("document.classification_failed", updated, %{"reason" => inspect(reason)})

      _result ->
        :ok
    end)
  end

  defp put_classification_attribute(metadata, status, reason, opts) do
    attributes = Map.get(metadata, :attributes) || %{}
    stamped = Map.put(attributes, @classification_attribute_key, classification_attribute(status, reason, opts))
    Map.put(metadata, :attributes, stamped)
  end

  defp classification_attribute(status, reason, opts) do
    %{
      "status" => status,
      "source" => Keyword.get(opts, :classification_source) || classification_source(status),
      "classifier" => opts |> Keyword.get_lazy(:classifier, &configured_classifier/0) |> inspect(),
      "classified_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
    |> maybe_put_classification_error(reason)
  end

  defp classification_source("fallback"), do: "filename"
  defp classification_source(_status), do: "agent"

  defp maybe_put_classification_error(attributes, nil), do: attributes
  defp maybe_put_classification_error(attributes, reason), do: Map.put(attributes, "last_error", inspect(reason))

  defp match_document_account(%Document{} = document) do
    metadata = %{
      title: document.title,
      summary: document.summary,
      correspondent: document.correspondent && document.correspondent.name,
      attributes: document.attributes || %{}
    }

    maybe_match_account(document, document.pages, metadata)
  end

  defp document_account(%Document{} = document, document_type, pages, metadata) do
    document = %{document | document_type: document_type}

    if !vendor_side_document?(document) do
      preassigned_account(document) || match_account(document, pages, metadata)
    end
  end

  defp preassigned_account(%Document{account_id: nil}), do: nil

  defp preassigned_account(%Document{account_id: account_id}) do
    Repo.get(Account, account_id)
  end

  defp maybe_match_account(%Document{} = document, pages, metadata) do
    if !vendor_side_document?(document) do
      match_account(document, pages, metadata)
    end
  end

  defp vendor_side_document?(%Document{} = document) do
    invoice_document?(document) or qonto_transaction_attachment?(document.attributes)
  end

  defp qonto_transaction_attachment?(%{"qonto_transaction_id" => transaction_id}) when is_binary(transaction_id) do
    true
  end

  defp qonto_transaction_attachment?(%{"qonto_attachment_id" => attachment_id}) when is_binary(attachment_id) do
    true
  end

  defp qonto_transaction_attachment?(_attributes), do: false

  defp invoice_document?(%Document{document_type: %{name: name}}) when is_binary(name) do
    name |> String.downcase() |> String.contains?("invoice")
  end

  defp invoice_document?(%Document{original_filename: filename}) when is_binary(filename) do
    String.contains?(String.downcase(filename), "invoice")
  end

  defp invoice_document?(_document), do: false

  defp match_account(%Document{} = document, pages, metadata) do
    haystacks = document_match_haystacks(document, pages, metadata)

    Account
    |> preload(:account_handles)
    |> Repo.all()
    |> Enum.map(fn account -> {account, account_match_score(account, haystacks)} end)
    |> Enum.filter(fn {_account, score} -> score > 0 end)
    |> Enum.sort_by(fn {_account, score} -> score end, :desc)
    |> case do
      [{account, score}, {_other, other_score} | _] when score == other_score ->
        if exact_account_identifier?(account, haystacks.full), do: account

      [{account, _score} | _] ->
        account

      [] ->
        nil
    end
  end

  defp document_match_haystacks(%Document{} = document, pages, metadata) do
    context =
      [
        document.title,
        document.original_filename,
        metadata[:title],
        metadata[:correspondent],
        document_attributes_text(searchable_attributes(metadata[:attributes]))
      ]
      |> join_match_text()

    full =
      [
        context,
        metadata[:summary],
        Enum.map_join(Enum.take(pages, 8), "\n", & &1.content)
      ]
      |> join_match_text()

    %{context: context, full: full}
  end

  defp join_match_text(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> normalize_match_text()
  end

  # The classification attribute is internal bookkeeping (classifier module,
  # status, timestamps), not document content, so it must not participate in
  # account matching or it would false-match accounts named like a classifier.
  defp searchable_attributes(attributes) when is_map(attributes) do
    Map.delete(attributes, @classification_attribute_key)
  end

  defp searchable_attributes(_attributes), do: %{}

  defp document_attributes_text(attributes) when is_map(attributes) do
    attributes
    |> Map.values()
    |> Enum.map_join(" ", &inspect/1)
  end

  defp account_match_score(%Account{} = account, %{context: context, full: full}) do
    [
      {account.contract_id, 120, full},
      {account.primary_domain, 100, full},
      {account.legal_name, 90, full},
      {account.name, 80, context},
      {account.account_key, 60, full}
    ]
    |> Kernel.++(Enum.map(account.account_handles, fn %AccountHandle{handle: handle} -> {handle, 90, full} end))
    |> Enum.reduce(0, fn {identifier, weight, haystack}, score ->
      if identifier_matches?(identifier, haystack), do: score + weight, else: score
    end)
  end

  defp exact_account_identifier?(%Account{} = account, haystack) do
    Enum.any?([account.contract_id, account.primary_domain], &identifier_matches?(&1, haystack))
  end

  defp identifier_matches?(identifier, haystack) when is_binary(identifier) do
    normalized = normalize_match_text(identifier)

    String.length(normalized) >= 4 and
      Regex.match?(~r/(^|[^a-z0-9])#{Regex.escape(normalized)}([^a-z0-9]|$)/, haystack)
  end

  defp identifier_matches?(_identifier, _haystack), do: false

  defp normalize_match_text(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9@._-]+/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Generates the page embedding and stores it in the OpenData Vector service
  # keyed by `document_page:<page_id>`. Postgres only records which model
  # embedded the page and when. Indexing is best-effort: an unconfigured or
  # failing vector service must not abort document processing.
  defp index_page_vector(%DocumentPage{} = page, %Document{} = document, opts) do
    case Embedding.embed(page.content, opts) do
      {:ok, %{embedding: embedding, model: model}} ->
        upsert_page_vector(page, document, embedding)

        page
        |> DocumentPage.changeset(%{
          embedding_model: model,
          embedded_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      {:error, _reason} ->
        page
    end
  end

  defp upsert_page_vector(%DocumentPage{} = page, %Document{} = document, embedding) do
    # Only fields declared in the vector collection's metadata schema
    # (source_type, document_id) may be sent; the service rejects unknown
    # fields. page_number is recovered from Postgres when hydrating hits.
    Vector.upsert_vectors([
      %{
        id: vector_id(page),
        vector: embedding,
        attributes: %{
          "source_type" => @vector_source_type,
          "document_id" => document.id
        }
      }
    ])
  end

  defp existing_page_ids(%Document{} = document) do
    Repo.all(from page in DocumentPage, where: page.document_id == ^document.id, select: page.id)
  end

  defp delete_page_vectors([]), do: :ok

  defp delete_page_vectors(page_ids) when is_list(page_ids) do
    Vector.delete_vectors(Enum.map(page_ids, &"#{@vector_source_type}:#{&1}"))
  end

  defp vector_id(%DocumentPage{id: id}), do: "#{@vector_source_type}:#{id}"

  # Briefly cleans the temp file up when the processing job exits, so
  # process_document does not remove it explicitly.
  defp write_temp(filename, body) do
    with {:ok, path} <- Briefly.create(prefix: "atlas-document", extname: Path.extname(filename)),
         :ok <- File.write(path, body) do
      {:ok, path}
    end
  end

  defp maybe_filter_query(queryable, nil), do: queryable
  defp maybe_filter_query(queryable, ""), do: queryable

  defp maybe_filter_query(queryable, query) do
    pattern = "%#{query}%"

    from(document in queryable,
      where:
        ilike(document.title, ^pattern) or ilike(document.original_filename, ^pattern) or
          ilike(document.summary, ^pattern)
    )
  end

  defp maybe_filter_by_named(queryable, _assoc, nil), do: queryable
  defp maybe_filter_by_named(queryable, _assoc, ""), do: queryable

  defp maybe_filter_by_named(queryable, :document_type, name) do
    from(document in queryable,
      join: document_type in assoc(document, :document_type),
      where: fragment("lower(?)", document_type.name) == ^String.downcase(name)
    )
  end

  defp maybe_filter_by_named(queryable, :correspondent, name) do
    from(document in queryable,
      join: correspondent in assoc(document, :correspondent),
      where: fragment("lower(?)", correspondent.name) == ^String.downcase(name)
    )
  end

  defp maybe_filter_by_named(queryable, :tag, name) do
    from(document in queryable,
      join: tag in assoc(document, :tags),
      where: fragment("lower(?)", tag.name) == ^String.downcase(name)
    )
  end

  defp maybe_exclude_by_named(queryable, _assoc, nil), do: queryable
  defp maybe_exclude_by_named(queryable, _assoc, ""), do: queryable

  defp maybe_exclude_by_named(queryable, :document_type, name) do
    from(document in queryable,
      left_join: document_type in assoc(document, :document_type),
      where: is_nil(document_type.id) or fragment("lower(?)", document_type.name) != ^String.downcase(name)
    )
  end

  defp maybe_exclude_by_named(queryable, :correspondent, name) do
    from(document in queryable,
      left_join: correspondent in assoc(document, :correspondent),
      where: is_nil(correspondent.id) or fragment("lower(?)", correspondent.name) != ^String.downcase(name)
    )
  end

  defp maybe_exclude_by_named(queryable, :tag, name) do
    from(document in queryable,
      where:
        fragment(
          """
          not exists (
            select 1
            from documents_tags documents_tag
            join document_tags tag on tag.id = documents_tag.tag_id
            where documents_tag.document_id = ? and lower(tag.name) = ?
          )
          """,
          document.id,
          ^String.downcase(name)
        )
    )
  end

  defp maybe_filter(queryable, _field, nil), do: queryable
  defp maybe_filter(queryable, _field, ""), do: queryable

  defp maybe_filter(queryable, field, value) do
    from(document in queryable, where: field(document, ^field) == ^value)
  end

  defp maybe_exclude(queryable, _field, nil), do: queryable
  defp maybe_exclude(queryable, _field, ""), do: queryable

  defp maybe_exclude(queryable, field, value) do
    from(document in queryable, where: field(document, ^field) != ^value or is_nil(field(document, ^field)))
  end

  defp maybe_filter_document_page(queryable, opts) do
    queryable
    |> maybe_filter_document_page_account_id(Keyword.get(opts, :account_id))
    |> maybe_filter_document_page_named(:document_type, Keyword.get(opts, :document_type))
    |> maybe_filter_document_page_named(:correspondent, Keyword.get(opts, :correspondent))
    |> maybe_filter_document_page_named(:tag, Keyword.get(opts, :tag))
    |> maybe_filter_document_page_status(Keyword.get(opts, :status))
    |> maybe_exclude_document_page_account_id(Keyword.get(opts, :exclude_account_id))
    |> maybe_exclude_document_page_named(:document_type, Keyword.get(opts, :exclude_document_type))
    |> maybe_exclude_document_page_named(:correspondent, Keyword.get(opts, :exclude_correspondent))
    |> maybe_exclude_document_page_named(:tag, Keyword.get(opts, :exclude_tag))
    |> maybe_exclude_document_page_status(Keyword.get(opts, :exclude_status))
  end

  defp maybe_filter_document_page_account_id(query, nil), do: query
  defp maybe_filter_document_page_account_id(query, ""), do: query

  defp maybe_filter_document_page_account_id(query, account_id) do
    where(query, [document: document], document.account_id == ^account_id)
  end

  defp maybe_filter_document_page_named(query, _assoc, nil), do: query
  defp maybe_filter_document_page_named(query, _assoc, ""), do: query

  defp maybe_filter_document_page_named(query, :document_type, name) do
    query
    |> join(:inner, [document: document], document_type in assoc(document, :document_type), as: :filter_document_type)
    |> where([filter_document_type: document_type], fragment("lower(?)", document_type.name) == ^String.downcase(name))
  end

  defp maybe_filter_document_page_named(query, :correspondent, name) do
    query
    |> join(:inner, [document: document], correspondent in assoc(document, :correspondent), as: :filter_correspondent)
    |> where([filter_correspondent: correspondent], fragment("lower(?)", correspondent.name) == ^String.downcase(name))
  end

  defp maybe_filter_document_page_named(query, :tag, name) do
    query
    |> join(:inner, [document: document], tag in assoc(document, :tags), as: :filter_tag)
    |> where([filter_tag: tag], fragment("lower(?)", tag.name) == ^String.downcase(name))
  end

  defp maybe_filter_document_page_status(query, nil), do: query
  defp maybe_filter_document_page_status(query, ""), do: query

  defp maybe_filter_document_page_status(query, status) do
    where(query, [document: document], document.status == ^status)
  end

  defp maybe_exclude_document_page_account_id(query, nil), do: query
  defp maybe_exclude_document_page_account_id(query, ""), do: query

  defp maybe_exclude_document_page_account_id(query, account_id) do
    where(query, [document: document], document.account_id != ^account_id or is_nil(document.account_id))
  end

  defp maybe_exclude_document_page_named(query, _assoc, nil), do: query
  defp maybe_exclude_document_page_named(query, _assoc, ""), do: query

  defp maybe_exclude_document_page_named(query, :document_type, name) do
    query
    |> join(:left, [document: document], document_type in assoc(document, :document_type), as: :exclude_document_type)
    |> where(
      [exclude_document_type: document_type],
      is_nil(document_type.id) or fragment("lower(?)", document_type.name) != ^String.downcase(name)
    )
  end

  defp maybe_exclude_document_page_named(query, :correspondent, name) do
    query
    |> join(:left, [document: document], correspondent in assoc(document, :correspondent), as: :exclude_correspondent)
    |> where(
      [exclude_correspondent: correspondent],
      is_nil(correspondent.id) or fragment("lower(?)", correspondent.name) != ^String.downcase(name)
    )
  end

  defp maybe_exclude_document_page_named(query, :tag, name) do
    where(
      query,
      [document: document],
      fragment(
        """
        not exists (
          select 1
          from documents_tags documents_tag
          join document_tags tag on tag.id = documents_tag.tag_id
          where documents_tag.document_id = ? and lower(tag.name) = ?
        )
        """,
        document.id,
        ^String.downcase(name)
      )
    )
  end

  defp maybe_exclude_document_page_status(query, nil), do: query
  defp maybe_exclude_document_page_status(query, ""), do: query

  defp maybe_exclude_document_page_status(query, status) do
    where(query, [document: document], document.status != ^status or is_nil(document.status))
  end

  defp maybe_filter_metadata_documents(queryable, opts) do
    queryable
    |> maybe_filter_metadata_document_account_id(Keyword.get(opts, :account_id))
    |> maybe_filter_metadata_document_named(:document_type, Keyword.get(opts, :document_type))
    |> maybe_filter_metadata_document_named(:correspondent, Keyword.get(opts, :correspondent))
    |> maybe_filter_metadata_document_named(:tag, Keyword.get(opts, :tag))
    |> maybe_filter_metadata_document_status(Keyword.get(opts, :status))
    |> maybe_exclude_metadata_document_account_id(Keyword.get(opts, :exclude_account_id))
    |> maybe_exclude_metadata_document_named(:document_type, Keyword.get(opts, :exclude_document_type))
    |> maybe_exclude_metadata_document_named(:correspondent, Keyword.get(opts, :exclude_correspondent))
    |> maybe_exclude_metadata_document_named(:tag, Keyword.get(opts, :exclude_tag))
    |> maybe_exclude_metadata_document_status(Keyword.get(opts, :exclude_status))
  end

  defp maybe_filter_metadata_document_account_id(query, nil), do: query
  defp maybe_filter_metadata_document_account_id(query, ""), do: query

  defp maybe_filter_metadata_document_account_id(query, account_id) do
    where(query, [document, _document_type, _correspondent, _account, _tag], document.account_id == ^account_id)
  end

  defp maybe_filter_metadata_document_named(query, _assoc, nil), do: query
  defp maybe_filter_metadata_document_named(query, _assoc, ""), do: query

  defp maybe_filter_metadata_document_named(query, :document_type, name) do
    where(
      query,
      [_document, document_type, _correspondent, _account, _tag],
      fragment("lower(?)", document_type.name) == ^String.downcase(name)
    )
  end

  defp maybe_filter_metadata_document_named(query, :correspondent, name) do
    where(
      query,
      [_document, _document_type, correspondent, _account, _tag],
      fragment("lower(?)", correspondent.name) == ^String.downcase(name)
    )
  end

  defp maybe_filter_metadata_document_named(query, :tag, name) do
    where(
      query,
      [_document, _document_type, _correspondent, _account, tag],
      fragment("lower(?)", tag.name) == ^String.downcase(name)
    )
  end

  defp maybe_filter_metadata_document_status(query, nil), do: query
  defp maybe_filter_metadata_document_status(query, ""), do: query

  defp maybe_filter_metadata_document_status(query, status) do
    where(query, [document, _document_type, _correspondent, _account, _tag], document.status == ^status)
  end

  defp maybe_exclude_metadata_document_account_id(query, nil), do: query
  defp maybe_exclude_metadata_document_account_id(query, ""), do: query

  defp maybe_exclude_metadata_document_account_id(query, account_id) do
    where(
      query,
      [document, _document_type, _correspondent, _account, _tag],
      document.account_id != ^account_id or is_nil(document.account_id)
    )
  end

  defp maybe_exclude_metadata_document_named(query, _assoc, nil), do: query
  defp maybe_exclude_metadata_document_named(query, _assoc, ""), do: query

  defp maybe_exclude_metadata_document_named(query, :document_type, name) do
    where(
      query,
      [_document, document_type, _correspondent, _account, _tag],
      is_nil(document_type.id) or fragment("lower(?)", document_type.name) != ^String.downcase(name)
    )
  end

  defp maybe_exclude_metadata_document_named(query, :correspondent, name) do
    where(
      query,
      [_document, _document_type, correspondent, _account, _tag],
      is_nil(correspondent.id) or fragment("lower(?)", correspondent.name) != ^String.downcase(name)
    )
  end

  defp maybe_exclude_metadata_document_named(query, :tag, name) do
    where(
      query,
      [document, _document_type, _correspondent, _account, _tag],
      fragment(
        """
        not exists (
          select 1
          from documents_tags documents_tag
          join document_tags tag on tag.id = documents_tag.tag_id
          where documents_tag.document_id = ? and lower(tag.name) = ?
        )
        """,
        document.id,
        ^String.downcase(name)
      )
    )
  end

  defp maybe_exclude_metadata_document_status(query, nil), do: query
  defp maybe_exclude_metadata_document_status(query, ""), do: query

  defp maybe_exclude_metadata_document_status(query, status) do
    where(
      query,
      [document, _document_type, _correspondent, _account, _tag],
      document.status != ^status or is_nil(document.status)
    )
  end

  defp order_documents(queryable, sort_by, sort_order) do
    direction = sort_direction(sort_order)

    case normalize_sort_by(sort_by) do
      "document_date" ->
        order_by(queryable, [document], [
          {^nulls_sort_direction(direction), document.document_date},
          desc: document.id
        ])

      "inserted_at" ->
        order_by(queryable, [document], [{^direction, document.inserted_at}, {^direction, document.id}])

      _field ->
        # id (UUIDv7, time-ordered) is a stable tiebreaker so offset pagination is
        # deterministic even when several documents share an inserted_at second.
        order_by(queryable, [document], desc: document.inserted_at, desc: document.id)
    end
  end

  defp sort_document_match_rows(rows, opts) do
    case normalize_sort_by(Keyword.get(opts, :sort_by)) do
      "document_date" ->
        Enum.sort(rows, &date_sorted_before?(&1.document, &2.document, sort_direction(opts[:sort_order])))

      "inserted_at" ->
        Enum.sort(rows, &inserted_at_sorted_before?(&1.document, &2.document, sort_direction(opts[:sort_order])))

      _field ->
        rows
    end
  end

  defp normalize_sort_by(value) when value in @sortable_document_fields, do: value
  defp normalize_sort_by(:document_date), do: "document_date"
  defp normalize_sort_by(:inserted_at), do: "inserted_at"
  defp normalize_sort_by(_value), do: nil

  defp sort_direction("asc"), do: :asc
  defp sort_direction(:asc), do: :asc
  defp sort_direction(_value), do: :desc

  defp nulls_sort_direction(:asc), do: :asc_nulls_last
  defp nulls_sort_direction(:desc), do: :desc_nulls_last

  defp date_sorted_before?(left, right, direction) do
    case {left.document_date, right.document_date} do
      {nil, nil} -> left.id >= right.id
      {nil, _date} -> false
      {_date, nil} -> true
      {%Date{} = left_date, %Date{} = right_date} -> compare_dates(left_date, right_date, left.id, right.id, direction)
    end
  end

  defp compare_dates(left_date, right_date, left_id, right_id, direction) do
    case Date.compare(left_date, right_date) do
      :eq -> left_id >= right_id
      :lt -> direction == :asc
      :gt -> direction == :desc
    end
  end

  # NaiveDateTime structs must be compared with NaiveDateTime.compare/2; Erlang term
  # order would sort them by struct key order (day before month before year). The id
  # tiebreaker follows the sort direction to match order_documents/3's inserted_at branch.
  defp inserted_at_sorted_before?(left, right, direction) do
    case NaiveDateTime.compare(left.inserted_at, right.inserted_at) do
      :eq -> compare_ids(left.id, right.id, direction)
      :lt -> direction == :asc
      :gt -> direction == :desc
    end
  end

  defp compare_ids(left_id, right_id, :asc), do: left_id <= right_id
  defp compare_ids(left_id, right_id, _desc), do: left_id >= right_id

  defp object_key(checksum, filename) do
    extension = filename |> Path.extname() |> String.downcase()
    "documents/#{String.slice(checksum, 0, 2)}/#{checksum}#{extension}"
  end

  defp audit_document(action, %Document{} = document, metadata, opts \\ []) do
    Audit.record(
      action,
      %{
        target_type: "document",
        target_id: document.id,
        target_label: document.title || document.original_filename,
        metadata: metadata || %{}
      },
      opts
    )
  end

  defp title_from_filename(filename) do
    filename
    |> Path.basename()
    |> Path.rootname()
    |> String.replace(~r/[_-]+/, " ")
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
