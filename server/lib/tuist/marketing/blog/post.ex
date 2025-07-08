defmodule Tuist.Marketing.Blog.Post do
  @moduledoc ~S"""
  This module defines the Post struct used to represent blog posts in the Tuist marketing website.
  Posts are loaded from markdown files and parsed into this struct by NimblePublisher.
  """
  @enforce_keys [:categories, :date, :excerpt, :slug, :title, :body]
  defstruct [
    :categories,
    :date,
    :excerpt,
    :slug,
    :title,
    :type,
    :interviewee_avatar,
    :interviewee_name,
    :interviewee_x_handle,
    :author,
    :body,
    :interviewee_role,
    :image_url,
    :tags,
    :category,
    :highlighted,
    :og_image_path
  ]

  def build(_filename, attrs, body) do
    title = String.trim_trailing(attrs["title"], ".")

    struct!(__MODULE__,
      categories: attrs["categories"],
      date: attrs["date"],
      excerpt: attrs["excerpt"],
      slug: attrs["slug"],
      title: title,
      type: attrs["type"],
      interviewee_avatar: attrs["interviewee_avatar"],
      interviewee_name: attrs["interviewee_name"],
      interviewee_role: attrs["interviewee_role"],
      interviewee_x_handle: attrs["interviewee_x_handle"],
      body: body,
      author: attrs["author"],
      image_url: attrs["image_url"],
      category: attrs["category"],
      tags: attrs["tags"] || [],
      highlighted: attrs["highlighted"] || false,
      og_image_path: attrs["og_image_path"]
    )
  end
end
