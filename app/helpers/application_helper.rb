# frozen_string_literal: true

module ApplicationHelper
  # Taken from: https://www.seancdavis.com/posts/render-inline-svg-rails-middleman/
  def svg(name, options = {})
    file_path = "#{Rails.root}/app/assets/images/#{name}.svg"
    if File.exist?(file_path)
      content_tag(:div, File.read(file_path).html_safe, class: options[:class])
    else
      '(not found)'
    end
  end
end
