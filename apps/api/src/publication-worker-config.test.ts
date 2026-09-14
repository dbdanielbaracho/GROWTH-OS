import assert from "node:assert/strict";
import test from "node:test";
import { loadPublicationWorkerConfig } from "./publication-worker-config.js";

const servicePrincipalId = "11111111-1111-4111-8111-111111111111";
const workerDatabaseUrl = "postgresql://worker:secret@db.example/growth";

test("worker config requires an explicit service principal and PostgreSQL URL", () => {
  assert.throws(
    () => loadPublicationWorkerConfig({ PUBLICATION_WORKER_DATABASE_URL: workerDatabaseUrl }),
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
    PUBLICATION_WORKER_DATABASE_URL: workerDatabaseUrl,
    PUBLICATION_WORKER_INTERVAL_MS: "10"
  });
  assert.equal(fast.intervalMs, 1_000);
  assert.equal(fast.leaseSeconds, 30);

  const slow = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: workerDatabaseUrl,
    PUBLICATION_WORKER_INTERVAL_MS: "999999"
  });
  assert.equal(slow.intervalMs, 60_000);
  assert.equal(slow.leaseSeconds, 180);
});

test("worker config uses safe defaults", () => {
  const config = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: "postgres://worker:secret@db.example/growth",
    PUBLICATION_WORKER_INTERVAL_MS: "not-a-number",
    PUBLICATION_WORKER_MAX_ATTEMPTS: "not-a-number"
  });
  assert.equal(config.intervalMs, 5_000);
  assert.equal(config.leaseSeconds, 30);
  assert.equal(config.maxAttempts, 5);
});

test("worker config clamps dead-letter attempt limits", () => {
  const minimum = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: workerDatabaseUrl,
    PUBLICATION_WORKER_MAX_ATTEMPTS: "0"
  });
  assert.equal(minimum.maxAttempts, 1);

  const maximum = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: workerDatabaseUrl,
    PUBLICATION_WORKER_MAX_ATTEMPTS: "999"
  });
  assert.equal(maximum.maxAttempts, 20);

  const configured = loadPublicationWorkerConfig({
    PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID: servicePrincipalId,
    PUBLICATION_WORKER_DATABASE_URL: workerDatabaseUrl,
    PUBLICATION_WORKER_MAX_ATTEMPTS: "7"
  });
  assert.equal(configured.maxAttempts, 7);
});
