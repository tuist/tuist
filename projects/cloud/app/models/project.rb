# frozen_string_literal: true

class Project < ApplicationRecord
  # Associations
  belongs_to :account, optional: false
end
