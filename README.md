# JSON Structural Expression (JSE)

JSON Structural Expression (JSE) is a JSON-based structural expression specification.

Just as in abstract algebra a "group" can be understood as "a set together with an operation on it,"  
**JSE can be understood as: a specification for S-expression structure applied on top of JSON data.**

JSON provides a static representation of structured data;  
JSE adds structured composition semantics on top of it, extending JSON from a data carrier into a medium that can express structured intent and computational logic.

---

## Why JSE

Traditional JSON:

- Suited for representing data
- Not suited for expressing logical structure
- Cannot naturally express S-Expression–style structure

Modern AI models, however:

- Can reliably produce valid JSON
- Can follow JSON Schema
- But when expressing complex logical structure, they often rely on Tool Call or text protocols

JSE offers another possibility:

- Still valid JSON
- Yet able to express structured logic
- Deterministically parseable by machines
- Selectively executable by systems
- Controls complexity without aiming for Turing completeness

---

## Core Design Principles

JSE is designed around the following principles:

### 1. Always Valid JSON

JSE data **must be syntactically valid JSON**.

---

### 2. Express S-Expression Structure

JSE can express traditional S-Expression–style structure while remaining JSON-compatible.

---

### 3. Use `$` for Symbols

- Any string starting with `$` is treated as a **Symbol**
- `$` can be read as the first letter of **S**ymbol or **S**-Expression

Examples:

```json
"$add"
"$if"
"$map"
```

---

### 4. Use `$$` for Escaping

To preserve the ability to represent literal strings:

- `$$` means an escaped `$`

Rules:

- `$expr` → Symbol
- `$$expr` → the string `"$expr"`

---

### 5. Two S-Expression Forms

#### (1) Array form (Positional form)

If the first element of a JSON array is a string starting with `$`, then it is an S-expression:

```json
["$add", 1, 2]
```

Otherwise it is just a plain JSON list.

---

#### (2) Object form (Named form)

If a JSON object:

- Has exactly one key that starts with `$`
- And all other keys do not start with `$`

then that object is treated as an S-expression, where:

- The `$key` is the operator
- The other fields are metadata

Example:

```json
{
  "$add": [1, 2],
  "source": "user_input"
}
```

If the object has no `$` key, it is a plain JSON object.

---

### 6. `$quote`

`$quote` is the LISP-style **quote**.

Its meaning:

- Do not interpret the following content as an expression
- Pass it through as-is

Example:

```json
["$quote", ["$add", 1, 2]]
```

That structure is treated as data, not as an expression.

---

### 7. Controlling Complexity

JSE:

- Does not aim to build a Turing-complete system
- Does not impose a single execution semantics
- Only defines a structural expression specification

Implementations may:

- Only parse structure
- Implement a limited set of operations
- Or extend to a full DSL execution system

---

## Relation to AI

Modern AI models can:

- Output JSON reliably
- Follow JSON Schema
- Produce complex nested structures

Therefore:

- You can attach the JSE specification in your prompts
- Have the model generate structural logic that can be parsed deterministically
- Or interpret JSE data according to the specification

Compared to Tool Call or MCP-style protocols, JSE offers more flexible and compositional expressiveness.

---

## Performance Considerations

When JSON objects are large:

- Checking for a unique `$` key may have a performance cost

You can use `$quote` to avoid unnecessary expression detection.

---

## Usage

### Installation

Implementations are available in several languages:

- **Python**: `pyjse`
- **TypeScript/JavaScript**: `jse-engine`
- **Java**: `jse4j`
- **Rust**: `jse`

#### Python (PyPI)

```bash
pip install pyjse
```

#### TypeScript / JavaScript (npm)

```bash
npm install jse-engine
```

#### Java (Maven Central)

Maven:

```xml
<dependency>
  <groupId>io.github.marchliu</groupId>
  <artifactId>jse4j</artifactId>
  <version>0.1.0</version>
</dependency>
```

Gradle Groovy:

```groovy
implementation 'io.github.marchliu:jse4j:0.1.0'
```

Gradle Kotlin:

```kotlin
implementation("io.github.marchliu:jse4j:0.1.0")
```

#### Rust (crates.io)

```toml
[dependencies]
jse = "0.1"
```

### Examples and Implementations

This repository includes:

- Python examples and interpreter: `python/pyjse`
- TypeScript examples and interpreter: `typescript/`
- Java examples and interpreter: `java/`
- Rust library: `rust/`
- Further additions (e.g. JSON Schema, more complex DSL examples) may follow

---

## Development

### Requirements

(To be added)

### Setup

```bash
# Development setup instructions
```

---

## Contributing

Contributions of code and ideas are welcome.

Please submit changes via Pull Request.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## Author

Liu Xin (Mars Liu) &lt;mars.liu@outlook.com&gt; maintained the Simplified Chinese translation of the Python Tutorial from 2.2 through 2.7 for over a decade. Author of the Jaskell/pyparsec family of algebraic combinator libraries and of the book *Construction and Implementation of a Mini LISP Interpreter* (2022). Currently at the Intelligent Innovation Center, Beijing Zhongguancun College ([bza.edu.cn](https://bza.edu.cn)).

- GitHub: [MarchLiu](https://github.com/MarchLiu)
- Project: [https://github.com/MarchLiu/jse](https://github.com/MarchLiu/jse)
