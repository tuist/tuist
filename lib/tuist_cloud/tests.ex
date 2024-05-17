defmodule TuistCloud.Tests do
  @moduledoc ~S"""
  A context that encapsulates the business logic of the Tuist Tests feature.
  """

  alias TuistCloud.CommandEvents.Event
  alias TuistCloud.Repo
  alias TuistCloud.Projects.Project
  alias TuistCloud.Accounts.Account

  @doc ~S"""
  Given a project, it returns the count of the remote binary cache hits for the current month.
  """
  def current_month_tested_target_hits_count(%Project{} = project) do
    Event.current_month_tested_target_hits_query(project) |> Repo.aggregate(:count)
  end

  def current_month_tested_target_hits_count(%Account{} = account) do
    Event.current_month_tested_target_hits_query(account) |> Repo.aggregate(:count)
  end
end
