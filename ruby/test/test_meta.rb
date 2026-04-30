require_relative "test_helper"

class TestMeta < Minitest::Test
  def setup
    @env = JSE::Env.new
    # Register custom functors that read metadata
    @env.register("$get_meta", ->(env, *_args) { env.get_meta })
    @env.register("$get_meta_key", ->(env, key, *_args) {
      k = key.respond_to?(:apply) ? env.eval(key) : key
      env.get_meta[k]
    })
    @env.register("$meta_with_args", ->(env, *args) {
      evaluated = args.map { |a| env.eval(a) }
      { meta: env.get_meta, args: evaluated }
    })
    @engine = JSE::Engine.new(@env)
  end

  def test_basic_meta_passing
    result = @engine.execute({ "$get_meta" => nil, "key1" => "value1", "key2" => 42 })
    assert_equal({ "key1" => "value1", "key2" => 42 }, result)
  end

  def test_meta_string_value
    result = @engine.execute({ "$get_meta" => nil, "name" => "Alice" })
    assert_equal({ "name" => "Alice" }, result)
  end

  def test_meta_number_value
    result = @engine.execute({ "$get_meta" => nil, "count" => 99 })
    assert_equal({ "count" => 99 }, result)
  end

  def test_meta_with_multiple_keys
    result = @engine.execute({ "$get_meta" => nil, "a" => 1, "b" => 2, "c" => 3 })
    assert_equal 3, result.length
    assert_equal 1, result["a"]
  end

  def test_meta_with_args
    result = @engine.execute({ "$meta_with_args" => [1, 2, 3], "source" => "test" })
    assert_equal "test", result[:meta]["source"]
    assert_equal [1, 2, 3], result[:args]
  end

  def test_meta_cleared_after_functor
    @engine.execute({ "$get_meta" => nil, "key" => "val" })
    assert_empty @env.get_meta
  end

  def test_meta_null_value
    result = @engine.execute({ "$get_meta" => nil, "nullable" => nil })
    assert_nil result["nullable"]
  end

  def test_meta_boolean_value
    result = @engine.execute({ "$get_meta" => nil, "active" => true })
    assert_equal true, result["active"]
  end

  def test_meta_missing_key
    result = @engine.execute({ "$get_meta_key" => "nonexistent", "other" => "val" })
    assert_nil result
  end
end
