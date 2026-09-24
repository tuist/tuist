defmodule Atlas.Product.Trace do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Integrations.GitHubRepository

  @kinds ~w(pull_request_opened pull_request_merged pull_request_closed issue_opened issue_closed)
  @sensitivities ~w(public internal restricted)

  @derive {
    Flop.Schema,
    filterable: [:kind, :github_repository_id],
    sortable: [:occurred_at, :inserted_at],
    default_limit: 50,
    max_limit: 100
  }

  schema "product_traces" do
    field :provider, :string, default: "github"
    field :kind, :string
    field :external_id, :string
    field :repository_full_name, :string
    field :number, :integer
    field :title, :string
    field :url, :string
    field :author_login, :string
    field :occurred_at, :utc_datetime
    field :labels, {:array, :string}, default: []
    field :sensitivity, :string, default: "internal"

    belongs_to :github_repository, GitHubRepository

    timestamps()
  end

  def kinds, do: @kinds

  def changeset(trace, attrs) do
    trace
    |> cast(attrs, [
      :provider,
      :kind,
      :external_id,
      :github_repository_id,
      :repository_full_name,
      :number,
      :title,
      :url,
      :author_login,
      :occurred_at,
      :labels,
      :sensitivity
    ])
    |> normalize_strings()
    |> validate_required([
      :provider,
      :kind,
      :external_id,
      :github_repository_id,
      :repository_full_name,
      :number,
      :title,
      :url,
      :occurred_at,
      :sensitivity
    ])
    |> validate_inclusion(:provider, ["github"])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_number(:number, greater_than: 0)
    |> foreign_key_constraint(:github_repository_id)
    |> unique_constraint([:provider, :external_id])
    |> check_constraint(:provider, name: :product_traces_provider_check)
    |> check_constraint(:kind, name: :product_traces_kind_check)
    |> check_constraint(:sensitivity, name: :product_traces_sensitivity_check)
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [
        :provider,
        :kind,
        :external_id,
        :repository_full_name,
        :title,
        :url,
        :author_login,
        :sensitivity
      ],
      changeset,
      fn field, changeset -> update_change(changeset, field, &normalize_string/1) end
    )
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: value
end
