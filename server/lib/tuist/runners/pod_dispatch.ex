defmodule Tuist.Runners.PodDispatch do
  @moduledoc """
  Records that a runner Pod was handed a runner credential. See
  `Tuist.Runners.Claims.record_dispatch/3`: a Pod named here is refused
  any further claim, whether or not its claim row still exists.
  """
  use Ecto.Schema

  @primary_key {:pod_name, :string, []}

  schema "runner_pod_dispatches" do
    field :account_id, :integer
    field :workflow_job_id, :integer
    field :dispatched_at, :utc_datetime_usec
  end
end
