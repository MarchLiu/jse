/**
 * Tests for meta mechanism in JSE.
 *
 * Meta mechanism allows passing additional metadata to functors through the
 * environment. When an expression like {"$operator": value, "meta_key": meta_value}
 * is evaluated, the metadata is set in the environment before the functor is called,
 * and cleared after the functor returns.
 */

import { describe, it, expect, beforeEach } from "vitest";
import { Engine, Env } from "../index.js";
import type { JseValue, Functor } from "../types.js";

// Helper to evaluate meta values (which might be AST nodes)
function evalMetaValue(env: Env, value: JseValue): JseValue {
  if (typeof value === "object" && value !== null && "apply" in value) {
    return env.eval(value);
  }
  return value;
}

// A functor that returns the current metadata from the environment
const getMeta: Functor = (env: Env) => {
  const meta = env.getMeta();
  // Evaluate all meta values
  const result: Record<string, JseValue> = {};
  for (const [k, v] of Object.entries(meta)) {
    result[k] = evalMetaValue(env, v);
  }
  return result;
};

// A functor that returns a specific key from metadata
const getMetaKey: Functor = (env: Env, ...args: JseValue[]) => {
  if (args.length === 0) {
    return null;
  }
  const key = args[0] as string;
  const meta = env.getMeta();
  if (meta === undefined || Object.keys(meta).length === 0) {
    return null;
  }
  const value = meta[key];
  return evalMetaValue(env, value);
};

// A functor that returns all metadata plus arguments
const metaWithArgs: Functor = (env: Env, ...args: JseValue[]) => {
  const meta = env.getMeta();
  const result: Record<string, JseValue> = {
    meta: {},
    args: args,
  };
  for (const [k, v] of Object.entries(meta)) {
    (result.meta as Record<string, JseValue>)[k] = evalMetaValue(env, v);
  }
  return result;
};

// Store for side effect testing
let lastMeta: Record<string, JseValue> | null = null;

// A functor that stores meta and returns the argument unchanged
const identityWithMeta: Functor = (env: Env, ...args: JseValue[]) => {
  const meta = env.getMeta();
  lastMeta = {};
  for (const [k, v] of Object.entries(meta)) {
    lastMeta[k] = evalMetaValue(env, v);
  }
  if (args.length > 0) {
    return evalMetaValue(env, args[0]);
  }
  return null;
};

function createEngineWithMetaFunctors(): Engine {
  const env = new Env();
  env.register("$get_meta", getMeta);
  env.register("$get_meta_key", getMetaKey);
  env.register("$meta_with_args", metaWithArgs);
  env.register("$identity", identityWithMeta);
  return new Engine(env);
}

describe("meta mechanism", () => {
  let engine: Engine;

  beforeEach(() => {
    engine = createEngineWithMetaFunctors();
    lastMeta = null;
  });

  describe("basic meta passing", () => {
    it("should pass metadata to functor", () => {
      const expr = {
        "$get_meta": null,
        key1: "value1",
        key2: 42,
      };
      const result = engine.execute(expr) as Record<string, JseValue>;

      expect(result).toHaveProperty("key1");
      expect(result).toHaveProperty("key2");
    });

    it("should pass string metadata values correctly", () => {
      const expr = {
        "$get_meta_key": "name",
        name: "test_value",
      };
      const result = engine.execute(expr);
      expect(result).toBe("test_value");
    });

    it("should pass numeric metadata values correctly", () => {
      const expr = {
        "$get_meta_key": "count",
        count: 123,
      };
      const result = engine.execute(expr);
      expect(result).toBe(123);
    });
  });

  describe("multiple metadata keys", () => {
    it("should handle multiple metadata keys", () => {
      const expr = {
        "$get_meta": null,
        first: "one",
        second: "two",
        third: 3,
      };
      const result = engine.execute(expr) as Record<string, JseValue>;

      expect(result["first"]).toBe("one");
      expect(result["second"]).toBe("two");
      expect(result["third"]).toBe(3);
    });
  });

  describe("meta with arguments", () => {
    it("should make both metadata and arguments available", () => {
      const expr = {
        "$meta_with_args": ["arg1", "arg2"],
        meta_key: "meta_value",
      };
      const result = engine.execute(expr) as Record<string, JseValue>;

      expect(result).toHaveProperty("meta");
      expect(result).toHaveProperty("args");
      expect((result["meta"] as Record<string, JseValue>)["meta_key"]).toBe("meta_value");
    });
  });

  describe("meta lifecycle", () => {
    it("should clear metadata after functor returns", () => {
      // First call with metadata
      const expr1 = {
        "$get_meta": null,
        temp_key: "temp_value",
      };
      const result1 = engine.execute(expr1) as Record<string, JseValue>;
      expect(result1).toHaveProperty("temp_key");

      // Second call without metadata - should return empty object
      const expr2 = { "$get_meta": null };
      const result2 = engine.execute(expr2) as Record<string, JseValue>;
      expect(Object.keys(result2)).toHaveLength(0);
    });

    it("should have meta available during functor execution", () => {
      const expr = {
        "$identity": "return_value",
        stored_key: "stored_value",
      };
      const result = engine.execute(expr);

      // The result should be the argument
      expect(result).toBe("return_value");

      // But the functor should have captured the meta
      expect(lastMeta).not.toBeNull();
      expect(lastMeta!["stored_key"]).toBe("stored_value");
    });
  });

  describe("metadata value types", () => {
    it("should handle object metadata values", () => {
      const expr = {
        "$get_meta_key": "config",
        config: { nested: "value", number: 42 },
      };
      const result = engine.execute(expr) as Record<string, JseValue>;
      expect(result).toEqual({ nested: "value", number: 42 });
    });

    it("should handle list metadata values", () => {
      const expr = {
        "$get_meta_key": "items",
        items: [1, 2, 3],
      };
      const result = engine.execute(expr);
      expect(result).toEqual([1, 2, 3]);
    });

    it("should handle null metadata values", () => {
      const expr = {
        "$get_meta_key": "nullable",
        nullable: null,
      };
      const result = engine.execute(expr);
      expect(result).toBeNull();
    });

    it("should handle boolean true metadata values", () => {
      const expr = {
        "$get_meta_key": "flag",
        flag: true,
      };
      const result = engine.execute(expr);
      expect(result).toBe(true);
    });

    it("should handle boolean false metadata values", () => {
      const expr = {
        "$get_meta_key": "flag",
        flag: false,
      };
      const result = engine.execute(expr);
      expect(result).toBe(false);
    });

    it("should handle nested list metadata values", () => {
      const expr = {
        "$get_meta_key": "nested",
        nested: [[1, 2], [3, 4]],
      };
      const result = engine.execute(expr);
      expect(result).toEqual([[1, 2], [3, 4]]);
    });

    it("should handle complex nested object metadata", () => {
      const expr = {
        "$get_meta_key": "complex",
        complex: {
          level1: {
            level2: "deep_value",
          },
          array: [1, 2, 3],
        },
      };
      const result = engine.execute(expr) as Record<string, JseValue>;
      expect((result["level1"] as Record<string, JseValue>)["level2"]).toBe("deep_value");
      expect(result["array"]).toEqual([1, 2, 3]);
    });
  });

  describe("missing metadata", () => {
    it("should return null for missing metadata key", () => {
      const expr = {
        "$get_meta_key": "nonexistent",
      };
      const result = engine.execute(expr);
      expect(result).toBeNull();
    });
  });
});
