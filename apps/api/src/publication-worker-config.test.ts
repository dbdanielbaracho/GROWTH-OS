import assert from "node:assert/strict";
import test from "node:test";
import { loadPublicationWorkerConfig } from "./publication-worker-config.js";

const servicePrincipalId = "11111111-1111-4111-8111-111111111111";

test("worker config requires an explicit service principal and PostgreSQL URL", () => {
  assert.throws(
    () => loadPublicationWorkerConfig({ PUBLICATION_WORKER_DATABASE_URL: "postgresql://worker:secret@db.example/growth" }),
    /PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID/
  );
  assert.throws(
    () => loadPublicationWorkerConfig({ PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId }),
    /PUBLICATION_WORKER_DATABASE_URL/
  );
  assert.throws(
    () => loadPublicationWorkerConfig({
      PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
      PUBLICATION_WORKER_DATABASE_URL: "https://not-postgres.example"
    }),
    /PostgreSQL worker database URL/
  );
});

test("worker config clamps polling interval and derives a bounded lease", () => {
  const fast = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: "postgresql://worker:secret@db.example/growth",
    PUBLICATION_WORKER_INTERVAL_MS: "10"
  });
  assert.equal(fast.intervalMs, 1_000);
  assert.equal(fast.leaseSeconds, 30);

  const slow = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: "postgresql://worker:secret@db.example/growth",
    PUBLICATION_WORKER_INTERVAL_MS: "999999"
  });
  assert.equal(slow.intervalMs, 60_000);
  assert.equal(slow.leaseSeconds, 180);
});

test("worker config uses a safe default interval", () => {
  const config = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: "postgres://worker:secret@db.example/growth",
    PUBLICATION_WORKER_INTERVAL_MS: "not-a-number"
  });
  assert.equal(config.intervalMs, 5_000);
  assert.equal(config.leaseSeconds, 30);
});
