import { env } from "./config.js";

export class IdentityEmailUnavailableError extends Error {}

type IdentityEmail = {
  to: string;
  subject: string;
  html: string;
};

export async function sendIdentityEmail(email: IdentityEmail): Promise<void> {
  if (!env.RESEND_API_KEY || !env.IDENTITY_EMAIL_FROM) {
    throw new IdentityEmailUnavailableError("identity_email_provider_not_configured");
  }

  const response = await fetch(env.IDENTITY_EMAIL_API_URL, {
    method: "POST",
    headers: {
      accept: "application/json",
      authorization: `Bearer ${env.RESEND_API_KEY}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      from: env.IDENTITY_EMAIL_FROM,
      to: [email.to],
      subject: email.subject,
      html: email.html
    })
  });

  if (!response.ok) {
    throw new Error(`identity email provider returned ${response.status}`);
  }
}
