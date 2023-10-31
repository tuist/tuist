# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

class ActiveRecord::Base
  # @shim: this is included at runtime https://github.com/rails/globalid/blob/v1.0.0/lib/global_id/railtie.rb#L38
  include GlobalID::Identification
end

module GlobalID::Identification
  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(GlobalID) }
  def to_gid(options = {}); end

  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(String) }
  def to_gid_param(options = {}); end

  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(GlobalID) }
  def to_global_id(options = {}); end

  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(SignedGlobalID) }
  def to_sgid(options = {}); end

  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(String) }
  def to_sgid_param(options = {}); end

  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(SignedGlobalID) }
  def to_signed_global_id(options = {}); end
end
