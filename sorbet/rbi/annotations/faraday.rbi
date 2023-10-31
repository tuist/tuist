# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module Faraday
  class << self
    sig { params(url: T.untyped, options: T::Hash[Symbol, T.untyped], block: T.nilable(T.proc.params(connection: Faraday::Connection).void)).returns(Faraday::Connection) }
    def new(url = nil, options = {}, &block); end
  end
end

class Faraday::Response
  sig { returns(T::Boolean) }
  def success?; end
end
