defmodule Atlas.GTM.Workers.SyncSocialPosts do
  @moduledoc "Daily read of every connected X account's posts and metrics."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  alias Atlas.GTM.SocialPosts

  @impl Oban.Worker
  def perform(_job), do: {:ok, SocialPosts.sync_all()}
end
