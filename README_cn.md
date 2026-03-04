# JSON Structural Expression (JSE)

JSON Structural Expression（JSE，JSON 结构化表达式）是一种基于 JSON 的结构化表达式规范。

正如抽象代数中，“群”可以被理解为“集合及其上的运算”，  
**JSE 可以被理解为：施加在 JSON 数据之上的 S 表达式结构规范。**

JSON 提供结构化数据的静态表示；  
JSE 在其之上引入结构化组合语义，使 JSON 从数据载体扩展为可表达结构化意图与计算逻辑的媒介。

---

## 为什么需要 JSE

传统 JSON：

- 适合表示数据
- 不适合表达逻辑结构
- 无法自然表达 S-Expression 风格结构

而现代 AI 模型：

- 可以稳定生成合法 JSON
- 可以遵循 JSON Schema
- 但在表达复杂逻辑结构时通常依赖 Tool Call 或文本协议

JSE 提供一种新的可能性：

- 仍然是合法 JSON
- 却可以表达结构化逻辑
- 可被机器确定性解析
- 可被系统选择性执行
- 控制复杂度，而不追求图灵完备

---

## 核心设计理念

JSE 的设计遵循以下原则：

### 1. 始终是合法 JSON

JSE 数据 **必须是语法正确的 JSON**。

---

### 2. 表达 S-Expression 结构

JSE 能够表达传统的 S-Expression 风格结构，同时保持 JSON 兼容性。

---

### 3. 使用 `$` 表示 Symbol

- 任何以 `$` 开头的字符串被视为 `Symbol`
- `$` 可理解为 `Symbol` 或 `S-Expression` 的首字母

示例：

```json
"$add"
"$if"
"$map"
```

---

### 4. 使用 `$$` 作为转义

为保持字符串表达能力：

* `$$` 表示转义 `$`

规则：

* `$expr` → Symbol
* `$$expr` → 字符串 `"$expr"`

---

### 5. 两种 S-Expression 表达形式

#### （1）数组形式（Positional Form）

如果一个 JSON 数组的第一个元素是以 `$` 开头的字符串，则它是一个 S 表达式：

```json
["$add", 1, 2]
```

否则，它只是普通 JSON 列表。

---

#### （2）对象形式（Named Form）

如果一个 JSON 对象：

* 仅包含一个以 `$` 开头的 key
* 其余 key 不以 `$` 开头

则该对象被视为 S 表达式，其中：

* `$key` 表示操作符
* 其余字段为元信息（meta data）

示例：

```json
{
  "$add": [1, 2],
  "source": "user_input"
}
```

若对象不包含任何 `$` key，则它是普通 JSON 对象。

---

### 6. `$quote`

`$quote` 表示 LISP 风格的 `quote`。

其语义为：

* 对其后内容不做表达式解析
* 保持原样传递

示例：

```json
["$quote", ["$add", 1, 2]]
```

该结构将被视为数据，而非表达式。

---

### 7. 控制复杂度

JSE：

* 不追求构建图灵完备系统
* 不强制定义执行语义
* 仅定义结构表达规范

实现者可以：

* 仅解析结构
* 实现有限操作集合
* 或扩展为 DSL 执行系统

---

## 与 AI 的关系

现代 AI 模型可以：

* 稳定输出 JSON
* 遵循 JSON Schema
* 生成复杂嵌套结构

因此：

* 可以在提示词中附带 JSE 规范
* 让模型生成可被确定性解析的结构逻辑
* 或依据规范解释 JSE 数据

相比 Tool Call 或 MCP 协议，JSE 提供更灵活、组合性更强的表达能力。

---

## 性能考虑

当 JSON 对象规模较大时：

* 检查是否唯一 `$key` 可能存在性能开销

可以使用 `$quote` 避免不必要的表达式检测。

---

## 使用方法

后续将提供：

* Python 示例
* TypeScript 示例
* 简单解释器实现
* JSON Schema 示例

用于演示：

* 结构解析
* 表达式解释
* DSL 扩展

---

## 开发

### 环境要求

（待补充）

### 开发环境设置

```bash
# 开发环境配置说明
```

---

## 贡献指南

欢迎贡献代码与想法。

请通过 Pull Request 提交修改建议。

---

## 许可证

本项目采用 MIT 许可证，详见 `LICENSE` 文件。

---

## 作者

我的名字是刘鑫(Mars Liu or Liu Xin)，曾经在十余年间维护了 Python Tutorial 2.2 到 2.7 的简体中文版翻译。是代数组合子库 Jaskell/pyparsec 系列的作者，2022年出版了《微型 LISP 解释器的构造与实现》一书。现就职于北京中关村学院（ https://bza.edu.cn ）智能创新中心。

MarsLiu
GitHub: [https://github.com/MarchLiu](https://github.com/MarchLiu)

项目地址：
[https://github.com/MarchLiu/jse](https://github.com/MarchLiu/jse)

```


