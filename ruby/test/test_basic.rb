require_relative "test_helper"

class TestBasic < Minitest::Test
  include JSE::TestHelper

  def setup
    @engine = JSE::Engine.with_env
  end

  def test_number
    assert_equal 42, @engine.execute(42)
  end

  def test_float
    assert_in_delta 3.14, @engine.execute(3.14), 0.001
  end

  def test_string
    assert_equal "hello", @engine.execute("hello")
  end

  def test_boolean_true
    assert_equal true, @engine.execute(true)
  end

  def test_boolean_false
    assert_equal false, @engine.execute(false)
  end

  def test_null
    assert_nil @engine.execute(nil)
  end

  def test_array
    result = @engine.execute([1, 2, 3])
    assert_equal [1, 2, 3], result
  end

  def test_dict
    result = @engine.execute({ "a" => 1, "b" => "x" })
    assert_equal({ "a" => 1, "b" => "x" }, result)
  end
end
