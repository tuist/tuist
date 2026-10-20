defmodule Atlas.GTM.Workers.PostBlogPostIdeaAnnouncement do
  @moduledoc """
  Announces a newly captured blog post idea in the company Slack #marketing
  channel and records the resulting thread on the idea so replies can be
  captured as follow-up comments.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.GTM
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.GTM.BlogPostIdeaNotifier

  @impl true
  def perform(%Oban.Job{args: %{"blog_post_idea_id" => idea_id}}) when is_binary(idea_id) do
    case GTM.get_blog_post_idea(idea_id) do
      nil ->
        {:cancel, :idea_not_found}

      %BlogPostIdea{} = idea ->
        case BlogPostIdeaNotifier.announce(idea) do
          {:ok, thread_ts} ->
            GTM.set_blog_post_idea_slack_thread(idea, thread_ts)
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
