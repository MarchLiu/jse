import { describe, it, expect } from "vitest";
import { Engine, Env, SQL_FUNCTORS } from "../index.js";

function createEngine() {
  const env = new Env();
  env.load(SQL_FUNCTORS);
  return new Engine(env);
}

function execute(engine: Engine, expr: unknown): string {
  return engine.execute(expr) as string;
}

describe("$sql functor", () => {
  const engine = createEngine();

  it("basic select from", () => {
    const sql = execute(engine, {
      $sql: [["$select", "$name", "$age"], ["$from", "$users"]],
    });
    expect(sql).toContain("select name, age");
    expect(sql).toContain("from users");
  });

  it("nested AND/OR", () => {
    const sql = execute(engine, {
      $sql: [
        ["$select", "$name", "$age"],
        ["$from", "$users"],
        ["$where", ["$and",
          ["$gt", "$age", 18],
          ["$or", ["$eq", "$status", "active"], ["$eq", "$role", "admin"]],
        ]],
      ],
    });
    expect(sql).toContain("age > 18");
    expect(sql).toContain("status = 'active'");
    expect(sql).toContain("role = 'admin'");
  });

  it("JOIN with alias", () => {
    const sql = execute(engine, {
      $sql: [
        ["$select", "$u.name", "$o.total"],
        ["$from", ["$as", "$users", "$u"]],
        ["$join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
        ["$where", ["$gt", "$o.total", 100]],
      ],
    });
    expect(sql).toContain("users as u");
    expect(sql).toContain("join orders as o");
    expect(sql).toContain("u.id = o.user_id");
  });

  it("LEFT JOIN + NULL", () => {
    const sql = execute(engine, {
      $sql: [
        ["$select", "$u.name", "$o.total"],
        ["$from", ["$as", "$users", "$u"]],
        ["$left-join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
        ["$where", ["$is", "$o.total", null]],
      ],
    });
    expect(sql).toContain("left join");
    expect(sql).toContain("o.total is null");
  });

  it("INSERT", () => {
    const sql = execute(engine, {
      $sql: [
        ["$insert-into", "$users", "$name", "$age", "$email"],
        ["$values", "Alice", 30, "alice@example.com"],
      ],
    });
    expect(sql).toContain("insert into users");
    expect(sql).toContain("values");
    expect(sql).toContain("'Alice'");
  });

  it("DELETE", () => {
    const sql = execute(engine, {
      $sql: [
        ["$delete-from", "$sessions"],
        ["$where", ["$lt", "$expired_at", "2024-01-01"]],
      ],
    });
    expect(sql).toContain("delete from sessions");
    expect(sql).toContain("expired_at < '2024-01-01'");
  });

  it("UPDATE", () => {
    const sql = execute(engine, {
      $sql: [
        ["$update", "$users"],
        ["$set", { $age: 31, $status: "active" }],
        ["$where", ["$eq", "$id", 42]],
      ],
    });
    expect(sql).toContain("update users");
    expect(sql).toContain("age = 31");
    expect(sql).toContain("id = 42");
  });

  it("$$ escape, null, boolean", () => {
    const sql = execute(engine, {
      $sql: [
        ["$select", "$name", "$sku"],
        ["$from", "$products"],
        ["$where", ["$and",
          ["$like", "$sku", "$$PROMO-%"],
          ["$is-not", "$deleted_at", null],
          ["$eq", "$is_active", true],
        ]],
      ],
    });
    expect(sql).toContain("sku like '$PROMO-%'");
    expect(sql).toContain("deleted_at is not null");
    expect(sql).toContain("is_active = true");
  });

  it("GROUP BY + aggregates", () => {
    const sql = execute(engine, {
      $sql: [
        ["$select", "$category",
          ["$as", ["$count", "$*"], "$cnt"],
          ["$as", ["$avg", "$price"], "$avg_price"],
        ],
        ["$from", "$products"],
        ["$group-by", "$category"],
        ["$order-by", "$avg_price", "$desc"],
        ["$limit", 50],
      ],
    });
    expect(sql).toContain("group by category");
    expect(sql).toContain("count(*)");
    expect(sql).toContain("order by avg_price desc");
    expect(sql).toContain("limit 50");
  });

  it("CROSS JOIN", () => {
    const sql = execute(engine, {
      $sql: [
        ["$select", "$u.name", "$d.dept_name"],
        ["$from", ["$as", "$users", "$u"]],
        ["$cross-join", ["$as", "$departments", "$d"]],
      ],
    });
    expect(sql).toContain("cross join departments as d");
  });
});
