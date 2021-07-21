# frozen_string_literal: true
module MetaTagsHelper
  def meta_title(title)
    content_for(:meta_title, title)
  end

  def content_for_meta_title
    content_for?(:meta_title) ? "TuistLab | #{content_for(:meta_title)}" : Rails.application.config.defaults.dig(:site_metadata, :title)
  end

  def meta_description(description)
    content_for(:meta_description, description)
  end

  def content_for_meta_description
    content_for?(:meta_description) ? content_for(:meta_description) : Rails.application.config.defaults.dig(:site_metadata, :description)
  end

  def meta_keywords(keywords)
    content_for(:meta_keywords, keywords.join(","))
  end

  def content_for_meta_keywords
    content_for?(:meta_keywords) ? content_for(:meta_keywords) : Rails.application.config.defaults.dig(:site_metadata, :keywords)
  end

  def content_for_meta_image
    URI.join(Rails.application.config.defaults.dig(:urls, :app), asset_pack_path("media/images/logo-with-background.png")).to_s
  end

  def content_for_meta_twitter_handle
    Rails.application.config.defaults.dig(:site_metadata, :twitter)
  end
end
