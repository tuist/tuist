defmodule Tuist.Runners.GitLab.Job do
  @moduledoc "GitLab job identity and encrypted, temporary execution payload."
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Runners.GitLab.Connection
  alias Tuist.Vault.Binary

  @primary_key {:workflow_job_id, :integer, read_after_writes: true}
  schema "runner_gitlab_jobs" do
    field :url, :string
    field :job_id, :integer
    field :project_path, :string
    field :pipeline_id, :integer
    field :payload, Binary, redact: true
    belongs_to :account, Account
    belongs_to :connection, Connection
    timestamps(type: :utc_datetime)
  end

  def job_url(%__MODULE__{url: url, project_path: path, job_id: id}), do: "#{url}/#{path}/-/jobs/#{id}"
  def project_url(%__MODULE__{url: url, project_path: path}), do: "#{url}/#{path}"
  def pipeline_url(%__MODULE__{url: url, project_path: path, pipeline_id: id}), do: "#{url}/#{path}/-/pipelines/#{id}"
end
