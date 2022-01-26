require 'cucumber/messages'

module Cucumber
  module Messages
    describe VERSION do
      it 'should be defined' do
        expect(subject).to match(/\d+\.\d+\.\d+/)
      end
    end
  end
end