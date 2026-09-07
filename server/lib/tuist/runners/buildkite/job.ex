defmodule Tuist.Runners.Buildkite.Job do
  @moduledoc """
  Maps a Buildkite job UUID onto the 64-bit `workflow_job_id` the rest of
  the runners subsystem is keyed on. See
  `Tuist.Repo.Migrations.CreateRunnerBuildkiteJobs` for why the surrogate
  exists and how its keyspace is kept disjoint from GitHub's.

  The row is also where the Buildkite-only coordinates live — the
  organization, pipeline and build a job belongs to — so the dashboard can
  build a link back to Buildkite without those columns leaking into the
  provider-agnostic lifecycle table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:job_uuid, :string, []}

  schema "runner_buildkite_jobs" do
    field :workflow_job_id, :integer
    field :organization_slug, :string
    field :pipeline_slug, :string, default: ""
    field :build_uuid, :string, default: ""
    field :build_number, :integer, default: 0
    field :queue_key, :string, default: ""
    field :reserved_until, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :job_uuid,
      :account_id,
      :organization_slug,
      :pipeline_slug,
      :build_uuid,
      :build_number,
      :queue_key,
      :reserved_until
    ])
    |> validate_required([:job_uuid, :account_id, :organization_slug])
  end

  @doc """
  The Buildkite URL for a job's build. Buildkite has no per-job page; the
  build page anchors on the job, which is what the dashboard links to.
  """
  def build_url(%__MODULE__{build_number: 0}), do: nil

  def build_url(%__MODULE__{organization_slug: org, pipeline_slug: pipeline, build_number: number})
      when is_binary(org) and org != "" and is_binary(pipeline) and pipeline != "" do
    "https://buildkite.com/#{org}/#{pipeline}/builds/#{number}"
  end

  def build_url(_job), do: nil
end
