export const MAX_PUBLICATION_RETRIES = 5;
const RETRY_BASE_DELAY_MS = 60_000;
const RETRY_MAX_DELAY_MS = 30 * 60_000;

export function publicationRetryDelayMs(retryCount: number): number {
  const normalized = Math.max(0, Math.min(Math.floor(retryCount), MAX_PUBLICATION_RETRIES));
  return Math.min(RETRY_BASE_DELAY_MS * (2 ** normalized), RETRY_MAX_DELAY_MS);
}

export function nextPublicationRetryAt(
  now: Date,
  retryCount: number
): Date {
  return new Date(now.getTime() + publicationRetryDelayMs(retryCount));
}
