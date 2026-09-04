import { z } from "zod";

const RawEnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),

  APP_ORIGIN: z.string().url().optional(),
  CSRF_SECRET: z.string().min(32).optional(),

  SESSION_ABSOLUTE_TTL_SECONDS: z.coerce.number().int().min(3600).max(60 * 60 * 24 * 90).default(60 * 60 * 24 * 30),
  SESSION_IDLE_TTL_SECONDS: z.coerce.number().int().min(300).max(60 * 60 * 24 * 30).default(60 * 60 * 24),

  LOGIN_RATE_WINDOW_SECONDS: z.coerce.number().int().min(60).max(60 * 60 * 24).default(15 * 60),
  LOGIN_MAX_EMAIL_FAILURES: z.coerce.number().int().min(1).max(1000).default(5),
  LOGIN_MAX_IP_FAILURES: z.coerce.number().int().min(1).max(10000).default(50),

  ARGON2_MEMORY_COST_KIB: z.coerce.number().int().min(19_456).max(1_048_576).default(19_456),
  ARGON2_TIME_COST: z.coerce.number().int().min(2).max(20).default(2),
  ARGON2_PARALLELISM: z.coerce.number().int().min(1).max(16).default(1),
  ARGON2_HASH_LENGTH: z.coerce.number().int().min(16).max(128).default(32)
}).superRefine((value, ctx) => {
  if (value.SESSION_IDLE_TTL_SECONDS > value.SESSION_ABSOLUTE_TTL_SECONDS) {
    ctx.addIssue({
      code: "custom",
      path: ["SESSION_IDLE_TTL_SECONDS"],
      message: "idle session TTL cannot exceed absolute session TTL"
    });
  }

  if (value.NODE_ENV === "production") {
    if (!value.APP_ORIGIN) {
      ctx.addIssue({ code: "custom", path: ["APP_ORIGIN"], message: "APP_ORIGIN is required in production" });
    } else {
      const origin = new URL(value.APP_ORIGIN);
      if (origin.protocol !== "https:") {
        ctx.addIssue({ code: "custom", path: ["APP_ORIGIN"], message: "APP_ORIGIN must use HTTPS in production" });
      }
      if (
        origin.pathname !== "/"
        || origin.search !== ""
        || origin.hash !== ""
        || origin.username !== ""
        || origin.password !== ""
      ) {
        ctx.addIssue({
          code: "custom",
          path: ["APP_ORIGIN"],
          message: "APP_ORIGIN must be an origin only (scheme + host + optional port), with no path, query, fragment, or credentials"
        });
      }
    }
    if (!value.CSRF_SECRET) {
      ctx.addIssue({ code: "custom", path: ["CSRF_SECRET"], message: "CSRF_SECRET is required in production" });
    }
  }
});

const parsed = RawEnvSchema.parse(process.env);

export const env = {
  ...parsed,
  APP_ORIGIN: parsed.APP_ORIGIN ?? "http://localhost:5173",
  CSRF_SECRET: parsed.CSRF_SECRET ?? "development-only-csrf-secret-change-before-production"
};
