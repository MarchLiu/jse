/// JSE Demo Program
///
/// This is a simple demonstration of how to use the JSE engine.
/// Note: This is a conceptual example showing how JSE works.

// Since JseValue constructors are read-only, we need to use a different approach.
// The actual usage would typically involve parsing JSON from external sources.

pub fn main {
  println("JSE (JSON Structural Expression) - MoonBit Implementation v0.2.0")
  println("="                                                               .repeat(60))

  // The JSE engine works with JSON values that are parsed from external sources.
  // Here's how you would typically use it:

  println("\n1. Basic Usage:")
  println("   let engine = jse::with_default_env()")
  println("   let result = Engine::execute(engine, jse_value)")

  println("\n2. Available Functors:")
  println("   - Builtin: $quote, $eq, $cond, $head, $tail, $atom?, $cons")
  println("   - Utils:   $not, $list?, $map?, $null?, $get, $set, $del, $conj, $and, $or")
  println("   - SQL:     $pattern, $query, $expr")

  println("\n3. Example Expressions:")
  println("   [\"$and\", true, false]  => false")
  println("   [\"$eq\", 42, 42]        => true")
  println("   [\"$not\", true]        => false")
  println("   [\"$cond\", true, \"a\", false, \"b\"] => \"a\"")

  println("\n4. For actual usage:")
  println("   - Parse JSON from a file or string")
  println("   - Create an Engine instance")
  println("   - Execute the expression")
  println("   - Handle the Result")

  println("\n5. Testing:")
  println("   To test this implementation, you can:")
  println("   - Compare results with the Python/Rust/TypeScript implementations")
  println("   - Use the example JSON files from those implementations")
  println("   - Run: moon build to compile the code")
  println("   - Run: moon check to verify the code")

  println("\nFor more information, see:")
  println("  - README.md in the parent directory")
  println("  - Python implementation at ../python/")
  println("  - Rust implementation at ../rust/")
}
