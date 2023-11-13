# typed: strict

module Devise
  module Controllers
    module Helpers
      sig { returns(T.nilable(User)) }
      def current_user; end
    end
  end
end
