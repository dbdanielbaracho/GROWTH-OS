import assert from "node:assert/strict";
import test from "node:test";
import {
  publishInstagram,
  publishYoutubeVideo,
  type PublicationFetch
} from "./publication-provider-adapters.js";

function jsonResponse(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers }
  });
}

test("Instagram adapter creates a container and then publishes it without leaking the token", async () => {
  const token = "instagram-secret-token";
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetchImpl: PublicationFetch = async (input, init) => {
    calls.push({ url: String(input), init });
    return calls.length === 1
      ? jsonResponse(200, { id: "container-123" }, { "x-fb-trace-id": "trace-1" })
      : jsonResponse(200, { id: "published-456" }, { "x-fb-trace-id": "trace-2" });
  };

  const result = await publishInstagram({
    apiVersion: "v24.0",
    providerAccountId: "17890000000000000",
    accessToken: token,
    mediaKind: "image",
    mediaUrl: "https://cdn.example.com/post.jpg",
    caption: "A real post",
    fetchImpl
  });

  assert.equal(result.outcome, "confirmed");
  assert.equal(result.providerContentId, "published-456");
  assert.equal(calls.length, 2);
  assert.equal(calls[0]?.init?.method, "POST");
  assert.equal(calls[1]?.init?.method, "POST");
  assert.match(calls[0]?.url ?? "", /\/media$/);
  assert.match(calls[1]?.url ?? "", /\/media_publish$/);
  assert.equal(calls[0]?.url.includes(token), false);
  assert.equal(String(calls[0]?.init?.body).includes(token), false);
  assert.equal(String(calls[1]?.init?.body).includes(token), false);
  assert.equal((calls[0]?.init?.headers as Record<string, string>).authorization, `Bearer ${token}`);
});

test("Instagram adapter preserves provider HTTP classification for authorization errors", async () => {
  const fetchImpl: PublicationFetch = async () =>
    jsonResponse(403, { error: { message: "denied" } }, { "x-fb-trace-id": "trace-denied" });

  await assert.rejects(
    publishInstagram({
      apiVersion: "v24.0",
      providerAccountId: "17890000000000000",
      accessToken: "token",
      mediaKind: "image",
      mediaUrl: "https://cdn.example.com/post.jpg",
      fetchImpl
    }),
    (error: unknown) =>
      error instanceof Error
      && error.name === "PublicationProviderError"
      && (error as { httpStatus?: number }).httpStatus === 403
      && (error as { providerRequestId?: string }).providerRequestId === "trace-denied"
  );
});

test("YouTube adapter completes resumable initiation and upload with a secure location", async () => {
  const token = "youtube-secret-token";
  const bytes = Buffer.from("video-bytes");
  const uploadLocation = "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=session-123";
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetchImpl: PublicationFetch = async (input, init) => {
    calls.push({ url: String(input), init });
    return calls.length === 1
      ? new Response(null, {
        status: 200,
        headers: { location: uploadLocation, "x-guploader-uploadid": "upload-123" }
      })
      : jsonResponse(200, { id: "youtube-video-789" }, { "x-guploader-uploadid": "upload-123" });
  };

  const result = await publishYoutubeVideo({
    accessToken: token,
    mimeType: "video/mp4",
    bytes: bytes.length,
    title: "Private test video",
    description: "No public release",
    mediaBody: bytes,
    fetchImpl
  });

  assert.equal(result.outcome, "confirmed");
  assert.equal(result.providerContentId, "youtube-video-789");
  assert.equal(calls.length, 2);
  assert.equal(calls[0]?.init?.method, "POST");
  assert.equal(calls[1]?.url, uploadLocation);
  assert.equal(calls[1]?.init?.method, "PUT");
  assert.equal(String(calls[0]?.init?.body).includes(token), false);
  assert.equal(String(calls[1]?.init?.body).includes(token), false);
  assert.equal((calls[1]?.init?.headers as Record<string, string>).authorization, `Bearer ${token}`);
  assert.equal((calls[1]?.init?.headers as Record<string, string>)["content-length"], String(bytes.length));
});

test("YouTube adapter rejects provider-controlled upload locations outside Google", async () => {
  const fetchImpl: PublicationFetch = async () =>
    new Response(null, {
      status: 200,
      headers: { location: "https://attacker.example/upload/youtube/v3/videos?upload_id=x" }
    });

  await assert.rejects(
    publishYoutubeVideo({
      accessToken: "token",
      mimeType: "video/mp4",
      bytes: 1,
      title: "Test",
      mediaBody: Uint8Array.from([1]),
      fetchImpl
    }),
    (error: unknown) =>
      error instanceof Error
      && error.name === "PublicationProviderError"
      && (error as { httpStatus?: number }).httpStatus === 502
  );
});

test("YouTube adapter rejects mismatched media byte counts before any provider call", async () => {
  let calls = 0;
  const fetchImpl: PublicationFetch = async () => {
    calls += 1;
    return jsonResponse(500, {});
  };

  await assert.rejects(
    publishYoutubeVideo({
      accessToken: "token",
      mimeType: "video/mp4",
      bytes: 2,
      title: "Test",
      mediaBody: Uint8Array.from([1]),
      fetchImpl
    })
  );
  assert.equal(calls, 0);
});
