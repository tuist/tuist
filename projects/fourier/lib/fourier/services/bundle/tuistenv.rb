# frozen_string_literal: true
module Fourier
  module Services
    module Bundle
      class Tuistenv < Base
        def call
          # system("swift", "build", "--product", "tuistenv", "--configuration", "release")
        end
      end
    end
  end
end
