defmodule Tuist.Ops.DailySlackReportWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "generates and sends the report" do
    # Given
    stub(Tuist.Time, :utc_now, fn -> ~U[2024-05-21 10:20:30Z] end)
    stub(Tuist.CommandEvents, :count_events_in_period, fn _, _ -> 1 end)
    stub(Tuist.CommandEvents, :count_all_events, fn -> 1 end)

    created_at = ~U[2024-05-20 10:20:30Z]
    user = [created_at: created_at] |> AccountsFixtures.user_fixture() |> Repo.preload(:account)

    project =
      ProjectsFixtures.project_fixture(account_id: user.account.id, created_at: created_at)

    AccountsFixtures.organization_fixture(creator: user, created_at: created_at)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 1500,
      created_at: created_at,
      remote_cache_target_hits: ["target1", "target2"]
    )

    stub(Tuist.Slack, :send_message, fn blocks ->
      assert blocks == [
               %{
                 type: "header",
                 text: %{type: "plain_text", text: "Daily report 21.5.2024 📈 (test)"}
               },
               %{
                 type: "context",
                 elements: [
                   %{
                     type: "plain_text",
                     text: "Great things start small—believe in your vision and keep pushing forward."
                   }
                 ]
               },
               %{
                 type: "section",
                 text: %{
                   type: "plain_text",
                   text:
                     "The following data represents data from Monday to today, and its growth compared to the same weekday last week:\n"
                 }
               },
               %{
                 type: "rich_text",
                 elements: [
                   %{type: "rich_text_section", elements: []},
                   %{
                     type: "rich_text_list",
                     elements: [
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{type: "text", text: "👩‍💻 Users: ", style: %{bold: true}},
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       },
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{
                             type: "text",
                             text: "💼 Organizations: ",
                             style: %{bold: true}
                           },
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       },
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{type: "text", text: "⚙️ Projects: ", style: %{bold: true}},
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       },
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{
                             type: "text",
                             text: "▶️ Command events: ",
                             style: %{bold: true}
                           },
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       }
                     ],
                     style: "bullet"
                   }
                 ]
               }
             ]

      :ok
    end)

    # When
    Tuist.Ops.DailySlackReportWorker.perform(%{})
  end
end
