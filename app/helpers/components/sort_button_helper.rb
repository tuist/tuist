# frozen_string_literal: true

module Components
  module SortButtonHelper
    def render_sort_button(label:, category:)
      render('components/sort_button', label: label, category: category)
    end

    def sort_link(column:)
      if column == params[:column]
        "?column=#{column}&direction=#{next_direction}"
      else
        "?column=#{column}&direction=asc"
      end
    end

    def next_direction
      params[:direction] == 'asc' ? 'desc' : 'asc'
    end
  end
end
