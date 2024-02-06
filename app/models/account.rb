# frozen_string_literal: true
# typed: true

class Account < ApplicationRecord
  extend T::Sig
  enum :plan, { enterprise: 1 }

  # Associations
  belongs_to :owner, polymorphic: true, optional: false
  has_many :projects, dependent: :destroy
  has_many :s3_buckets, class_name: "S3Bucket", dependent: :destroy

  # Validations
  validates :name, exclusion: Environment.blocklisted_slug_keywords
end
