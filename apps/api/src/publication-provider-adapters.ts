import {
  buildInstagramContainerRequest,
  buildInstagramPublishRequest,
  buildYoutubeVideoInsertRequest,
  type InstagramContainerInput,
  type YoutubeVideoInsertInput
} from "./publication-provider-requests.js";
import {
  preparePublicationProviderResult,
  PublicationProviderError,
  type PublicationProviderResult
} from "./publication-execution.js";

export type PublicationFetch = typeof fetch;

function responseRequestId(response: Response): string | null {
  return response.headers.get("x-request-id")
    ?? response.headers.get("x-fb-trace-id")
    ?? response.headers.get("x-guploader-uploadid");
}

async function responsePayload(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text.trim()) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return { non_json_response: true };
  }
}

async function requireSuccessfulResponse(
  response: Response,
  provider: "instagram" | "youtube",
  operation: string
): Promise<unknown> {
  await responsePayload(response);
  if (!response.ok) {
    throw new PublicationProviderError(
      response.status,
      responseRequestId(response),
      `${provider} ${operation} request failed`
    );
  }
  return null;
}

function payloadString(payload: unknown, key: string): string | null {
  if (!payload || typeof payload !== "object") return null;
  const value = (payload as Record<string, unknown>)[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function isAllowedYoutubeUploadLocation(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:"
      && ["www.googleapis.com", "youtube.googleapis.com"].includes(url.hostname)
      && url.pathname.startsWith("/upload/youtube/v3/videos");
  } catch {
    return false;
  }
}

export type InstagramPublicationInput = InstagramContainerInput & {
  fetchImpl?: PublicationFetch;
};

export async function publishInstagram(
  input: InstagramPublicationInput
): Promise<PublicationProviderResult> {
  const { fetchImpl = fetch, ...requestInput } = input;
  const containerRequest = buildInstagramContainerRequest(requestInput);
  const containerResponse = await fetchImpl(containerRequest.url, containerRequest);
  const containerPayload = await responsePayload(containerResponse);
  if (!containerResponse.ok) {
    throw new PublicationProviderError(
      containerResponse.status,
      responseRequestId(containerResponse),
      "instagram media container request failed"
    );
  }
  const creationId = payloadString(containerPayload, "id");
  if (!creationId) {
    throw new PublicationProviderError(
      502,
      responseRequestId(containerResponse),
      "instagram media container response missing creation id"
    );
  }

  const publishRequest = buildInstagramPublishRequest({
    apiVersion: requestInput.apiVersion,
    providerAccountId: requestInput.providerAccountId,
    accessToken: requestInput.accessToken,
    creationId
  });
  const publishResponse = await fetchImpl(publishRequest.url, publishRequest);
  const publishPayload = await responsePayload(publishResponse);
  if (!publishResponse.ok) {
    throw new PublicationProviderError(
      publishResponse.status,
      responseRequestId(publishResponse),
      "instagram media publish request failed"
    );
  }
  const providerContentId = payloadString(publishPayload, "id");
  if (!providerContentId) {
    throw new PublicationProviderError(
      502,
      responseRequestId(publishResponse),
      "instagram publish response missing provider content id"
    );
  }

  return preparePublicationProviderResult({
    httpStatus: publishResponse.status,
    providerRequestId: responseRequestId(publishResponse)
      ?? responseRequestId(containerResponse),
    providerContentId,
    rawPayload: {
      container_status: containerResponse.status,
      publish_status: publishResponse.status
    }
  });
}

export type YoutubeVideoPublicationInput = YoutubeVideoInsertInput & {
  mediaBody: Uint8Array;
  fetchImpl?: PublicationFetch;
};

export async function publishYoutubeVideo(
  input: YoutubeVideoPublicationInput
): Promise<PublicationProviderResult> {
  const { fetchImpl = fetch, mediaBody, ...requestInput } = input;
  const parsedBytes = Number(requestInput.bytes);
  if (mediaBody.byteLength !== parsedBytes) {
    throw new PublicationProviderError(
      400,
      null,
      "youtube media body length does not match declared bytes"
    );
  }

  const initiationRequest = buildYoutubeVideoInsertRequest(requestInput);
  const initiationResponse = await fetchImpl(initiationRequest.url, initiationRequest);
  await requireSuccessfulResponse(initiationResponse, "youtube", "resumable initiation");

  const uploadLocation = initiationResponse.headers.get("location");
  if (!uploadLocation || !isAllowedYoutubeUploadLocation(uploadLocation)) {
    throw new PublicationProviderError(
      502,
      responseRequestId(initiationResponse),
      "youtube resumable initiation returned an invalid upload location"
    );
  }

  const uploadResponse = await fetchImpl(uploadLocation, {
    method: "PUT",
    headers: {
      authorization: `Bearer ${requestInput.accessToken}`,
      "content-type": requestInput.mimeType,
      "content-length": String(requestInput.bytes)
    },
    body: Buffer.from(mediaBody)
  });
  const uploadPayload = await responsePayload(uploadResponse);
  if (!uploadResponse.ok) {
    throw new PublicationProviderError(
      uploadResponse.status,
      responseRequestId(uploadResponse)
        ?? responseRequestId(initiationResponse),
      "youtube video upload request failed"
    );
  }
  const providerContentId = payloadString(uploadPayload, "id");
  if (!providerContentId) {
    throw new PublicationProviderError(
      502,
      responseRequestId(uploadResponse)
        ?? responseRequestId(initiationResponse),
      "youtube upload response missing provider content id"
    );
  }

  return preparePublicationProviderResult({
    httpStatus: uploadResponse.status,
    providerRequestId: responseRequestId(uploadResponse)
      ?? responseRequestId(initiationResponse),
    providerContentId,
    rawPayload: {
      initiation_status: initiationResponse.status,
      upload_status: uploadResponse.status
    }
  });
}
