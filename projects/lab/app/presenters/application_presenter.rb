# frozen_string_literal: true
class ApplicationPresenter
  def self.present(*args, &block)
    new(*args).present(&block)
  end

  def present
    raise NotImplementedError
  end
end
