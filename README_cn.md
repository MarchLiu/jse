# JSON Structural Expression

JSE（JSON 结构化表达式）是一种基于 JSON 的结构化表达式编码格式。

它将 JSON 从被动的数据表示扩展为可组合、可计算的逻辑表达式的传输媒介。
JSE 使包括 AI 智能体在内的系统，不仅能够传输数据，还可以以确定性且可被机器处理的形式，传达结构化的意图和计算语义。

JSE 的核心在于，充分利用 json 格式的特性，表达出 s 表达式风格的程序逻辑。它的设计考量包含以下几个方面

- JSE 始终是符合语法的 JSON
- JSE 能够表达符合传统的 [s-expression](https://en.wikipedia.org/wiki/S-expression) 
- 利用 JSON 的特性，适当的做一些扩展，利于表达现代软件工程中需要的一些普适的特性，以及 s 表达式中一些不容易表达为 json 结构的内容，例如注释，symbol 和 quote
- 不追求实现图灵完备的 lisp 系统，相反，使用此规范的 AI 或非 AI 软件系统，可以由开发者自己选择实现到何等完备程度，这样我们可以提供一个表达能力足够强大和灵活，又受控于系统机制的表达方式
- 现代的 AI 模型普遍可以稳定可靠的书写 JSON，那么可以利用 JSE 规范，表达出灵活的信息，达成比 Tool Call 和 MCP 更丰富的表达能力
- 控制复杂度，使其便于 AI 书写，也便于人类阅读和编辑。

## 主要设计

- json 规范中，JSON 信息应该总是从一个 JSON 对象开始， JSE 数据也推荐总是以一个 JSON 对象为基础
- 在 JSE 系统中，以 `$` 符号开头的字符串表示是一个有特殊意义的词汇，我们将其视作是 `symbol`。`$` 可以理解为 `Symbol` 或者 `S-Expression` 的开头字母
- 出于普适的考虑，将 `$$` 作为 `$` 的转义字符（Escaped Char），例如 `$expr` 表示 `s-expression`，而 `$$expr` 表示内容为 `"$expr"` 的字符串
- 如果一个字典（JSON Object）的 key 中，仅包含一个以 `$` 开头的 key，其它的 key 都不以 `$` 开头，那么这是一个 s 表达式，其它 key 是这个 s 表达式的元信息（meta data），典型如 lisp 方言 clojure 就支持这种特性，如果没有包含任何以 `$` 开头的 sybmol ，那么它就被视作是一个 JSON 对象
- 如果一个数组（JSON List）的第一个 key 是以 `$` 开头的字符串，那么它是一个朴素的 s 表达式，否则它是一个朴素的 JSON 列表
- `$quote` 表示 LISP 的 `quote`，也就是对其后面的内容不做处理，直接保持原样传递，这对于一些 DSL 非常有用
- 表达数据的字典可能非常大，逐个检查key是否唯一的包含一个 symbol 可能性能代价非常大，可以使用 `$quote` 表达数据，避免不必要的性能开销
- 现代的 AI 模型普遍可以写出符合 json schema 的 json 输出，我们可以在提示词中附带 jse spec，使其可以同 jse 表达精确的复杂逻辑。或者依据 spec 解读 jse 数据。

## 使用方法

我会编写 Python、Typescript 等常规编程语言的示例，提供简单逻辑的数据处理演示。

## 开发

### 环境要求


### 开发环境设置

```bash
# 开发环境配置说明
```

## 贡献指南

欢迎贡献代码！请随时提交 Pull Request。

## 许可证

本项目采用 MIT 许可证 - 详情请查看 [LICENSE](LICENSE) 文件。

## 联系方式

作者：MarsLiu - [@MarchLiu](https://github.com/MarchLiu)

项目地址：[https://github.com/MarchLiu/jse](https://github.com/MarchLiu/jse)
