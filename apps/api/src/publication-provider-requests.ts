import { z } from "zod";

const HttpsUrl = z.string().trim().url().refine((value) => value.startsWith("https://"), {
  message: "provider publication assets must use HTTPS"
});

const InstagramVersion = z.string().regex(/^v\d+\.\d+$/);

export const InstagramContainerInputSchema = z.object({
  apiVersion: InstagramVersion,
  providerAccountId: z.string().trim().min(1).max(200),
  accessToken: z.string().min(1),
  mediaKind: z.enum(["image", "reel"]),
  mediaUrl: HttpsUrl,
  caption: z.string().max(2_200).default("")
});

export type InstagramContainerInput = z.input<typeof InstagramContainerInputSchema>;

export function buildInstagramContainerRequest(input: InstagramContainerInput): RequestInit & { url: string } {
  const parsed = InstagramContainerInputSchema.parse(input);
  const url = `https://graph.instagram.com/${parsed.apiVersion}/${encodeURIComponent(parsed.providerAccountId)}/media`;
  const body = new URLSearchParams({
    ...(parsed.mediaKind === "image" ? { image_url: parsed.mediaUrl } : {
      media_type: "REELS",
      video_url: parsed.mediaUrl
    }),
    ...(parsed.caption ? { caption: parsed.caption } : {})
  });

  return {
    url,
    method: "POST",
    headers: {
      authorization: `Bearer ${parsed.accessToken}`,
      "content-type": "application/x-www-form-urlencoded"
    },
    body: body.toString()
  };
}

export function buildInstagramPublishRequest(input: {
  apiVersion: string;
  providerAccountId: string;
  accessToken: string;
  creationId: string;
}): RequestInit & { url: string } {
  const version = InstagramVersion.parse(input.apiVersion);
  const accountId = z.string().trim().min(1).max(200).parse(input.providerAccountId);
  const token = z.string().min(1).parse(input.accessToken);
  const creationId = z.string().trim().min(1).max(200).parse(input.creationId);
  return {
    url: `https://graph.instagram.com/${version}/${encodeURIComponent(accountId)}/media_publish`,
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/x-www-form-urlencoded"
    },
    body: new URLSearchParams({ creation_id: creationId }).toString()
  };
}

export const YoutubeVideoInsertInputSchema = z.object({
  accessToken: z.string().min(1),
  mimeType: z.enum(["video/mp4", "video/quicktime", "video/webm"]),
  bytes: z.number().int().positive(),
  title: z.string().trim().min(1).max(100),
  description: z.string().max(5_000).default(""),
  tags: z.array(z.string().trim().min(1).max(500)).max(50).default([]),
  privacyStatus: z.enum(["private", "public", "unlisted"]).default("private")
});

export type YoutubeVideoInsertInput = z.input<typeof YoutubeVideoInsertInputSchema>;

export function buildYoutubeVideoInsertRequest(input: YoutubeVideoInsertInput): RequestInit & { url: string } {
  const parsed = YoutubeVideoInsertInputSchema.parse(input);
  const metadata = {
    snippet: {
      title: parsed.title,
      description: parsed.description,
      ...(parsed.tags.length ? { tags: parsed.tags } : {})
    },
    status: { privacyStatus: parsed.privacyStatus }
  };

  return {
    url: "https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status&uploadType=resumable",
    method: "POST",
    headers: {
      authorization: `Bearer ${parsed.accessToken}`,
      "content-type": "application/json; charset=UTF-8",
      "x-upload-content-length": String(parsed.bytes),
      "x-upload-content-type": parsed.mimeType
    },
    body: JSON.stringify(metadata)
  };
}
