const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type PublicationWorkerConfig = {
  servicePrincipalId: string;
  workerDatabaseUrl: string;
  intervalMs: number;
  leaseSeconds: number;
};

export function loadPublicationWorkerConfig(environment: NodeJS.ProcessEnv): PublicationWorkerConfig {
  const servicePrincipalId = environment.PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID;
  if (typeof servicePrincipalId !== "string" || !UUID_PATTERN.test(servicePrincipalId)) {
    throw new Error("publication worker requires PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID");
  }

  const workerDatabaseUrl = environment.PUBLICATION_WORKER_DATABASE_URL;
  if (typeof workerDatabaseUrl !== "string" || workerDatabaseUrl.length === 0) {
    throw new Error("publication worker requires PUBLICATION_WORKER_DATABASE_URL");
  }

  let parsedDatabaseUrl: URL;
  try {
    parsedDatabaseUrl = new URL(workerDatabaseUrl);
  } catch {
    throw new Error("publication worker requires a valid worker database URL");
  }
  if (!["postgres:", "postgresql:"].includes(parsedDatabaseUrl.protocol)) {
    throw new Error("publication worker requires a PostgreSQL worker database URL");
  }

  const configuredInterval = Number.parseInt(environment.PUBLICATION_WORKER_INTERVAL_MS ?? "5000", 10);
  const intervalMs = Math.max(
    1_000,
    Math.min(60_000, Number.isFinite(configuredInterval) ? configuredInterval : 5_000)
  );

  return {
    servicePrincipalId,
    workerDatabaseUrl,
    intervalMs,
    leaseSeconds: Math.min(900, Math.max(30, Math.ceil(intervalMs / 1000) * 3))
  };
}
