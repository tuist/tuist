defmodule Tuist.Repo.Migrations.AddBillingMultiplierToRunnerSessions do
  @moduledoc """
  Persists the cost-weighted machine factor used to convert a session's
  elapsed time into normalized compute units.

  Storing it on the row rather than deriving it at invoice time is what
  makes the runner rate card safe to change: recomputing the multiplier
  from the live catalog would silently reprice every historical session
  the moment a shape's weighting changed. Nullable because rows written
  before this migration have no stored factor; billing falls back to the
  catalog for those, and the raw shape stays on the row either way so
  analytics keep full fidelity.
  """
  use Ecto.Migration

  def change do
    alter table(:runner_sessions) do
      add :billing_multiplier, :integer
    end
  end
end
