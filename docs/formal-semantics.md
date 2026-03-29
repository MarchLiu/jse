这是一份**结构层语义**，不涉及执行语义（因为 JSE 不强制定义执行）。

---

# JSE 形式化语义定义

Version 0.1 (Structural Layer)

---

# 1. 基础集合定义

设：

* 𝑱 为所有合法 JSON 值的集合
* 𝑺 为所有 Symbol 的集合
* 𝑬 为所有 JSE 表达式的集合
* 𝑫 为普通 JSON 数据的集合

---

## 1.1 JSON 值定义

JSON 值定义为：

```
J ::= 
      null
    | boolean
    | number
    | string
    | array(J*)
    | object({ string : J }*)
```

其中：

* `array(J*)` 表示有限序列
* `object({k : v}*)` 表示有限键值映射

---

# 2. Symbol 定义

定义 Symbol 判定函数：

```
isSymbol : string → boolean
```

满足：

```
isSymbol(s) ⇔
    s 以 "$" 开头
    ∧ s 不以 "$$" 开头
```

定义转义函数：

```
unescape : string → string
```

```
unescape("$$" + x) = "$" + x
unescape(s) = s (otherwise)
```

定义：

```
S = { s ∈ string | isSymbol(s) }
```

---

# 3. JSE 表达式抽象语法

JSE 表达式定义为：

```
E ::= 
      Data
    | ArrayExpr
    | ObjectExpr
```

其中：

---

## 3.1 Data

```
Data ::= 
      null
    | boolean
    | number
    | string
    | array(E*)
    | object({ string : E }*)
```

但 Data 不满足表达式判定规则。

---

## 3.2 Array Expression

```
ArrayExpr ::= array( s, E* )
```

满足：

* s ∈ S

形式上：

```
ArrayExpr(V) ⇔
    V = [v₀, v₁, ..., vₙ]
    ∧ v₀ ∈ S
```

---

## 3.3 Object Expression

```
ObjectExpr ::= object({ s : E, k₁ : E₁, ..., kₙ : Eₙ })
```

满足：

* s ∈ S
* 且对象中恰好存在一个 Symbol key

形式定义：

```
ObjectExpr(V) ⇔
    V = {k₁: v₁, ..., kₙ: vₙ}
    ∧ |{ kᵢ | isSymbol(kᵢ) }| = 1
```

---

# 4. 结构解析函数

定义结构解析函数：

```
parse : J → E
```

其定义如下：

---

## 4.1 原子值

```
parse(null) = null
parse(boolean) = boolean
parse(number) = number
```

字符串：

```
parse(s) =
    if s 以 "$$" 开头:
        unescape(s)
    else if isSymbol(s) ∧ s ≠ "$*":
        Symbol(s)
    else:
        s
```

注意：

`$*` 保持为通配字面量，不作为 Symbol；
其他以 `$` 开头且非 `$$` 的字符串可解析为 Symbol。

---

## 4.2 数组

设：

```
V = [v₀, v₁, ..., vₙ]
```

则：

```
parse(V) =
    if isSymbol(v₀):
        ArrayExpr( v₀, parse(v₁), ..., parse(vₙ) )
    else:
        array( parse(v₀), ..., parse(vₙ) )
```

---

## 4.3 对象

设：

```
V = {k₁: v₁, ..., kₙ: vₙ}
```

定义：

```
SymbolKeys = { kᵢ | isSymbol(kᵢ) }
```

则：

### 情况 1：|SymbolKeys| = 0

```
parse(V) = object({ kᵢ : parse(vᵢ) })
```

---

### 情况 2：|SymbolKeys| = 1

设唯一 Symbol key 为 `s`

则：

```
parse(V) =
    ObjectExpr(
        s,
        parse(V[s]),
        metadata = { k ≠ s : parse(V[k]) }
    )
```

---

### 情况 3：|SymbolKeys| > 1

```
parse(V) = error("JSE_STRUCTURE_ERROR")
```

---

# 5. Quote 语义

定义特殊 Symbol：

```
"$quote"
```

扩展 parse 规则：

若：

```
V = ["$quote", x]
```

则：

```
parse(V) = Quote(x)
```

且：

```
Quote(x) = x
```

其中：

* 不递归调用 parse(x)
* 保持原始 JSON 结构

对象形式：

```
{ "$quote": x }
```

同理适用。

---

# 6. 规范化语义（Normalization）

定义规范化函数：

```
normalize : E → Canonical Form
```

规则：

* 所有 ObjectExpr 转换为 ArrayExpr 形式：

```
{ "$add": [1,2], "source":"a" }
```

规范化为：

```
("$add" [1,2])
```

并保留 metadata 结构。

此规则确保：

> 每个表达式具有唯一结构表示。

---

# 7. 不变量（Structural Invariants）

对任意合法 JSE 表达式 E：

1. E ∈ JSON
2. ObjectExpr 中 Symbol key 唯一
3. ArrayExpr 的 head 必为 Symbol
4. Quote 内部不递归解析
5. 解析是确定性的

---

# 8. 非目标

本语义：

* 不定义执行语义
* 不定义求值规则
* 不定义操作符集合
* 不保证可计算性

它仅定义：

> 如何从 JSON 结构中确定性识别表达式结构。

---

# 9. 形式总结

可以形式化地描述为：

```
JSE = (J, parse)
```

其中：

* J 为 JSON 值集合
* parse 为确定性结构解释函数

类比抽象代数：

> JSON 是集合
> parse 引入表达结构
> JSE 是 JSON 上施加的结构化语义层

