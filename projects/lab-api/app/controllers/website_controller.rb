# typed: ignore
# frozen_string_literal: true

class WebsiteController < ApplicationController
  layout "website"

  def landing
    render("website/landing")
  end

  def privacy
    render("website/privacy")
  end

  def terms
    render("website/terms")
  end

  def cookie
    render("website/cookie")
  end

  def acceptable_use_policy
    render("website/acceptable_use_policy")
  end

  def changelog
    @changelogs = changelogs
    render("website/changelog")
  end

  def changelog_feed
    head(:ok)
  end

  private

  def changelogs
    changelog_dir = Rails.root.join("app/content/changelog")
    Dir.glob(File.join(changelog_dir, "*")).map do |file_path|
      parsed_file = FrontMatterParser::Parser.parse_file(file_path)
      date_string = File.basename(file_path).split("-").first
      OpenStruct.new(
        date: Date.strptime(date_string, "%Y%m%d"),
        title: parsed_file.front_matter["title"],
        type: parsed_file.front_matter["type"],
        html: markdown_parser.render(parsed_file.content)
      )
    end
  end

  def markdown_parser
    @markdown_parser ||= Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true)
  end
end
