defmodule TuistEx.Cache.Prefetch do
  @moduledoc false

  alias TuistEx.Cache.Reapi

  # Only the caller plans keys and consumes results. Workers perform transport
  # only: Mix project state, environment changes and installation stay serialized.
  def with_fetcher(remote, plan, callback) do
    reference = make_ref()

    fetch = fn key, dependency ->
      request = {key, dependency.app}
      {result, remaining} = Map.pop(Process.get(reference, %{}), request, :unfetched)
      Process.put(reference, remaining)

      if result == :unfetched do
        case remote.() do
          nil ->
            :miss

          session ->
            requests = plan.(key, dependency)
            results = Reapi.get_many(session, requests)
            {result, remaining} = Map.pop(results, request, :miss)
            Process.put(reference, remaining)
            result
        end
      else
        result
      end
    end

    try do
      callback.(fetch)
    after
      Process.delete(reference)
    end
  end
end
