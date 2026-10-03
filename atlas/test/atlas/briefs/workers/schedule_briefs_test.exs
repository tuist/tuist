defmodule Atlas.Briefs.Workers.ScheduleBriefsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  alias Atlas.Briefs
  alias Atlas.Briefs.Config
  alias Atlas.Briefs.Workers.PostBrief
  alias Atlas.Briefs.Workers.ScheduleBriefs
  alias Atlas.Slack.API

  test "schedules the Monday financial pulse on a database that has only ever run migrations" do
    stub(Config, :leadership_slack_channel_id, fn -> "C-LEADERSHIP" end)

    stub(API, :get_channel_info, fn :company, "C-LEADERSHIP" ->
      {:ok,
       %{
         slack_app: :company,
         slack_channel_id: "C-LEADERSHIP",
         name: "leadership",
         is_shared: false,
         is_ext_shared: false,
         is_member: true,
         is_private: true
       }}
    end)

    assert :ok = perform_job(ScheduleBriefs, %{"cadence" => "weekly"})

    subscription = Briefs.get_subscription("leadership", "weekly")
    assert_enqueued(worker: PostBrief, args: %{"subscription_id" => subscription.id})
    assert %{cadence: "monthly"} = Briefs.get_subscription("leadership", "monthly")
  end

  test "schedules nothing when no leadership channel is configured" do
    stub(Config, :leadership_slack_channel_id, fn -> nil end)

    assert :ok = perform_job(ScheduleBriefs, %{"cadence" => "weekly"})
    refute_enqueued(worker: PostBrief)
  end

  test "recognizes the final day of a calendar month" do
    assert ScheduleBriefs.last_day_of_month?(~D[2028-02-29])
    refute ScheduleBriefs.last_day_of_month?(~D[2028-02-28])
  end
end
