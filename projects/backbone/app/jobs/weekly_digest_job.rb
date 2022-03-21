# frozen_string_literal: true

require "slack-ruby-block-kit"

class WeeklyDigestJob < ApplicationJob
  def perform(channel: "#general")
    week_before_past = Time.now.last_week.last_week..Time.now.last_week.last_week.end_of_week
    past_week = Time.now.last_week..Time.now.last_week.end_of_week

    generated_projects_week_before_past = CommandEvent.where(name: "generate", created_at: week_before_past).count
    generated_projects_past_week = CommandEvent.where(name: "generate", created_at: past_week).count
    generated_projects_diff = (
      (generated_projects_past_week.to_f / generated_projects_week_before_past.to_f - 1) * 100
    ).to_i

    focused_projects_week_before_past = CommandEvent.where(name: "focus", created_at: week_before_past).count
    focused_projects_past_week = CommandEvent.where(name: "focus", created_at: past_week).count
    focused_projects_diff = ((focused_projects_past_week.to_f / focused_projects_week_before_past.to_f - 1) * 100).to_i

    warmed_projects_week_before_past = CommandEvent.where(name: "cache", subcommand: "warm",
      created_at: week_before_past).count
    warmed_projects_past_week = CommandEvent.where(name: "cache", subcommand: "warm", created_at: past_week).count
    warmed_projects_diff = ((warmed_projects_past_week.to_f / warmed_projects_week_before_past.to_f - 1) * 100).to_i

    fetched_dependencies_week_before_past = CommandEvent.where(name: "dependencies", subcommand: "fetch",
      created_at: week_before_past).count
    fetched_dependencies_past_week = CommandEvent.where(name: "dependencies", subcommand: "fetch",
      created_at: past_week).count
    fetched_dependencies_diff = (
      (fetched_dependencies_past_week.to_f / fetched_dependencies_week_before_past.to_f - 1) * 100
    ).to_i

    updated_dependencies_week_before_past = CommandEvent.where(name: "dependencies", subcommand: "update",
      created_at: week_before_past).count
    updated_dependencies_past_week = CommandEvent.where(name: "dependencies", subcommand: "update",
      created_at: past_week).count
    updated_dependencies_diff = (
      (updated_dependencies_past_week.to_f / updated_dependencies_week_before_past.to_f - 1) * 100
    ).to_i

    client = Slack::Web::Client.new
    blocks = Slack::BlockKit.blocks do |b|
      b.header(text: "Weekly Digest")
      b.context do |c|
        c.mrkdwn(text: Time.now.to_formatted_s(:short))
      end
      b.section do |s|
        s.mrkdwn(text: "This is a weekly digest that contains some anonymized metrics about the usage of Tuist.")
      end
      b.divider
      b.section do |s|
        body = <<~BODY
        *Project generation*
        · Generated projects: #{generated_projects_past_week} _(#{more_or_less_percentage_in_words(generated_projects_diff)} the week before, #{generated_projects_week_before_past})_

        *Caching*
        · Focused projects: #{focused_projects_past_week} _(#{more_or_less_percentage_in_words(focused_projects_diff)} the week before, #{focused_projects_week_before_past})_
        · Cache-warmed projects: #{warmed_projects_past_week} _(#{more_or_less_percentage_in_words(warmed_projects_diff)} the week before, #{warmed_projects_week_before_past})_

        *Dependencies*
        · Fetched dependencies: #{fetched_dependencies_past_week} _(#{more_or_less_percentage_in_words(fetched_dependencies_diff)} than the week before, #{fetched_dependencies_week_before_past})_
        · Updated dependencies: #{updated_dependencies_past_week} _(#{more_or_less_percentage_in_words(updated_dependencies_diff)} than the week before, #{updated_dependencies_week_before_past})_

        BODY
        s.mrkdwn(text: body)
      end
    end

    client.chat_postMessage(channel: channel, blocks: blocks.to_json, as_user: true)
  end

  def more_or_less_percentage_in_words(percentage)
    if percentage < 0
      "#{-percentage}% less than"
    else
      "#{percentage}% more than"
    end
  end
end
