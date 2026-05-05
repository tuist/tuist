defmodule Tuist.Bundles.Bundle do
  @moduledoc """
  ClickHouse-backed schema for app bundles.
  """

  use Ecto.Schema

  alias Tuist.Bundles.Artifact

  @platforms [
    :ios,
    :ios_simulator,
    :tvos,
    :tvos_simulator,
    :watchos,
    :watchos_simulator,
    :visionos,
    :visionos_simulator,
    :macos,
    :android
  ]

  @types [:ipa, :app, :xcarchive, :aab, :apk]

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :git_branch,
      :type,
      :name,
      :install_size,
      :download_size,
      :supported_platforms,
      :inserted_at
    ],
    sortable: [:inserted_at, :install_size, :download_size]
  }

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "bundles" do
    field :app_bundle_id, Ch, type: "String"
    field :name, Ch, type: "String"
    field :install_size, Ch, type: "Int64"
    field :download_size, Ch, type: "Nullable(Int64)"
    field :git_branch, Ch, type: "Nullable(String)"
    field :git_commit_sha, Ch, type: "Nullable(String)"
    field :git_ref, Ch, type: "Nullable(String)"
    field :supported_platforms, Ch, type: "Array(LowCardinality(String))"
    field :version, Ch, type: "String"
    field :type, Ch, type: "LowCardinality(String)"
    field :project_id, Ch, type: "Int64"
    field :uploaded_by_account_id, Ch, type: "Nullable(Int64)"

    field :inserted_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"

    belongs_to :project, Tuist.Projects.Project, type: :integer, define_field: false

    belongs_to :uploaded_by_account, Tuist.Accounts.Account,
      type: :integer,
      define_field: false

    has_many :artifacts, Artifact, foreign_key: :bundle_id
  end

  @doc """
  Atom values accepted as `type` on bundle uploads.
  """
  def types, do: @types

  @doc """
  Atom values accepted in `supported_platforms` on bundle uploads.
  """
  def supported_platforms, do: @platforms
end
