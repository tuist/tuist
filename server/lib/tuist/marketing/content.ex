defmodule Tuist.Marketing.Content do
  @moduledoc """
  Aggregates marketing content across sources (blog posts, case studies).
  """
  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Customers

  def get_entries do
    posts = Enum.map(Blog.get_posts(), &{:post, &1})
    case_studies = Enum.map(Customers.get_case_studies(), &{:case_study, &1})

    Enum.sort_by(posts ++ case_studies, &get_entry_date/1, {:desc, DateTime})
  end

  def get_entry_categories do
    get_entries()
    |> Enum.map(&get_entry_category/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def get_entry_title(entry), do: entry_data(entry).title
  def get_entry_excerpt(entry), do: entry_data(entry).excerpt
  def get_entry_body(entry), do: entry_data(entry).body
  def get_entry_slug(entry), do: entry_data(entry).slug
  def get_entry_image_url(entry), do: entry_data(entry).image_url
  def get_entry_date(entry), do: entry_data(entry).date
  def get_entry_category(entry), do: entry_data(entry).category
  def get_entry_author_name(entry), do: entry_data(entry).author_name

  defp entry_data({:post, post}) do
    %{
      title: post.title,
      excerpt: post.excerpt,
      body: post.body,
      slug: post.slug,
      image_url: Blog.get_post_image_url(post),
      date: post.date,
      category: post.category,
      author_name: Blog.get_post_author_name(post)
    }
  end

  defp entry_data({:case_study, case_study}) do
    %{
      title: case_study.title,
      excerpt: case_study.excerpt,
      body: case_study.body,
      slug: case_study.slug,
      image_url: Tuist.Environment.app_url(path: case_study.og_image_path, marketing: true),
      date: DateTime.new!(case_study.date, ~T[00:00:00], "Etc/UTC"),
      category: "case-studies",
      author_name: case_study.company
    }
  end
end
