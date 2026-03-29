# JSE C# Runtime (`csharp`)

A .NET 8 implementation of JSE using:

- `System.Text.Json` for JSON parsing
- `System.Linq.Expressions` for expression-tree compilation

## Structure

- `Jse/Ast` immutable AST nodes
- `Jse/Serialization` AST/runtime serializer + parser facility
- `Jse/Runtime` engine/environment/operator registry
- `Jse/Execution` expression compiler with delegate cache
- `Jse.Tests` xUnit tests

## Example

```csharp
using Jse.Runtime;

var engine = new JseEngine();
var result = engine.Execute("[\"$add\",1,2]");
// result == 3
```

## Notes

- Execution is restricted to registered operators.
- Runtime dispatch is deterministic and restricted to registered operators and scoped callables.
- `$quote` returns unevaluated JSON-shaped data.
- Test catalog and stress scenarios are documented in `TESTING.md`.

## C# Specific Semantics

- JSON values are mapped by `JsonHelpers` as:
	- number -> `decimal`
	- array -> `List<object?>`
	- object -> `Dictionary<string, object?>`
- Parsing/AST serialization are centralized in `Jse.Serialization.JseRuntimeSerializer`.
- Compiler supports `Compile<T>` for typed delegate generation; `JseEngine.Execute` remains `object?` at the API boundary.
- Operator registry uses typed bindings and overload resolution by argument types.
- Operator registration accepts both specific and general signatures (including `object`/`object?`), and runtime selects the most specific applicable overload.
- Operator registration supports `Expression<Func<...>>` via `RegisterExpression(...)` and also includes special/variadic registration APIs.

## Serialization Support

- `Jse.Serialization.JseRuntimeSerializer` supports round-trip serialization for:
	- `JseNode` AST (`SerializeNode` / `DeserializeNode`)
	- `OperatorEnvironment` (`SerializeOperatorSettings` / `DeserializeOperatorSettings`)
- Serialized AST and runtime settings can be loaded back and executed by the compiler/engine.
- Operator settings serialization prefers expression-backed operators and stores detailed `JseCsharpOperators` expression nodes in a separate JSON section.
- Non-expression operator bindings are intentionally rejected by serializer to keep replay deterministic.
