defmodule Atlas.Documents.Document do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Documents.Correspondent
  alias Atlas.Documents.DocumentPage
  alias Atlas.Documents.DocumentType
  alias Atlas.Documents.Tag
  alias Atlas.Users.User

  @statuses ~w(pending_upload uploaded processing ready failed)
  @sources ~w(upload paperless email qonto letter)

  # Offset pagination for the document library is delegated to Flop.
  @derive {Flop.Schema, filterable: [], sortable: [:document_date, :inserted_at], default_limit: 25, max_limit: 100}

  schema "documents" do
    field :title, :string
    field :original_filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :checksum_sha256, :string
    field :storage_bucket, :string
    field :storage_key, :string
    field :source, :string, default: "upload"
    field :status, :string, default: "uploaded"
    field :document_date, :date
    field :archive_serial_number, :integer
    field :attributes, :map, default: %{}
    field :summary, :string
    field :processed_at, :utc_datetime
    field :upload_expires_at, :utc_datetime
    field :last_error, :string

    belongs_to :account, Account
    belongs_to :uploaded_by, User
    belongs_to :correspondent, Correspondent
    belongs_to :document_type, DocumentType
    has_many :pages, DocumentPage
    many_to_many :tags, Tag, join_through: "documents_tags", on_replace: :delete

    timestamps()
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :title,
      :original_filename,
      :content_type,
      :byte_size,
      :checksum_sha256,
      :storage_bucket,
      :storage_key,
      :source,
      :status,
      :document_date,
      :archive_serial_number,
      :attributes,
      :summary,
      :processed_at,
      :upload_expires_at,
      :last_error
    ])
    |> validate_required([
      :title,
      :original_filename,
      :content_type,
      :storage_bucket,
      :storage_key,
      :source,
      :status
    ])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> validate_bytes_and_checksum()
    |> unique_constraint([:storage_bucket, :storage_key])
    |> unique_constraint(:archive_serial_number)
    |> assoc_constraint(:account)
    |> assoc_constraint(:correspondent)
    |> assoc_constraint(:document_type)
  end

  # byte_size and checksum_sha256 are only known once the bytes have landed in
  # storage, so a `pending_upload` row is allowed to omit them. Every other
  # status must carry both.
  defp validate_bytes_and_checksum(changeset) do
    case get_field(changeset, :status) do
      "pending_upload" -> changeset
      _status -> validate_required(changeset, [:byte_size, :checksum_sha256])
    end
  end

  @doc """
  Replaces the document's tag associations. Tags must already be persisted.
  """
  def tags_changeset(document, tags) when is_list(tags) do
    document
    |> change()
    |> put_assoc(:tags, tags)
  end

  def statuses, do: @statuses
  def sources, do: @sources
end
