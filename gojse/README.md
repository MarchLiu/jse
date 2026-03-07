# gojse

Go implementation of JSE (JSON Structural Expression), consistent with the Python/TypeScript/Java/Rust runtimes in this repository.

## Install

In your `go.mod`:

```bash
go get github.com/MarchLiu/jse/gojse@v0.2.0
```

Then import:

```go
import jse "github.com/MarchLiu/jse/gojse"
```

## Usage

```go
package main

import (
    "fmt"
    "encoding/json"

    jse "github.com/MarchLiu/jse/gojse"
)

func main() {
    engine := jse.NewEngine(jse.ExpressionEnv{})

    // Basic literal
    v, _ := engine.Execute(42)
    fmt.Println(v) // 42

    // Logic expression
    expr := []interface{}{"$and", true, true, false}
    v, _ = engine.Execute(expr)
    fmt.Println(v) // false

    // Query pattern
    var query map[string]interface{}
    _ = json.Unmarshal([]byte(`{
      "$expr": ["$pattern", "$*", "author of", "$*"]
    }`), &query)
    sql, _ := engine.Execute(query)
    fmt.Println(sql) // SQL string
}
```

## Development

```bash
cd gojse
go test ./...
```

## Publishing to Go module proxy

1. Ensure `gojse/go.mod` contains:

   ```txt
   module github.com/MarchLiu/jse/gojse
   ```

2. 在仓库根目录打 tag，例如：

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. 之后用户即可通过：

   ```bash
   go get github.com/MarchLiu/jse/gojse@v0.1.0
   ```

   安装该模块，Go 的 proxy（如 `proxy.golang.org`）会自动从 GitHub 抓取代码和版本信息。

## Repository

<https://github.com/MarchLiu/jse>

## License

MIT

