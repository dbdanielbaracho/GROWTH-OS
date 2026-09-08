import assert from "node:assert/strict";
import test from "node:test";
import {
  buildInstagramContainerRequest,
  buildInstagramPublishRequest,
  buildYoutubeVideoInsertRequest
} from "./publication-provider-requests.js";

test("Instagram image container uses HTTPS media and keeps token out of URL/body", () => {
  const request = buildInstagramContainerRequest({
    apiVersion: "v24.0",
    providerAccountId: "ig-123",
    accessToken: "secret-token",
    mediaKind: "image",
    mediaUrl: "https://cdn.example/image.jpg",
    caption: "hello"
  });
  assert.equal(request.method, "POST");
  assert.equal(request.url, "https://graph.instagram.com/v24.0/ig-123/media");
  assert.equal(String(request.body).includes("image_url=https%3A%2F%2Fcdn.example%2Fimage.jpg"), true);
  assert.equal(String(request.body).includes("secret-token"), false);
  assert.equal(request.url.includes("secret-token"), false);
  assert.equal((request.headers as Record<string, string>).authorization, "Bearer secret-token");
});

test("Instagram reel request uses the provider media type and rejects non-HTTPS assets", () => {
  const request = buildInstagramContainerRequest({
    apiVersion: "v24.0",
    providerAccountId: "ig-123",
    accessToken: "secret-token",
    mediaKind: "reel",
    mediaUrl: "https://cdn.example/video.mp4"
  });
  assert.equal(String(request.body).includes("media_type=REELS"), true);
  assert.throws(() =>
    buildInstagramContainerRequest({
      apiVersion: "v24.0",
      providerAccountId: "ig-123",
      accessToken: "secret-token",
      mediaKind: "image",
      mediaUrl: "http://cdn.example/image.jpg"
    })
  );
});

test("Instagram publish request sends only the creation id in the body", () => {
  const request = buildInstagramPublishRequest({
    apiVersion: "v24.0",
    providerAccountId: "ig-123",
    accessToken: "secret-token",
    creationId: "creation-123"
  });
  assert.equal(request.url.endsWith("/ig-123/media_publish"), true);
  assert.equal(String(request.body), "creation_id=creation-123");
  assert.equal(String(request.body).includes("secret-token"), false);
});

test("YouTube resumable insert declares upload metadata and defaults to private", () => {
  const request = buildYoutubeVideoInsertRequest({
    accessToken: "secret-token",
    mimeType: "video/mp4",
    bytes: 1234,
    title: "Launch",
    description: "Description"
  });
  assert.equal(request.url, "https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status&uploadType=resumable");
  const headers = request.headers as Record<string, string>;
  assert.equal(headers.authorization, "Bearer secret-token");
  assert.equal(headers["x-upload-content-length"], "1234");
  assert.equal(headers["x-upload-content-type"], "video/mp4");
  assert.deepEqual(JSON.parse(String(request.body)), {
    snippet: { title: "Launch", description: "Description" },
    status: { privacyStatus: "private" }
  });
  assert.equal(String(request.body).includes("secret-token"), false);
});

test("YouTube publication validates title and positive content length", () => {
  assert.throws(() => buildYoutubeVideoInsertRequest({
    accessToken: "secret-token",
    mimeType: "video/mp4",
    bytes: 0,
    title: "",
    description: ""
  }));
});
