# JSE MoonBit - Testing Guide

## Overview

The MoonBit implementation of JSE (JSON Structural Expression) follows the same architecture as the Python, Rust, and TypeScript versions but is adapted for MoonBit's type system and language features.

## Building and Checking

```bash
# Check the code for errors
moon check

# Build the project
moon build

# Build with warnings suppressed
moon build --warn-list -unused_mut
```

## Testing Approach

Due to MoonBit's type system, the `JseValue` enum constructors are read-only. This means testing needs to be done differently than in other languages.

### Method 1: Compare with Other Implementations

The best way to test the MoonBit implementation is to:

1. Run the same JSON expressions through the Python implementation
2. Compare the results with the MoonBit implementation

Example workflow:
```bash
# Run Python tests
cd ../python
pytest tests/

# Note the expected results
# Then use equivalent JSON in MoonBit
```

### Method 2: Create Test Data Files

Create JSON files with test expressions and expected results:

```json
// test_data.json
{
  "tests": [
    {
      "name": "basic number",
      "expression": 42,
      "expected": 42
    },
    {
      "name": "boolean true",
      "expression": true,
      "expected": true
    },
    {
      "name": "and operator",
      "expression": ["$and", true, true],
      "expected": true
    }
  ]
}
```

### Method 3: Manual Testing with REPL

When MoonBit gets a REPL or interactive mode, you can test expressions directly:

```moonbit
let engine = with_default_env()
let result = Engine::execute(engine, expression)
// Check result
```

## Test Coverage Areas

### 1. Basic Expressions
- Numbers, strings, booleans, null
- Arrays and objects

### 2. Logic Operators
- `$and` - Logical AND
- `$or` - Logical OR
- `$not` - Logical NOT
- `$eq` - Equality check

### 3. Control Flow
- `$cond` - Conditional expression

### 4. Array Operations
- `$head` - Get first element
- `$tail` - Get rest of array
- `$cons` - Add element to front
- `$atom?` - Check if not array/object

### 5. Object Operations
- `$get` - Get object property
- `$set` - Set object property
- `$del` - Delete object property
- `$conj` - Conjunction (alias for set)

### 6. Type Predicates
- `$list?` - Check if array
- `$map?` - Check if object
- `$null?` - Check if null

## Running the Demo

```bash
# Compile and run the demo
cd examples
moon run demo.mbt
```

## Known Limitations

1. **Read-only JseValue constructors**: Cannot create JseValue directly in test code
2. **Test framework integration**: MoonBit's test framework has specific requirements
3. **No REPL yet**: Cannot test interactively

## Recommendations

For now, the best testing approach is:

1. **Use Python as reference**: Run tests in Python first
2. **Manual verification**: Compare MoonBit output with Python output
3. **Property-based testing**: Test invariants that should hold true
4. **Integration testing**: Test from the perspective of JSON input/output

## Future Improvements

1. Add JSON parsing support to create JseValues from strings
2. Create a proper test suite once MoonBit's test framework matures
3. Add property-based tests
4. Create benchmark tests
