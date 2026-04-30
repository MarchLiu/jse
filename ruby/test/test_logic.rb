require_relative "test_helper"

class TestLogic < Minitest::Test
  include JSE::TestHelper

  def setup
    env = JSE::Env.new
    env.load(JSE::Functors::Builtin::BUILTIN_FUNCTORS)
    env.load(JSE::Functors::Utils::UTILS_FUNCTORS)
    @engine = JSE::Engine.new(env)
  end

  def test_and_basic
    assert_equal true, @engine.execute(["$and", true, true, true])
    assert_equal false, @engine.execute(["$and", true, false, true])
  end

  def test_or_basic
    assert_equal true, @engine.execute(["$or", false, false, true])
    assert_equal false, @engine.execute(["$or", false, false, false])
  end

  def test_not_basic
    assert_equal false, @engine.execute(["$not", true])
    assert_equal true, @engine.execute(["$not", false])
  end

  def test_nested_logic
    expr = ["$or",
            ["$and", true, ["$not", false]],
            ["$and", false, true]]
    assert_equal true, @engine.execute(expr)
  end

  def test_deep_nesting
    expr = ["$and",
            ["$not", ["$or", false, false]],
            ["$or", ["$not", true], true]]
    assert_equal true, @engine.execute(expr)
  end
end
