defmodule Atlas.Engineering.Errors.ProjectKey do
  @moduledoc """
  A Data Source Name minted for a project, optionally scoped to a single
  domain.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "errors_project_keys" do
    field :dsn_project_id, :integer, read_after_writes: true
    field :public_key, :string
    field :secret_key, :string
    field :name, :string, default: "default"
    field :last_used_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :domain, Domain
    belongs_to :created_by, User, foreign_key: :created_by_user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(project_key, attrs) do
    project_key
    |> cast(attrs, [
      :project_id,
      :domain_id,
      :public_key,
      :secret_key,
      :name,
      :created_by_user_id
    ])
    |> validate_required([:project_id, :public_key, :name])
    |> validate_length(:public_key, is: 32)
    |> validate_length(:secret_key, is: 32)
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:public_key)
    |> unique_constraint([:project_id, :domain_id],
      name: :errors_project_keys_project_id_domain_id_index,
      message: "domain already has a DSN for this project"
    )
  end

  def generate_key do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  def dsn(%__MODULE__{public_key: public_key, dsn_project_id: project_id}, endpoint_url) when is_binary(endpoint_url) do
    uri = URI.parse(endpoint_url)
    scheme = uri.scheme || "https"
    host = uri.host
    port = if uri.port in [nil, 80, 443], do: "", else: ":#{uri.port}"
    "#{scheme}://#{public_key}@#{host}#{port}/#{project_id}"
  end
end
