defmodule TuistCloud.Cache do
  @moduledoc ~S"""
  A context that encapsulates the business logic of the Tuist Cache feature.
  """
  alias TuistCloud.CommandEvents.Event
  alias TuistCloud.Repo
  alias TuistCloud.Projects.Project
  alias TuistCloud.Accounts.Account

  def current_month_remote_binary_cache_hits_count(%Project{} = project) do
    Event.current_month_remote_binary_cache_hits_query(project) |> Repo.aggregate(:count)
  end

  def current_month_remote_binary_cache_hits_count(%Account{} = account) do
    Event.current_month_remote_binary_cache_hits_query(account) |> Repo.aggregate(:count)
  end
end
