defmodule Tuist.Runs.QuarantinedTestCase do
  @moduledoc """
  A virtual schema representing aggregated quarantined test case data.
  This is used to display test cases that are currently quarantined.
  """

  defstruct [
    :id,
    :name,
    :module_name,
    :suite_name,
    :quarantined_by_account_id,
    :quarantined_by_account_name,
    :last_ran_at,
    :last_run_id
  ]
end
