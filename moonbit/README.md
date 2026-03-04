# jse (MoonBit)

MoonBit implementation of JSON Structural Expression (JSE), sharing the same semantics as the Python / TypeScript / Java / Rust / Go runtimes in this repository.

## 安装（使用 Moon 包管理）

在你的 MoonBit 项目根目录下执行：

```bash
moon add marchliu/jse
```

然后在需要使用的包中，在 `moon.pkg` 中加入：

```moon
import {
  "marchliu/jse/jse",
}
```

## 使用示例

```moon
import {
  "moonbitlang/core/json",
  "marchliu/jse/jse" @jse,
}

fn main {
  let expr : Json = ["$and", true, true, false].to_json()
  let result = jse::eval(expr)
  // result == False
}
```

## 发布到 mooncakes.io

在 `moonbit/` 目录下已经配置好 `moon.mod.json`：

```json
{
  "name": "marchliu/jse",
  "version": "0.1.0",
  "readme": "README.md",
  "repository": "https://github.com/MarchLiu/jse",
  "license": "MIT",
  "source": "src"
}
```

发布步骤（需先在 Moon 官方注册并登录）：

```bash
cd moonbit
moon login        # 如有需要
moon publish
```

发布成功后，其他项目即可通过 `moon add marchliu/jse` 引入该模块。

