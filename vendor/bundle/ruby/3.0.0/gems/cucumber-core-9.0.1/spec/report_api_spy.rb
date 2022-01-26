# frozen_string_literal: true
class ReportAPISpy
  def initialize
    @result = []
  end

  def test_case(*args)
    @result << [:test_case, *args]
    yield self if block_given?
  end

  def test_step(*args)
    @result << [:test_step, *args]
    yield self if block_given?
  end

  def done(*args)
    @result << [:done, *args]
    yield self if block_given?
  end

  def messages
    @result.map(&:first)
  end
end
