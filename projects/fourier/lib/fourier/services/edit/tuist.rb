# frozen_string_literal: true

module Fourier
  module Services
    module Edit
      class Tuist < Base
        def call
          Utilities::System.tuist("edit", "--only-current-directory")
        end
      end
    end
  end
end
