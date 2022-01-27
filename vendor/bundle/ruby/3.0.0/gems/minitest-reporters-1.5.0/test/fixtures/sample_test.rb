Class.new(Minitest::Test) do
  def test_success
    assert true
  end
  def test_failure
    assert false
  end
  def test_skip
    skip('Skipping rope')
  end
  def test_error
    raise 'An unexpected error'
  end
end

