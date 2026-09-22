defmodule Atlas.Nudges.Proposal do
  @moduledoc """
  A signal's output when it decides to fire. The nudges context turns this
  into a persisted `Atlas.Nudges.Nudge` row after the dedup and rate-limit
  guards pass.
  """

  @enforce_keys [:dedup_key, :title, :rationale, :draft_subject, :draft_body]
  defstruct [
    :dedup_key,
    :title,
    :rationale,
    :draft_subject,
    :draft_body,
    :contact_id,
    evidence: %{},
    severity: "normal",
    expires_in_days: 7
  ]

  @type t :: %__MODULE__{
          dedup_key: String.t(),
          title: String.t(),
          rationale: String.t(),
          draft_subject: String.t(),
          draft_body: String.t(),
          contact_id: binary() | nil,
          evidence: map(),
          severity: String.t(),
          expires_in_days: pos_integer()
        }
end
