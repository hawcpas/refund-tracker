const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const {
  defineSecret,
  defineString,
  defineInt,
  defineBoolean,
} = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const archiver = require("archiver");
const functions = require("firebase-functions");

// ✅ ADD THESE THREE LINES HERE
const os = require("os");
const path = require("path");
const fs = require("fs");

admin.initializeApp();

const db = admin.firestore();

// ============================
// Graph (modern auth) secrets
// ============================
const GRAPH_TENANT_ID = defineSecret("GRAPH_TENANT_ID");
const GRAPH_CLIENT_ID = defineSecret("GRAPH_CLIENT_ID");
const GRAPH_CLIENT_SECRET = defineSecret("GRAPH_CLIENT_SECRET");


// ============================
// Params
// ============================
const APP_NAME = defineString("APP_NAME", { default: "Axume Portal" });
const APP_URL = defineString("APP_URL");

const SMTP_HOST = defineString("SMTP_HOST");
const SMTP_PORT = defineInt("SMTP_PORT", { default: 587 });
const SMTP_SECURE = defineBoolean("SMTP_SECURE", { default: false });
const SMTP_FROM = defineString("SMTP_FROM");

// ============================
// checkEmailExists (public)
// ============================
exports.checkEmailExists = onCall(
  { region: "us-central1" },
  async (request) => {
    const email = String(request.data?.email || "").trim().toLowerCase();
    if (!email || !email.includes("@")) {
      throw new HttpsError("invalid-argument", "Valid email is required.");
    }

    try {
      await admin.auth().getUserByEmail(email);
      return { ok: true, exists: true };
    } catch (e) {
      // Firebase Admin throws auth/user-not-found
      if (e && (e.code === "auth/user-not-found" || e.errorInfo?.code === "auth/user-not-found")) {
        return { ok: true, exists: false };
      }
      console.error("checkEmailExists failed:", e);
      throw new HttpsError("internal", "Unable to check email.");
    }
  }
);

// ============================
// Helpers
// ============================

// ============================
// Email branding (single source of truth)
// ============================
function getEmailLogoUrl() {
  // Use APP_URL if set (keeps branding correct across domains),
  // otherwise fall back to your Firebase Hosting domain.
  const base = (APP_URL.value() || "https://axume-portal-6bfd3.web.app")
    .toString()
    .replace(/\/$/, "");

  // You said: "newlonglogo.png"
  // Put the file at: /icons/newlonglogo.png (recommended to match your existing pattern)
  return `https://portal.axumecpas.com/icons/newlonglogo.png`;

  // If you truly host it at the root instead, use this instead:
  // return `${base}/newlonglogo.png`;
}


function hashOtp(code) {
  return crypto.createHash("sha256").update(code).digest("hex");
}

function renderActivationEmail({ appName, firstName, resetLink, verifyLink }) {
  const safeFirstName = (firstName || "").toString().trim() || "there";

  return `
<div style="font-family:Segoe UI, Arial, sans-serif; background:#ffffff; color:#0B1F33; line-height:1.55;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width:620px; margin:0 auto; background:#ffffff;">

    <!-- Header / Logo -->
    <tr>
      <td style="padding:28px 24px 18px 24px; border-bottom:1px solid #E4E7EC; background:#F9FAFB;">
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td>
              <img
                src="${getEmailLogoUrl()}"
                alt="Axume &amp; Associates CPAs"
                width="360"
                height="84"
                style="display:block;border:0;outline:none;text-decoration:none;max-width:360px;height:auto;"
              />
            </td>
          </tr>
        </table>
      </td>
    </tr>

    <!-- Body -->
    <tr>
      <td style="padding:24px;">

        <h2 style="margin:0 0 6px 0; font-size:20px; font-weight:700; color:#0B1F33;">
          Account activation required
        </h2>

        <p style="margin:0 0 18px 0; font-size:14px; color:#475467;">
          ${appName}
        </p>

        <p style="margin:0 0 14px 0;">
          Hello ${safeFirstName},
        </p>

        <p style="margin:0 0 14px 0;">
  An account has been created for you in <b>${appName}</b>.
  This portal provides authorized firm personnel with secure access to
  internal resources and the ability to retrieve and manage files in a
  protected environment.
</p>

        <p style="margin:0 0 22px 0;">
          To complete your setup and access the portal, please follow the steps below.
        </p>

        <!-- Step 1 -->
        <div style="margin:0 0 18px 0; padding:16px; border:1px solid #E4E7EC; border-radius:8px; background:#F9FAFB;">
          <p style="margin:0 0 6px 0; font-weight:700; color:#0B1F33;">
            Step 1 — Set your password
          </p>
          <p style="margin:0 0 12px 0; font-size:14px;">
            Establish a secure password to activate your account.
          </p>

          <a
            href="${resetLink}"
            style="display:inline-block; padding:10px 16px; background:#0B1F33; color:#ffffff;
                   text-decoration:none; border-radius:6px; font-weight:600; font-size:14px;"
          >
            Set password
          </a>
        </div>

        <!-- Step 2 -->
        <div style="margin:0 0 24px 0; padding:16px; border:1px solid #E4E7EC; border-radius:8px;">
          <p style="margin:0 0 6px 0; font-weight:700; color:#0B1F33;">
            Step 2 — Verify your email address
          </p>
          <p style="margin:0 0 12px 0; font-size:14px;">
            Email verification is recommended and helps protect your account.
          </p>

          <a
            href="${verifyLink}"
            style="display:inline-block; padding:10px 16px; background:#ffffff; color:#0B1F33;
                   text-decoration:none; border-radius:6px; border:1px solid #0B1F33;
                   font-weight:600; font-size:14px;"
          >
            Verify email
          </a>
        </div>

        <!-- Fallback links -->
        <p style="margin:0 0 10px 0; font-size:13px; color:#667085;">
          If the buttons above do not open correctly, copy and paste the links below into your browser:
        </p>

        <p style="margin:0 0 8px 0; font-size:12px;">
          <b>Set password</b><br/>
          <a href="${resetLink}" style="color:#0B62D6; word-break:break-all;">
            ${resetLink}
          </a>
        </p>

        <p style="margin:0 0 20px 0; font-size:12px;">
          <b>Verify email</b><br/>
          <a href="${verifyLink}" style="color:#0B62D6; word-break:break-all;">
            ${verifyLink}
          </a>
        </p>

        <!-- Support -->
        <p style="margin:0 0 8px 0;">
          If you believe you received this message in error, or need assistance,
          please contact the firm’s IT administrator at
          <a href="mailto:guillermo@axumecpas.com" style="color:#0B62D6;">
            guillermo@axumecpas.com
          </a>.
        </p>

        <p style="margin:20px 0 0 0;">
          Regards,<br/>
          <b>Axume &amp; Associates CPAs</b><br/>
          <span style="font-size:13px; color:#667085;">
            Internal Systems Administration
          </span>
        </p>
      </td>
    </tr>

    <!-- Footer -->
    <tr>
      <td style="padding:16px 24px; border-top:1px solid #E4E7EC;">
        <p style="margin:0; font-size:12px; color:#667085;">
          This message was generated automatically by the firm’s internal systems. Please do not reply.
        </p>
      </td>
    </tr>

  </table>
</div>
`;
}

function renderOtpEmail({ appName, code }) {
  return `
<div style="font-family:Segoe UI, Arial, sans-serif; background:#ffffff; color:#0B1F33; line-height:1.55;">
  <!-- ✅ Preheader (shows in inbox preview / lock screen) -->
<div style="
  display:none;
  max-height:0;
  overflow:hidden;
  mso-hide:all;
  font-size:1px;
  line-height:1px;
  color:#ffffff;
">
  Your verification code is ${code}. Expires in 5 minutes.
</div>
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width:620px; margin:0 auto; background:#ffffff;">

    <!-- Header -->
    <tr>
      <td style="padding:28px 24px 18px 24px; border-bottom:1px solid #E4E7EC; background:#F9FAFB;">
        <img
          src="${getEmailLogoUrl()}"
          alt="Axume & Associates CPAs"
          width="360"
          style="display:block;border:0;outline:none;text-decoration:none;max-width:360px;height:auto;"
        />
      </td>
    </tr>

    <!-- Body -->
    <tr>
      <td style="padding:24px;">

        <h2 style="margin:0 0 6px 0; font-size:20px; font-weight:700; color:#0B1F33;">
          Login verification required
        </h2>

        <p style="margin:0 0 18px 0; font-size:14px; color:#475467;">
          ${appName}
        </p>

        <p style="margin:0 0 14px 0;">
          A sign‑in attempt was made to your account.  
          To continue, enter the verification code below.
        </p>

        <!-- Code box -->
        <div style="margin:20px 0 22px 0; padding:18px; border:1px solid #E4E7EC;
                    border-radius:10px; background:#F9FAFB; text-align:center;">
          <div style="font-size:32px; font-weight:800; letter-spacing:6px; color:#0B1F33;">
            ${code}
          </div>
        </div>

        <p style="margin:0 0 16px 0; font-size:13px; color:#475467;">
          This code expires in <b>5 minutes</b> and can only be used once.
        </p>

        <p style="margin:0 0 14px 0; font-size:13px; color:#475467;">
          If you did not attempt to sign in, please notify your administrator immediately.
        </p>

        <!-- Support -->
        <p style="margin:20px 0 0 0;">
          Regards,<br/>
          <b>Axume & Associates CPAs</b><br/>
          <span style="font-size:13px; color:#667085;">
            Internal Systems Administration
          </span>
        </p>

      </td>
    </tr>

    <!-- Footer -->
    <tr>
      <td style="padding:16px 24px; border-top:1px solid #E4E7EC;">
        <p style="margin:0; font-size:12px; color:#667085;">
          This message was generated automatically by the firm’s internal systems.
          Please do not reply.
        </p>
      </td>
    </tr>

  </table>
</div>
`;
}

function renderEmailChangeVerificationEmail({ appName, confirmUrl }) {
  return `
<div style="font-family:Segoe UI, Arial, sans-serif; background:#ffffff; color:#0B1F33; line-height:1.55;">
  <!-- ✅ Preheader (inbox / lock screen preview) -->
  <div style="
    display:none;
    max-height:0;
    overflow:hidden;
    mso-hide:all;
    font-size:1px;
    line-height:1px;
    color:#ffffff;
  ">
    Confirm your new email address for ${appName}. This link expires in 1 hour.
  </div>

  <table width="100%" cellpadding="0" cellspacing="0"
         style="max-width:620px; margin:0 auto; background:#ffffff;">

    <!-- Header / Logo -->
    <tr>
      <td style="padding:28px 24px 18px 24px;
                 border-bottom:1px solid #E4E7EC;
                 background:#F9FAFB;">
        <img
          src="${getEmailLogoUrl()}"
          alt="Axume & Associates CPAs"
          width="360"
          style="display:block;border:0;outline:none;
                 text-decoration:none;max-width:360px;height:auto;"
        />
      </td>
    </tr>

    <!-- Body -->
    <tr>
      <td style="padding:24px;">

        <h2 style="margin:0 0 6px 0;
                   font-size:20px;
                   font-weight:700;
                   color:#0B1F33;">
          Email change confirmation required
        </h2>

        <p style="margin:0 0 18px 0;
                  font-size:14px;
                  color:#475467;">
          ${appName}
        </p>

        <p style="margin:0 0 14px 0;">
          A request was made to change the email address associated with your account.
        </p>

        <p style="margin:0 0 18px 0;">
          To complete this change, please confirm the new email address by selecting
          the button below.
        </p>

        <!-- Action -->
        <div style="margin:20px 0 22px 0;
                    padding:16px;
                    border:1px solid #E4E7EC;
                    border-radius:10px;
                    background:#F9FAFB;
                    text-align:center;">
          <a
            href="${confirmUrl}"
            style="display:inline-block;
                   padding:10px 16px;
                   background:#0B1F33;
                   color:#ffffff;
                   text-decoration:none;
                   border-radius:6px;
                   font-weight:600;
                   font-size:14px;">
            Confirm email change
          </a>
        </div>

        <p style="margin:0 0 14px 0;
                  font-size:13px;
                  color:#475467;">
          This link expires in <b>1 hour</b> and can only be used once.
        </p>

        <p style="margin:0 0 14px 0;
                  font-size:13px;
                  color:#475467;">
          If you did not request this change, no action is required and your
          account will remain unchanged.
        </p>

        <!-- Support -->
        <p style="margin:20px 0 0 0;">
          Regards,<br/>
          <b>Axume &amp; Associates CPAs</b><br/>
          <span style="font-size:13px; color:#667085;">
            Internal Systems Administration
          </span>
        </p>

      </td>
    </tr>

    <!-- Footer -->
    <tr>
      <td style="padding:16px 24px;
                 border-top:1px solid #E4E7EC;">
        <p style="margin:0;
                  font-size:12px;
                  color:#667085;">
          This message was generated automatically by the firm’s internal systems.
          Please do not reply.
        </p>
      </td>
    </tr>

  </table>
</div>
`;
}

function safeFilename(name) {
  return (name || "")
    .toString()
    .replace(/[/\\?%*:|"<>]/g, "_")
    .replace(/[\r\n]+/g, " ")
    .replace(/"/g, "'");
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function formatBytes(bytes) {
  const n = Number(bytes || 0);
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / (1024 * 1024)).toFixed(1)} MB`;
  return `${(n / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function normalizeEmail(email) {
  return (email || "").toLowerCase().trim();
}

function normalizeName(s) {
  return (s || "").toString().trim();
}

function sha256(s) {
  return crypto.createHash("sha256").update(String(s)).digest("hex");
}

async function assertAdmin(callerUid) {
  const snap = await admin.firestore().collection("users").doc(callerUid).get();
  if (!snap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Admin profile missing in users/{uid}."
    );
  }
  const role = (snap.data()?.role || "").toString().toLowerCase().trim();
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Admins only.");
  }
}

async function assertDropoffAccess(callerUid) {
  const snap = await admin.firestore().collection("users").doc(callerUid).get();
  if (!snap.exists) {
    throw new HttpsError(
      "permission-denied",
      "User profile missing in users/{uid}."
    );
  }

  const data = snap.data() || {};
  const role = (data.role || "").toString().toLowerCase().trim();
  const can = role === "admin" || (data.capabilities && data.capabilities.dropoffs === true);

  if (!can) {
    throw new HttpsError("permission-denied", "Drop-off access required.");
  }
}


function isValidHttpUrl(url) {
  return (
    typeof url === "string" &&
    url.trim() !== "" &&
    /^https?:\/\/[^\s]+$/.test(url.trim())
  );
}

const DEFAULT_DROPOFF_EXPIRATION_MINUTES = 14 * 24 * 60;
const MAX_DROPOFF_EXPIRATION_MINUTES = 90 * 24 * 60;
const MIN_DROPOFF_EXPIRATION_MINUTES = 1;

function normalizeExpirationMinutes(value, legacyHoursValue, legacyDaysValue) {
  if (value === null) return null;

  const raw =
    value != null
      ? Number(value)
      : legacyHoursValue != null
        ? Number(legacyHoursValue) * 60
        : legacyDaysValue != null
          ? Number(legacyDaysValue) * 24 * 60
          : DEFAULT_DROPOFF_EXPIRATION_MINUTES;

  if (!Number.isFinite(raw)) return DEFAULT_DROPOFF_EXPIRATION_MINUTES;

  return Math.max(
    MIN_DROPOFF_EXPIRATION_MINUTES,
    Math.min(MAX_DROPOFF_EXPIRATION_MINUTES, Math.floor(raw))
  );
}

function makeDropoffExpiresAtFromMinutes(minutes) {
  if (minutes == null) return null;

  return admin.firestore.Timestamp.fromMillis(
    Date.now() + minutes * 60 * 1000
  );
}


function dropoffExpired(doc) {
  const expiresAt = doc.expiresAt;
  const ms = expiresAt?.toMillis?.();
  return typeof ms === "number" && ms <= Date.now();
}

async function markDropoffExpired(ref) {
  await ref.set(
    {
      status: "expired",
      expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedBy: "system",
    },
    { merge: true }
  );
}

exports.expireDropoffRequests = onSchedule(
  {
    region: "us-central1",
    schedule: "every 5 minutes",
    timeZone: "America/Los_Angeles",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    let total = 0;

    while (true) {
      const snap = await db
        .collection("dropoff_requests")
        .where("status", "==", "open")
        .where("expiresAt", "<=", now)
        .limit(400)
        .get();

      if (snap.empty) break;

      const batch = db.batch();

      snap.docs.forEach((doc) => {
        batch.set(
          doc.ref,
          {
            status: "expired",
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            statusUpdatedBy: "system",
          },
          { merge: true }
        );
      });

      await batch.commit();
      total += snap.size;

      if (snap.size < 400) break;
    }

    console.log("Expired dropoff requests:", total);
  }
);



exports.verifyLoginOtp = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated");
    }

    const code = String(request.data?.code || "").trim();
    if (!code) {
      throw new HttpsError("invalid-argument", "Code is required.");
    }

    const uid = request.auth.uid;
    const ref = db.collection("auth_otps").doc(uid);
    const snap = await ref.get();

    if (!snap.exists) {
      throw new HttpsError("not-found", "No active OTP.");
    }

    const data = snap.data();

    if (data.expiresAt.toDate() < new Date()) {
      await ref.delete();
      throw new HttpsError("deadline-exceeded", "Code expired.");
    }

    if (data.codeHash !== hashOtp(code)) {
      await ref.update({
        attempts: admin.firestore.FieldValue.increment(1),
      });
      throw new HttpsError("permission-denied", "Invalid code.");
    }

    const user = await admin.auth().getUser(uid);
    const existingClaims = user.customClaims || {};

    await admin.auth().setCustomUserClaims(uid, {
      ...existingClaims,
      otp_verified: true,
      otp_verified_at: Date.now(), // ✅ milliseconds
    });


    await ref.delete();

    return { ok: true };
  }
);


exports.sendLoginOtp = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated");
    }

    const uid = request.auth.uid;
    const email = request.auth.token.email;
    if (!email) {
      throw new HttpsError("failed-precondition", "User has no email.");
    }

    const OTP_TTL_MS = 5 * 60 * 1000;        // ✅ OTP validity stays 5 minutes
    const RESEND_COOLDOWN_MS = 30 * 1000;    // ✅ resend throttle is 1 minute
    const nowMs = Date.now();

    const ref = db.collection("auth_otps").doc(uid);
    const existing = await ref.get();

    if (existing.exists) {
      const data = existing.data() || {};
      const exp = data.expiresAt?.toDate?.();

      // If the current OTP is still valid…
      if (exp && exp.getTime() > nowMs) {
        const lastSentAtMs = Number(data.lastSentAtMs || 0);
        const sinceLastSend = nowMs - lastSentAtMs;

        // ✅ Throttle: block sending a NEW email/code until 60s passes
        if (lastSentAtMs && sinceLastSend < RESEND_COOLDOWN_MS) {
          const remainingSeconds = Math.max(
            0,
            Math.ceil((RESEND_COOLDOWN_MS - sinceLastSend) / 1000)
          );

          console.log("⏳ OTP resend throttled");
          return {
            ok: true,
            throttled: true,
            remainingSeconds,
            // Helpful metadata for UI if you want it:
            otpExpiresAt: exp.toISOString(),
          };
        }

        // ✅ Cooldown passed → allow sending a NEW code email
        // (We generate a new code because we only store a hash)
      }
    }

    // ✅ Clear previous OTP trust
    const user = await admin.auth().getUser(uid);
    const existingClaims = user.customClaims || {};

    await admin.auth().setCustomUserClaims(uid, {
      ...existingClaims,
      otp_verified: false,
      otp_verified_at: 0,
    });

    const code = Math.floor(100000 + Math.random() * 900000).toString();

    await ref.set({
      codeHash: hashOtp(code),
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(nowMs + OTP_TTL_MS)),
      attempts: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),

      // ✅ NEW: used ONLY for resend throttling
      lastSentAtMs: nowMs,
    });

    await sendAccountEmail({
      to: email,
      subject: "Login verification code",
      html: renderOtpEmail({
        appName: APP_NAME.value(),
        code,
      }),
    });

    return {
      ok: true,
      sent: true,
      remainingSeconds: 30,                 // next resend allowed after 60s
      otpExpiresAt: new Date(nowMs + OTP_TTL_MS).toISOString(),
    };
  }
);

const https = require("https"); // ✅ add near the top with other requires

// ============================
// Microsoft Graph helpers (Application permissions)
// ============================
let _graphTokenCache = { token: null, expMs: 0 };

function _httpsRequest({ method, url, headers, body }) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);

    const req = https.request(
      {
        method,
        hostname: u.hostname,
        path: u.pathname + u.search,
        headers,
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () =>
          resolve({ status: res.statusCode || 0, body: data })
        );
      }
    );

    req.on("error", reject);

    if (body) req.write(body);
    req.end();
  });
}

async function _getGraphAccessToken() {
  const now = Date.now();

  // ✅ reuse token if it expires in > 60s
  if (_graphTokenCache.token && _graphTokenCache.expMs - now > 60_000) {
    return _graphTokenCache.token;
  }

  const tenantId = GRAPH_TENANT_ID.value();
  const clientId = GRAPH_CLIENT_ID.value();
  const clientSecret = GRAPH_CLIENT_SECRET.value();

  const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;

  const body = new URLSearchParams();
  body.set("client_id", clientId);
  body.set("client_secret", clientSecret);
  body.set("grant_type", "client_credentials");
  body.set("scope", "https://graph.microsoft.com/.default");

  const resp = await _httpsRequest({
    method: "POST",
    url: tokenUrl,
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (resp.status !== 200) {
    console.error("❌ Graph token fetch failed", {
      status: resp.status,
      body: resp.body,
    });
    throw new Error(`Graph token fetch failed: ${resp.status}`);
  }

  const json = JSON.parse(resp.body);
  const accessToken = json.access_token;
  const expiresInSec = Number(json.expires_in || 3600);

  _graphTokenCache = {
    token: accessToken,
    expMs: now + expiresInSec * 1000,
  };

  return accessToken;
}

// ✅ Drop-in replacement (same signature your code already calls)
async function sendAccountEmail({ to, subject, html }) {
  const fromAddress = (SMTP_FROM.value() || "").toString().trim();
  if (!fromAddress || !fromAddress.includes("@")) {
    console.error("SMTP_FROM is invalid:", { fromAddress });
    throw new Error("SMTP_FROM is missing or invalid");
  }

  const token = await _getGraphAccessToken();

  const payload = JSON.stringify({
    message: {
      subject,
      toRecipients: [{ emailAddress: { address: to } }],
      replyTo: [
        {
          emailAddress: {
            name: "Axume & Associates IT Dept.",
            address: "guillermo@axumecpas.com",
          },
        },
      ],
      body: { contentType: "HTML", content: html },
    },
    saveToSentItems: false,
  });

  const url = `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(
    fromAddress
  )}/sendMail`;

  const resp = await _httpsRequest({
    method: "POST",
    url,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(payload),
    },
    body: payload,
  });

  // Graph returns 202 on success
  if (resp.status !== 202) {
    console.error("❌ Graph sendMail failed", {
      status: resp.status,
      fromAddress,
      to,
      subject,
      body: resp.body,
    });
    throw new Error(`Graph sendMail failed: ${resp.status}`);
  }

  console.log("✅ Graph email accepted", { to, subject, fromAddress });
  return true;
}


async function getUserDocByUid(uid) {
  const ref = admin.firestore().collection("users").doc(uid);
  const snap = await ref.get();
  return { ref, snap, data: snap.exists ? (snap.data() || {}) : {} };
}

exports.notifyDropoffBatchUpload = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    console.log("✅ notifyDropoffBatchUpload CALLED", {
      data: request.data,
    });

    try {
      const { rid, token, files } = request.data || {};

      if (!rid || !token || !Array.isArray(files) || files.length === 0) {
        throw new HttpsError(
          "invalid-argument",
          "rid, token, and files[] are required."
        );
      }

      // ✅ execution continues → email WILL send

      const ref = admin.firestore().collection("dropoff_requests").doc(rid);
      const snap = await ref.get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "Drop-off request not found.");
      }

      const req = snap.data() || {};
      if (sha256(token) !== req.tokenHash) {
        throw new HttpsError("permission-denied", "Invalid token.");
      }

      if ((req.status || "open") !== "open") {
        throw new HttpsError("failed-precondition", "Drop-off is closed.");
      }

      if (dropoffExpired(req)) {
        await markDropoffExpired(ref);
        throw new HttpsError("failed-precondition", "Drop-off link has expired.");
      }

      const createdByUid = (req.createdByUid || "").toString().trim();

      const createdByEmail = (req.createdByEmail || "").toString().trim();
      const clientName = (req.clientName || "a client").toString().trim();

      if (!createdByUid && !createdByEmail) return { ok: true, emailed: false };

      // Determine recipient email
      let to = createdByEmail;
      if (!to) {
        const u = await admin.auth().getUser(createdByUid);
        to = (u.email || "").toString().trim();
      }
      if (!to) return { ok: true, emailed: false };

      // Build portal link (same as single-file email)
      const baseUrl = (APP_URL.value() || "").toString().replace(/\/$/, "");
      const portalUrl = baseUrl ? `${baseUrl}/generate-upload-link?rid=${rid}` : "";

      const subject = `${clientName} has uploaded files.`;
      // ✅ MULTI‑FILE LIST (this is the only difference)
      // ✅ Normalize BOTH payload types:
      //  - old: ["a.pdf", "b.txt"]
      //  - new: [{ name:"a.pdf", sizeBytes: 123 }, ...]
      const normalizedFiles = (Array.isArray(files) ? files : [])
        .map((x) => {
          if (typeof x === "string") {
            return { name: x, sizeBytes: null };
          }
          if (x && typeof x === "object") {
            // allow a few common key names
            const name =
              (x.name || x.originalName || x.filename || "").toString().trim();
            const sizeBytes =
              x.sizeBytes != null ? Number(x.sizeBytes) : (x.size != null ? Number(x.size) : null);
            return { name, sizeBytes };
          }
          return { name: "", sizeBytes: null };
        })
        .filter((f) => (f.name || "").toString().trim().length > 0);

      // ✅ If caller payload was empty after normalization, fall back to Firestore
      let finalFiles = normalizedFiles;

      if (finalFiles.length === 0) {
        try {
          const want = Math.min(
            25,
            Math.max(1, Array.isArray(files) ? files.length : 10)
          );

          const filesSnap = await ref
            .collection("files")
            .where("deleted", "==", false)
            .orderBy("createdAt", "desc")
            .limit(want)
            .get();

          finalFiles = filesSnap.docs.map((d) => {
            const m = d.data() || {};
            return {
              name: (m.originalName || d.id || "").toString().trim(),
              sizeBytes: m.sizeBytes != null ? Number(m.sizeBytes) : null,
            };
          }).filter((f) => f.name);
        } catch (e) {
          console.warn("notifyDropoffBatchUpload fallback list failed:", e);
        }
      }

      console.log("notifyDropoffBatchUpload file payload", {
        receivedCount: Array.isArray(files) ? files.length : 0,
        normalizedCount: normalizedFiles.length,
        finalCount: finalFiles.length,
        sample: Array.isArray(files) ? files[0] : null,
      });

      const fileLines = finalFiles
        .map((f) => {
          const name = safeFilename((f.name || "").toString().trim());
          if (!name) return null;

          const sizeText = f.sizeBytes != null ? formatBytes(f.sizeBytes) : null;
          return sizeText
            ? `<li style="margin:0 0 6px 0;"><b>${name}</b> <span style="color:#667085; font-weight:600;">(${sizeText})</span></li>`
            : `<li style="margin:0 0 6px 0;"><b>${name}</b></li>`;
        })
        .filter(Boolean)
        .join("") || `<li style="margin:0 0 6px 0;"><b>Files uploaded</b> <span style="color:#667085; font-weight:600;">(details unavailable)</span></li>`;
      ``

      const html = `
<div style="font-family:Segoe UI, Arial, sans-serif; background:#ffffff; color:#0B1F33; line-height:1.55;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width:620px; margin:0 auto; background:#ffffff;">

    <!-- Header / Logo -->
    <tr>
      <td style="padding:28px 24px 18px 24px; border-bottom:1px solid #E4E7EC; background:#F9FAFB;">
        <img
          src="${getEmailLogoUrl()}"
          alt="Axume &amp; Associates CPAs"
          width="360"
          style="display:block;border:0;outline:none;text-decoration:none;max-width:360px;height:auto;"
        />
      </td>
    </tr>

    <!-- Body -->
    <tr>
      <td style="padding:24px;">

        <h2 style="margin:0 0 6px 0; font-size:20px; font-weight:700; color:#0B1F33;">
          New file upload received
        </h2>

        <p style="margin:0 0 18px 0; font-size:14px; color:#475467;">
          ${APP_NAME.value()}
        </p>

        <p style="margin:0 0 14px 0;">
          New files have been uploaded to the secure drop‑off request for
          <b>${clientName}</b>.
        </p>

        <div style="margin:0 0 18px 0; padding:16px; border:1px solid #E4E7EC; border-radius:8px; background:#F9FAFB;">
          <p style="margin:0 0 8px 0; font-weight:700; color:#0B1F33;">
            Uploaded files
          </p>
          <ul style="margin:0; padding-left:18px;">
            ${fileLines}
          </ul>
        </div>

        <p style="margin:0 0 18px 0;">
          To review the uploaded files, open the firm portal using the link below.
        </p>

        ${portalUrl
          ? `
        <div style="margin:0 0 24px 0;">
          <a
            href="${portalUrl}"
            style="display:inline-block; padding:10px 16px; background:#0B1F33; color:#ffffff;
                   text-decoration:none; border-radius:6px; font-weight:600; font-size:14px;"
          >
            Open upload details
          </a>
        </div>
        `
          : ""
        }

        <p style="margin:0 0 8px 0;">
          If you were not expecting this upload, no action is required.
        </p>

        <p style="margin:20px 0 0 0;">
          Regards,<br/>
          <b>Axume &amp; Associates CPAs</b><br/>
          <span style="font-size:13px; color:#667085;">
            Internal Systems Administration
          </span>
        </p>

      </td>
    </tr>

    <!-- Footer -->
    <tr>
      <td style="padding:16px 24px; border-top:1px solid #E4E7EC;">
        <p style="margin:0; font-size:12px; color:#667085;">
          This message was generated automatically by the firm’s internal systems. Please do not reply.
        </p>
      </td>
    </tr>

  </table>
</div>
`;

      await sendAccountEmail({ to, subject, html });

      // ============================
      // ✅ IN-APP NOTIFICATION (staff) — batch upload
      // ============================
      if (createdByUid) {
        await db.collection("notifications").add({
          userUid: createdByUid,
          type: "dropoff_upload",
          title: "Client upload received",
          body: `${clientName || "A client"} uploaded ${finalFiles.length} files`,
          requestId: rid,
          clientName: clientName || "",
          businessName: req.businessName || "",
          clientEmail: req.clientEmail || "",
          fileCount: finalFiles.length,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          readAt: null,
        });

      }

      return { ok: true, emailed: true };
    } catch (err) {
      console.error("notifyDropoffBatchUpload failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Batch upload notification failed.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

// ============================
// inviteUser (admin-only) ✅ RESTORED + Option A capability default
// ============================
exports.inviteUser = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const email = normalizeEmail(data?.email);
      const requestedRole = (data?.role || "associate").toString().toLowerCase().trim();
      const firstName = normalizeName(data?.firstName);
      const lastName = normalizeName(data?.lastName);
      const displayName = `${firstName} ${lastName}`.trim();

      if (!email || !email.includes("@")) {
        throw new HttpsError("invalid-argument", "Valid email is required.");
      }
      if (!firstName) throw new HttpsError("invalid-argument", "First name is required.");
      if (!lastName) throw new HttpsError("invalid-argument", "Last name is required.");

      // ✅ Option A: allow dropoffs by default for non-admin staff
      const dropoffsDefault = requestedRole !== "admin";

      // ✅ Block self-invite
      let callerEmail = normalizeEmail(auth.token?.email);
      if (!callerEmail) {
        const caller = await admin.auth().getUser(auth.uid);
        callerEmail = normalizeEmail(caller.email);
      }
      if (callerEmail && callerEmail === email) {
        throw new HttpsError("failed-precondition", "You cannot invite yourself.");
      }

      // Create or fetch Auth user
      let userRecord;
      let existedInAuth = true;
      try {
        userRecord = await admin.auth().getUserByEmail(email);
      } catch (_) {
        existedInAuth = false;
        userRecord = await admin.auth().createUser({
          email,
          displayName: displayName || undefined,
          emailVerified: false,
        });
      }

      // Validate APP_URL
      const rawAppUrl = APP_URL.value();
      if (!isValidHttpUrl(rawAppUrl)) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${rawAppUrl}"`);
      }

      const actionCodeSettings = {
        url: rawAppUrl.trim(),
        handleCodeInApp: false,
      };

      const resetLink = await admin
        .auth()
        .generatePasswordResetLink(email, actionCodeSettings);

      const verifyLink = await admin
        .auth()
        .generateEmailVerificationLink(email, actionCodeSettings);

      // Fetch existing Firestore profile (if any)
      const userDocRef = admin.firestore().collection("users").doc(userRecord.uid);
      const existingSnap = await userDocRef.get();
      const existingData = existingSnap.exists ? (existingSnap.data() || {}) : {};
      const existingRole = (existingData.role || "").toString().toLowerCase().trim();
      const existingStatus = (existingData.status || "").toString().toLowerCase().trim();

      // Prevent downgrading an existing admin via invite
      if (existingRole === "admin" && requestedRole !== "admin") {
        throw new HttpsError("failed-precondition", "Admins cannot be downgraded via invites.");
      }

      // Do not overwrite role/status for already-active users
      const shouldWriteRoleStatus =
        !existingSnap.exists ||
        existingStatus === "" ||
        existingStatus === "invited" ||
        existingStatus === "pending";

      const userPayload = {
        uid: userRecord.uid,
        email,
        firstName,
        lastName,
        displayName,
        emailVerified: false,
        invitedAt: admin.firestore.FieldValue.serverTimestamp(),
        invitedBy: auth.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),

        // ✅ NEW: capability default (Option A)
        capabilities: {
          dropoffs: dropoffsDefault,
        },
      };

      if (shouldWriteRoleStatus) {
        userPayload.role = requestedRole;
        userPayload.status = "invited";
      }

      await userDocRef.set(userPayload, { merge: true });

      // Track invites by email (ledger)
      await admin.firestore().collection("invites").doc(email).set(
        {
          email,
          uid: userRecord.uid,
          firstName,
          lastName,
          displayName,
          role: requestedRole,
          status: "invited",
          invitedAt: admin.firestore.FieldValue.serverTimestamp(),
          invitedBy: auth.uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Send email
      await sendAccountEmail({
        to: email,
        subject: `Action required: Activate your Axume & Associates CPAs – Internal Portal account`,
        html: renderActivationEmail({
          appName: APP_NAME.value(),
          firstName,
          resetLink,
          verifyLink,
        }),
      });


      return { ok: true, email, role: requestedRole, sent: true, existedInAuth };
    } catch (err) {
      console.error("inviteUser failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Invite failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

exports.requestEmailChange = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const uid = request.auth.uid;
    const newEmail = String(request.data?.email || "").trim().toLowerCase();

    if (!newEmail || !newEmail.includes("@")) {
      throw new HttpsError("invalid-argument", "Valid email is required.");
    }

    const user = await admin.auth().getUser(uid);
    const currentEmail = (user.email || "").toLowerCase();

    if (newEmail === currentEmail) {
      throw new HttpsError(
        "failed-precondition",
        "New email must be different from current email."
      );
    }

    // ✅ Generate secure token
    const token = crypto.randomBytes(32).toString("hex");
    const tokenHash = crypto
      .createHash("sha256")
      .update(token)
      .digest("hex");

    const EXPIRES_MS = 60 * 60 * 1000; // 1 hour
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + EXPIRES_MS
    );

    const emailChangeRef = admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("emailChange")
      .doc("pending");

    await emailChangeRef.set({
      pendingEmail: newEmail,
      tokenHash,
      expiresAt,
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // ✅ Build confirmation link
    const baseUrl = APP_URL.value().replace(/\/$/, "");
    const confirmUrl = `${baseUrl}/confirm-email-change?uid=${uid}&token=${token}`;

    await sendAccountEmail({
      to: newEmail,
      subject: "Confirm your email address change",
      html: renderEmailChangeVerificationEmail({
        appName: APP_NAME.value(),
        confirmUrl,
      }),
    });

    // ✅ Audit log
    await admin.firestore().collection("auditLogs").add({
      type: "email_change_requested",
      uid,
      oldEmail: currentEmail,
      newEmail,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true };
  }
);

exports.confirmEmailChange = functions.https.onRequest(async (req, res) => {
  try {
    const uid = String(req.query.uid || "").trim();
    const token = String(req.query.token || "").trim();

    if (!uid || !token) {
      return res.status(400).send("Invalid or missing parameters.");
    }

    const tokenHash = crypto
      .createHash("sha256")
      .update(token)
      .digest("hex");

    const emailChangeRef = admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("emailChange")
      .doc("pending");

    const snap = await emailChangeRef.get();

    if (!snap.exists) {
      return res.status(410).send("This email change request is no longer valid.");
    }

    const data = snap.data();
    const { pendingEmail, expiresAt } = data || {};

    if (!pendingEmail || !expiresAt) {
      return res.status(410).send("Invalid email change request.");
    }

    if (expiresAt.toMillis() < Date.now()) {
      await emailChangeRef.delete();
      return res.status(410).send("This email change request has expired.");
    }

    if (data.tokenHash !== tokenHash) {
      return res.status(403).send("Invalid verification token.");
    }

    // ✅ Update Firebase Auth email
    await admin.auth().updateUser(uid, {
      email: pendingEmail,
      emailVerified: true,
    });

    // ✅ Update Firestore user profile
    await admin.firestore().collection("users").doc(uid).set(
      {
        email: pendingEmail,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // ✅ Cleanup
    await emailChangeRef.delete();

    // ✅ Audit log
    await admin.firestore().collection("auditLogs").add({
      type: "email_change_confirmed",
      uid,
      newEmail: pendingEmail,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });

    // ✅ Redirect user back to portal
    const redirectUrl = `${APP_URL.value().replace(/\/$/, "")}/account-settings?emailChanged=1`;
    return res.redirect(302, redirectUrl);
  } catch (err) {
    console.error("confirmEmailChange failed:", err);
    return res.status(500).send("Email confirmation failed.");
  }
});

exports.finalizeDropoffUpload = onCall(
  { region: "us-central1" },
  async (request) => {
    const { rid, token, file } = request.data || {};
    if (!rid || !token || !file) {
      throw new HttpsError("invalid-argument", "rid, token, and file are required.");
    }

    const db = admin.firestore();
    const ref = db.collection("dropoff_requests").doc(rid);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Drop-off request not found.");

    const doc = snap.data() || {};
    if ((doc.status || "open") !== "open") {
      throw new HttpsError("failed-precondition", "Drop-off is closed.");
    }

    if (dropoffExpired(doc)) {
      await markDropoffExpired(ref);
      throw new HttpsError("failed-precondition", "Drop-off link has expired.");
    }

    if (sha256(token) !== doc.tokenHash) {
      throw new HttpsError("permission-denied", "Invalid token.");
    }

    // ✅ Request-level values we want to show in the global uploads table
    const requestClientName = (doc.clientName || "").toString().trim();
    const requestClientEmail = (doc.clientEmail || "").toString().trim();
    const requestBusinessName = (doc.businessName || "").toString().trim();

    // ✅ who created the request (staff)
    const requestCreatedByUid = (doc.createdByUid || "").toString().trim();

    // ✅ determine the creator role + display name (Requested by)
    let requestCreatedByRole = "unknown";
    let requestCreatedByName = "";
    let requestCreatedByEmail = "";

    if (requestCreatedByUid) {
      const creatorSnap = await db.collection("users").doc(requestCreatedByUid).get();
      const u = creatorSnap.data() || {};

      requestCreatedByRole = ((u.role || "") + "").toString().toLowerCase().trim() || "unknown";

      const first = (u.firstName || "").toString().trim();
      const last = (u.lastName || "").toString().trim();
      const displayName = (u.displayName || "").toString().trim();

      requestCreatedByName = (first || last) ? `${first} ${last}`.trim() : displayName;
      requestCreatedByEmail = (u.email || "").toString().trim();
    }

    // generate a server-side fileId
    const fileId = db.collection("_tmp").doc().id;

    await ref.collection("files").doc(fileId).set({
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      originalName: file.originalName || "",
      storagePath: file.storagePath || "",
      sizeBytes: file.sizeBytes || 0,
      contentType: file.contentType || "",

      // ✅ REQUIRED so File Box query where deleted==false returns the doc
      deleted: false,

      uploadedBy: { type: "client", name: requestClientName },

      requestId: rid,
      requestCreatedByUid,
      requestCreatedByRole,
      requestCreatedByName: requestCreatedByName || "",
      requestCreatedByEmail: requestCreatedByEmail || "",
      requestBusinessName: requestBusinessName || "",
      requestClientEmail: requestClientEmail || "",
      requestClientName: requestClientName || "",
      requestExpiresAt: doc.expiresAt || null,
    });

    // bump counters
    await ref.set(
      {
        lastUploadedAt: admin.firestore.FieldValue.serverTimestamp(),
        fileCount: admin.firestore.FieldValue.increment(1),
      },
      { merge: true }
    );

    // ============================
    // ✅ AUDIT: record client upload activity (append-only)
    // ============================
    try {
      // Best-effort request context (privacy-safe)
      const raw = request.rawRequest;
      const ua = (raw && raw.headers && raw.headers["user-agent"]) ? String(raw.headers["user-agent"]) : "";
      const xff = (raw && raw.headers && raw.headers["x-forwarded-for"]) ? String(raw.headers["x-forwarded-for"]) : "";
      const ip = (xff.split(",")[0] || (raw && raw.ip) || "").toString().trim();
      const ipHash = ip ? sha256(ip) : "";

      await db.collection("file_activity").add({
        // Identifiers
        fileId,
        requestId: rid,
        fileDocPath: `dropoff_requests/${rid}/files/${fileId}`,

        // What happened
        action: "upload", // upload | view | download
        occurredAt: admin.firestore.FieldValue.serverTimestamp(),

        // Actor (client-only for this event)
        actorType: "client",
        actorUid: null,
        actorName: requestClientName || "Client",
        actorEmail: requestClientEmail || "",

        // Context (helps UI + rules)
        requestCreatedByUid: requestCreatedByUid || "",
        requestCreatedByRole: requestCreatedByRole || "unknown",
        requestCreatedByName: requestCreatedByName || "",
        requestBusinessName: requestBusinessName || "",

        // File snapshot (useful for audits/reports)
        originalName: file.originalName || "",
        storagePath: file.storagePath || "",
        sizeBytes: file.sizeBytes || 0,
        contentType: file.contentType || "",

        // Privacy-safe telemetry (optional but useful)
        ipHash,
        userAgent: ua,
      });
    } catch (e) {
      console.error("file_activity upload log failed (non-blocking):", e);
    }
    return { ok: true, fileId };
  }
);

// ============================
// file_activity -> denormalize last activity onto file metadata doc
// ============================
exports.syncFileLastActivity = onDocumentCreated(
  {
    region: "us-central1",
    document: "file_activity/{eventId}",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const e = snap.data() || {};
    const requestId = String(e.requestId || "").trim();
    const fileId = String(e.fileId || "").trim();
    if (!requestId || !fileId) return;

    const action = String(e.action || "").toLowerCase().trim();
    const actorName = String(e.actorName || "").trim();
    const actorType = String(e.actorType || "").toLowerCase().trim();
    const surface = String(e.surface || "").toLowerCase().trim();

    // occurredAt is serverTimestamp; at trigger time it should usually be a Timestamp
    const occurredAt =
      e.occurredAt && typeof e.occurredAt.toMillis === "function"
        ? e.occurredAt
        : admin.firestore.Timestamp.now();

    const fileRef = db
      .collection("dropoff_requests")
      .doc(requestId)
      .collection("files")
      .doc(fileId);

    await db.runTransaction(async (tx) => {
      const fileSnap = await tx.get(fileRef);
      if (!fileSnap.exists) return;

      const cur = fileSnap.data() || {};
      const curTs = cur.lastActivityAt;
      const curMs = curTs && typeof curTs.toMillis === "function" ? curTs.toMillis() : 0;
      const newMs = occurredAt.toMillis();

      // Only update if this event is newer than what we already stored
      if (newMs >= curMs) {
        tx.set(
          fileRef,
          {
            lastActivityAt: occurredAt,
            lastActivityAction: action || "unknown",
            lastActivityActorName: actorName || "—",
            lastActivityActorType: actorType || "unknown",
            lastActivitySurface: surface || null,
            lastActivityEventId: snap.id,
          },
          { merge: true }
        );
      }
    });
  }
);

// ============================
// DROP-OFF upload notification (email)
// Fires when a new file metadata doc is created
// ============================

exports.notifyDropoffUpload = onDocumentCreated(
  {
    region: "us-central1",
    document: "dropoff_requests/{requestId}/files/{fileId}",
    secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET],
  },
  async (event) => {
    try {
      const snap = event.data;
      if (!snap) return;

      const { requestId } = event.params || {};
      if (!requestId) return;

      return;

      const fileData = snap.data() || {};
      const originalName = (fileData.originalName || "").toString().trim();

      // Parent dropoff request
      const reqRef = admin.firestore().collection("dropoff_requests").doc(requestId);

      // Use a transaction to debounce notifications (avoid 10 emails for 10 files)
      await admin.firestore().runTransaction(async (tx) => {
        const reqSnap = await tx.get(reqRef);
        if (!reqSnap.exists) return;

        const req = reqSnap.data() || {};
        const createdByUid = (req.createdByUid || "").toString().trim();
        const createdByEmail = (req.createdByEmail || "").toString().trim();
        const clientName = (req.clientName || "a client").toString().trim();

        if (!createdByUid && !createdByEmail) return;

        // Debounce window (2 minutes). Adjust if you want.
        const lastNotified = req.lastUploadNotifiedAt;
        const lastMs =
          lastNotified && typeof lastNotified.toMillis === "function"
            ? lastNotified.toMillis()
            : 0;

        const nowMs = Date.now();
        const debounceMs = 10 * 1000; // 10 seconds for testing

        if (nowMs - lastMs < debounceMs) {
          // Too soon since last notification -> skip
          return;
        }

        // Stamp notification time
        tx.set(
          reqRef,
          { lastUploadNotifiedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );

        // Build a safe portal link (use your APP_URL param)
        const baseUrl = (APP_URL.value() || "").toString().replace(/\/$/, "");
        const portalUrl = baseUrl ? `${baseUrl}/view-dropoffs` : "";

        // Determine recipient email:
        // Prefer createdByEmail from doc (most reliable), otherwise fall back to Auth lookup
        let to = createdByEmail;
        if (!to) {
          const u = await admin.auth().getUser(createdByUid);
          to = (u.email || "").toString().trim();
        }
        if (!to) return;

        const subject = `${clientName} has uploaded files.`;

        const fileLine = originalName
          ? `<li style="margin:0 0 6px 0;"><b>${safeFilename(originalName)}</b></li>`
          : "";

        const html = `
<div style="font-family:Segoe UI, Arial, sans-serif; background:#ffffff; color:#0B1F33; line-height:1.55;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width:620px; margin:0 auto; background:#ffffff;">

    <!-- Header / Logo -->
    <tr>
      <td style="padding:28px 24px 18px 24px; border-bottom:1px solid #E4E7EC; background:#F9FAFB;">
        <img
          src="${getEmailLogoUrl()}"
          alt="Axume & Associates CPAs"
          width="360"
          style="display:block;border:0;outline:none;text-decoration:none;max-width:360px;height:auto;"
        />
      </td>
    </tr>

    <!-- Body -->
    <tr>
      <td style="padding:24px;">

        <h2 style="margin:0 0 6px 0; font-size:20px; font-weight:700; color:#0B1F33;">
          New file upload received
        </h2>

        <p style="margin:0 0 18px 0; font-size:14px; color:#475467;">
          ${APP_NAME.value()}
        </p>

        <p style="margin:0 0 14px 0;">
          A new file has been uploaded to the secure drop‑off request for
          <b>${clientName}</b>.
        </p>

        ${fileLine
            ? `
        <div style="margin:0 0 18px 0; padding:16px; border:1px solid #E4E7EC; border-radius:8px; background:#F9FAFB;">
          <p style="margin:0 0 8px 0; font-weight:700; color:#0B1F33;">
            Uploaded file
          </p>
          <ul style="margin:0; padding-left:18px;">
            ${fileLine}
          </ul>
        </div>
        `
            : ""
          }

        <p style="margin:0 0 18px 0;">
          To review the uploaded file, open the firm portal using the link below.
        </p>

        ${portalUrl
            ? `
        <div style="margin:0 0 24px 0;">
          <a
            href="${portalUrl}"
            style="display:inline-block; padding:10px 16px; background:#0B1F33; color:#ffffff;
                   text-decoration:none; border-radius:6px; font-weight:600; font-size:14px;"
          >
            Open drop‑off requests
          </a>
        </div>
        `
            : ""
          }

        <p style="margin:0 0 8px 0;">
          If you were not expecting this upload, no action is required.
        </p>

        <p style="margin:20px 0 0 0;">
          Regards,<br/>
          <b>Axume & Associates CPAs</b><br/>
          <span style="font-size:13px; color:#667085;">
            Internal Systems Administration
          </span>
        </p>

      </td>
    </tr>

    <!-- Footer -->
    <tr>
      <td style="padding:16px 24px; border-top:1px solid #E4E7EC;">
        <p style="margin:0; font-size:12px; color:#667085;">
          This message was generated automatically by the firm’s internal systems. Please do not reply.
        </p>
      </td>
    </tr>

  </table>
</div>
`;

        await sendAccountEmail({ to, subject, html });
      });

      return;
    } catch (err) {
      console.error("notifyDropoffUpload failed:", err);
      return;
    }
  }
);


// ============================
// deleteUser (admin-only)
// ============================
exports.deleteUser = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const targetUid = (data?.uid || "").toString().trim();
      const email = normalizeEmail(data?.email);

      if (!targetUid) throw new HttpsError("invalid-argument", "uid is required.");

      if (targetUid === auth.uid) {
        throw new HttpsError("failed-precondition", "You cannot delete yourself.");
      }

      const targetSnap = await admin.firestore().collection("users").doc(targetUid).get();
      const targetRole = (targetSnap.data()?.role || "").toString().toLowerCase().trim();

      if (targetRole === "admin") {
        const adminsSnap = await admin.firestore()
          .collection("users")
          .where("role", "==", "admin")
          .get();

        if (adminsSnap.size <= 1) {
          throw new HttpsError("failed-precondition", "At least one admin must remain.");
        }
      }

      try { await admin.auth().deleteUser(targetUid); } catch (_) { }

      const batch = admin.firestore().batch();
      batch.delete(admin.firestore().collection("users").doc(targetUid));
      if (email) batch.delete(admin.firestore().collection("invites").doc(email));
      await batch.commit();

      return { ok: true, uid: targetUid, email };
    } catch (err) {
      console.error("deleteUser failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Delete failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

// ============================
// updateUser (admin-only)
// ============================
exports.updateUser = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const uid = (data?.uid || "").toString().trim();
      if (!uid) throw new HttpsError("invalid-argument", "uid is required.");

      if (uid === auth.uid) {
        throw new HttpsError("failed-precondition", "You cannot edit yourself here.");
      }

      const email = normalizeEmail(data?.email);
      const role = (data?.role || "").toString().toLowerCase().trim();
      let status = (data?.status || "").toString().toLowerCase().trim();
      const reason = (data?.reason || "").toString().trim();
      const firstName = (data?.firstName ?? "").toString().trim();
      const lastName = (data?.lastName ?? "").toString().trim();
      const displayName = `${firstName} ${lastName}`.trim();
      const communicationsRaw = data?.communications ?? null;

      const allowedRoles = new Set(["associate", "admin"]);
      if (status === "inactive") status = "disabled";
      if (status === "pending") status = "invited";
      const allowedStatus = new Set(["active", "invited", "disabled"]);

      if (email && !email.includes("@")) {
        throw new HttpsError("invalid-argument", "Valid email is required.");
      }
      if (role && !allowedRoles.has(role)) {
        throw new HttpsError("invalid-argument", "Invalid role.");
      }
      if (status && !allowedStatus.has(status)) {
        throw new HttpsError("invalid-argument", "Invalid status.");
      }

      if (email || displayName) {
        await admin.auth().updateUser(uid, {
          ...(email ? { email } : {}),
          ...(displayName ? { displayName } : {}),
        });
      }

      const { ref, data: existing } = await getUserDocByUid(uid);

      if ((existing.role || "").toString().toLowerCase() === "admin" && role === "associate") {
        const adminsSnap = await admin.firestore().collection("users").where("role", "==", "admin").get();
        if (adminsSnap.size <= 1) {
          throw new HttpsError("failed-precondition", "At least one admin must remain.");
        }
      }

      const patch = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: auth.uid,
      };

      if (email) patch.email = email;
      if (role) patch.role = role;
      if (status) patch.status = status;
      if (firstName) patch.firstName = firstName;
      if (lastName) patch.lastName = lastName;
      if (displayName) patch.displayName = displayName;

      if (communicationsRaw && typeof communicationsRaw === "object") {
        const clean = {};
        const wildixExtension = (communicationsRaw.wildixExtension ?? "").toString().trim();
        const clearflySmsNumber = (communicationsRaw.clearflySmsNumber ?? "").toString().trim();
        const clearflyEfaxNumber = (communicationsRaw.clearflyEfaxNumber ?? "").toString().trim();

        if (wildixExtension) clean.wildixExtension = wildixExtension;
        if (clearflySmsNumber) clean.clearflySmsNumber = clearflySmsNumber;
        if (clearflyEfaxNumber) clean.clearflyEfaxNumber = clearflyEfaxNumber;

        if (Object.keys(clean).length > 0) {
          patch.communications = clean;
        }
      }

      await ref.set(patch, { merge: true });

      const commsChange =
        patch.communications
          ? {
            wildixExtension: patch.communications.wildixExtension || null,
            clearflySmsNumber: patch.communications.clearflySmsNumber || null,
            clearflyEfaxNumber: patch.communications.clearflyEfaxNumber || null,
          }
          : null;

      await admin.firestore().collection("auditLogs").add({
        type: "user_update",
        targetUid: uid,
        changes: {
          email: email || null,
          role: role || null,
          status: status || null,
          communications: commsChange,
          firstName: firstName || null,
          lastName: lastName || null,
          displayName: displayName || null,
        },
        reason: reason || null,
        actorUid: auth.uid,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        ok: true,
        uid,
        email: email || existing.email || "",
        role: role || existing.role || "",
        status: status || existing.status || "",
      };
    } catch (err) {
      console.error("updateUser failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Update failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

// ============================
// setUserDisabled (admin-only)
// ============================
exports.setUserDisabled = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const uid = (data?.uid || "").toString().trim();
      const disabled = !!data?.disabled;
      const reason = (data?.reason || "").toString().trim();

      if (!uid) throw new HttpsError("invalid-argument", "uid is required.");
      if (uid === auth.uid) throw new HttpsError("failed-precondition", "You cannot disable yourself.");

      if (disabled) {
        const targetSnap = await admin.firestore().collection("users").doc(uid).get();
        const targetRole = (targetSnap.data()?.role || "").toString().toLowerCase().trim();
        if (targetRole === "admin") {
          const adminsSnap = await admin.firestore().collection("users").where("role", "==", "admin").get();
          if (adminsSnap.size <= 1) {
            throw new HttpsError("failed-precondition", "At least one admin must remain.");
          }
        }
      }

      await admin.auth().updateUser(uid, { disabled });

      const prevSnap = await admin.firestore().collection("users").doc(uid).get();
      const prevStatus = (prevSnap.data()?.status || "").toString().toLowerCase().trim();

      const nextStatus = disabled
        ? "disabled"
        : (prevStatus === "invited" ? "invited" : "active");

      await admin.firestore().collection("users").doc(uid).set(
        {
          status: nextStatus,
          disabled: disabled,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: auth.uid,
        },
        { merge: true }
      );

      await admin.firestore().collection("auditLogs").add({
        type: disabled ? "user_deactivated" : "user_reactivated",
        targetUid: uid,
        reason: reason || null,
        actorUid: auth.uid,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true, uid, disabled };
    } catch (err) {
      console.error("setUserDisabled failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Disable/enable failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

exports.testGraphEmail = onCall(
  {
    region: "us-central1",
    secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated");
    const email = request.auth.token.email;
    if (!email) throw new HttpsError("failed-precondition", "User has no email.");

    await sendAccountEmail({
      to: email,
      subject: "Graph mail test – Axume Portal",
      html: `<p>If you received this, Microsoft Graph SendMail is working.</p><p>Time: ${new Date().toISOString()}</p>`,
    });

    return { ok: true, sentTo: email };
  }
);

// ============================
// sendPasswordReset (admin-only)
// ============================
exports.sendPasswordReset = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const email = normalizeEmail(data?.email);
      const uid = (data?.uid || "").toString().trim();

      if (!email || !email.includes("@")) {
        throw new HttpsError("invalid-argument", "Valid email is required.");
      }
      if (!isValidHttpUrl(APP_URL.value())) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${APP_URL.value()}"`);
      }

      if (uid) {
        const u = await admin.auth().getUser(uid);
        const authEmail = normalizeEmail(u.email);
        if (authEmail && authEmail !== email) {
          throw new HttpsError("failed-precondition", "UID/email mismatch.");
        }
      }

      const resetLink = await admin.auth().generatePasswordResetLink(email, {
        url: APP_URL.value().trim(),
        handleCodeInApp: false,
      });

      await sendAccountEmail({
        to: email,
        subject: `Password reset request – ${APP_NAME.value()}`,
        html: `
<div style="font-family:Segoe UI, Arial, sans-serif; background:#ffffff; color:#0B1F33; line-height:1.55;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width:620px; margin:0 auto; background:#ffffff;">

    <!-- Header / Logo -->
    <tr>
      <td style="padding:28px 24px 18px 24px; border-bottom:1px solid #E4E7EC; background:#F9FAFB;">
        <img
          src="${getEmailLogoUrl()}"
          alt="Axume & Associates CPAs"
          width="360"
          style="display:block;border:0;outline:none;text-decoration:none;max-width:360px;height:auto;"
        />
      </td>
    </tr>

    <!-- Body -->
    <tr>
      <td style="padding:24px;">

        <h2 style="margin:0 0 6px 0; font-size:20px; font-weight:700; color:#0B1F33;">
          Password reset request
        </h2>

        <p style="margin:0 0 18px 0; font-size:14px; color:#475467;">
          ${APP_NAME.value()}
        </p>

        <p style="margin:0 0 14px 0;">
          A request was received to reset the password for your account.
        </p>

        <p style="margin:0 0 18px 0;">
          To proceed, select the button below to set a new password. This link is time‑limited
          and can only be used once.
        </p>

        <!-- Action -->
        <div style="margin:0 0 24px 0; padding:16px; border:1px solid #E4E7EC; border-radius:8px; background:#F9FAFB;">
          <a
            href="${resetLink}"
            style="display:inline-block; padding:10px 16px; background:#0B1F33; color:#ffffff;
                   text-decoration:none; border-radius:6px; font-weight:600; font-size:14px;"
          >
            Reset password
          </a>
        </div>

        <!-- Fallback -->
        <p style="margin:0 0 10px 0; font-size:13px; color:#667085;">
          If the button above does not work, copy and paste the link below into your browser:
        </p>

        <p style="margin:0 0 20px 0; font-size:12px;">
          <a href="${resetLink}" style="color:#0B62D6; word-break:break-all;">
            ${resetLink}
          </a>
        </p>

        <p style="margin:0 0 14px 0;">
          If you did not request a password reset, no further action is required.
          Your account will remain unchanged.
        </p>

        <!-- Support -->
        <p style="margin:0 0 8px 0;">
          For assistance, please contact the firm’s IT administrator at
          <a href="mailto:guillermo@axumecpas.com" style="color:#0B62D6;">
            guillermo@axumecpas.com
          </a>.
        </p>

        <p style="margin:20px 0 0 0;">
          Regards,<br/>
          <b>Axume & Associates CPAs</b><br/>
          <span style="font-size:13px; color:#667085;">
            Internal Systems Administration
          </span>
        </p>

      </td>
    </tr>

    <!-- Footer -->
    <tr>
      <td style="padding:16px 24px; border-top:1px solid #E4E7EC;">
        <p style="margin:0; font-size:12px; color:#667085;">
          This message was generated automatically by the firm’s internal systems. Please do not reply.
        </p>
      </td>
    </tr>

  </table>
</div>
`,
      });

      // ============================
      // ✅ IN-APP NOTIFICATION (staff) — batch upload
      // ============================
      if (createdByUid) {
        await db.collection("notifications").add({
          userUid: createdByUid,
          type: "dropoff_upload",
          title: "Client uploaded files",
          body: `${clientName} uploaded ${finalFiles.length} files`,
          requestId: rid,
          clientName,
          fileCount: finalFiles.length,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          readAt: null,
        });
      }

      await admin.firestore().collection("auditLogs").add({
        type: "password_reset_sent",
        targetUid: uid || null,
        email,
        actorUid: auth.uid,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true, email };
    } catch (err) {
      console.error("sendPasswordReset failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Password reset failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

// ============================
// resendInvite (admin-only)
// ============================
exports.resendInvite = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const uid = (data?.uid || "").toString().trim();
      if (!uid) throw new HttpsError("invalid-argument", "uid is required.");

      const userRecord = await admin.auth().getUser(uid);
      const email = normalizeEmail(userRecord.email);

      if (!email) throw new HttpsError("failed-precondition", "Target user has no email.");
      if (!isValidHttpUrl(APP_URL.value())) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${APP_URL.value()}"`);
      }

      const actionCodeSettings = { url: APP_URL.value().trim(), handleCodeInApp: false };
      const resetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
      const verifyLink = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);

      // Pull first name if available (optional but nice)
      // Try to get a first name for a nicer greeting (optional)
      let firstName = "";
      try {
        const profSnap = await admin.firestore().collection("users").doc(uid).get();
        const prof = profSnap.data() || {};
        firstName = (prof.firstName || "").toString().trim();

        // fallback to displayName if needed
        if (!firstName) {
          const dn = (prof.displayName || userRecord.displayName || "").toString().trim();
          firstName = dn.split(/\s+/)[0] || "";
        }
      } catch (_) {
        // ignore; renderActivationEmail will fall back to "there"
      }

      await sendAccountEmail({
        to: email,
        subject: `Action required: Activate your ${APP_NAME.value()} account`,
        html: renderActivationEmail({
          appName: APP_NAME.value(),
          firstName,
          resetLink,
          verifyLink,
        }),
      });


      await admin.firestore().collection("users").doc(uid).set(
        {
          status: "invited",
          invitedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: auth.uid,
        },
        { merge: true }
      );

      await admin.firestore().collection("invites").doc(email).set(
        {
          email,
          uid,
          status: "invited",
          invitedAt: admin.firestore.FieldValue.serverTimestamp(),
          invitedBy: auth.uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      await admin.firestore().collection("auditLogs").add({
        type: "invite_resent",
        targetUid: uid,
        email,
        actorUid: auth.uid,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true, uid, email };
    } catch (err) {
      console.error("resendInvite failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err?.message ?? String(err));

    }
  }
);

// ============================
// DROP-OFF MODULE (current code)
// ============================

// createDropoffRequest (admin-only)
exports.createDropoffRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    await assertDropoffAccess(auth.uid);

    const firstName = normalizeName(data.firstName);
    const lastName = normalizeName(data.lastName);
    const message = normalizeName(data.message);

    // ✅ NEW optional fields
    const clientEmail = normalizeEmail(data.clientEmail);
    const businessName = normalizeName(data.businessName);

    const expirationMinutes = data.noExpiration === true
      ? null
      : normalizeExpirationMinutes(
          data.expirationMinutes,
          data.expirationHours,
          data.expirationDays
        );
    const expirationHours = expirationMinutes == null
      ? null
      : Math.ceil(expirationMinutes / 60);
    const expiresAt = makeDropoffExpiresAtFromMinutes(expirationMinutes);

    if (!firstName || !lastName) {
      throw new HttpsError("invalid-argument", "First and last name required.");
    }

    // Optional email validation (only if provided)
    if (clientEmail && !clientEmail.includes("@")) {
      throw new HttpsError("invalid-argument", "clientEmail must be a valid email.");
    }

    const token = crypto.randomBytes(32).toString("hex");
    const tokenHash = sha256(token);

    const ref = admin.firestore().collection("dropoff_requests").doc();

    const baseUrl = APP_URL.value();
    const cleanBase = baseUrl.replace(/\/$/, "");
    const url = `${cleanBase}/dropoff?rid=${ref.id}&t=${token}`;

    await ref.set({
      requestId: ref.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdByUid: auth.uid,
      createdByEmail: normalizeEmail(auth.token?.email),

      clientFirstName: firstName,
      clientLastName: lastName,
      clientName: `${firstName} ${lastName}`,

      // ✅ NEW stored fields
      clientEmail: clientEmail || "",
      businessName: businessName || "",

      message: message || "",
      status: "open",
      noExpiration: expirationMinutes == null,
      expirationMinutes,
      expirationHours,
      expirationDays: expirationHours == null ? null : Math.ceil(expirationHours / 24),
      expiresAt,
      expiredAt: null,
      tokenHash,
      url,
      lastViewedAt: null,
      lastUploadedAt: null,
      fileCount: 0,
    });

    return {
      ok: true,
      requestId: ref.id,
      url,
      expiresAtMillis: expiresAt?.toMillis?.() ?? null,
      expirationMinutes,
      expirationHours,
    };

  }
);

exports.validateDropoffLink = onCall({ region: "us-central1" }, async (request) => {
  const { rid, token } = request.data || {};
  if (!rid || !token) {
    throw new HttpsError("invalid-argument", "rid and token required.");
  }

  const ref = admin.firestore().collection("dropoff_requests").doc(rid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Drop-off request not found.");
  }

  const doc = snap.data() || {};

  if (sha256(token) !== doc.tokenHash) {
    throw new HttpsError("permission-denied", "Invalid token.");
  }

  let status = (doc.status || "open").toString();

  if (status === "open" && dropoffExpired(doc)) {
    await markDropoffExpired(ref);
    status = "expired";
  }

  if (status === "open") {
    await ref.set(
      { lastViewedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  const clientName = (doc.clientName || "").toString().trim();
  const businessName = (doc.businessName || "").toString().trim();
  const clientEmail = (doc.clientEmail || "").toString().trim();
  const message = (doc.message || "").toString();

  const createdByUid = (doc.createdByUid || "").toString().trim();
  const createdByEmail = (doc.createdByEmail || "").toString().trim();

  let requestedByName = "";
  let requestedByEmail = createdByEmail;

  if (createdByUid) {
    try {
      const uSnap = await admin.firestore().collection("users").doc(createdByUid).get();
      const u = uSnap.data() || {};
      const first = (u.firstName || "").toString().trim();
      const last = (u.lastName || "").toString().trim();
      const dn = (u.displayName || "").toString().trim();
      requestedByName = (first || last) ? `${first} ${last}`.trim() : dn;
      if (!requestedByEmail) requestedByEmail = (u.email || "").toString().trim();
    } catch (_) { }
  }

  const clamp = (s, max) => (s || "").toString().trim().slice(0, max);

  return {
    ok: true,
    requestId: rid,

    // ✅ existing (do not break UI)
    clientName: clamp(clientName, 120),
    message: clamp(message, 4000),
    status: clamp(status, 20),

    expiresAtMillis: doc.expiresAt?.toMillis?.() ?? null,


    // ✅ NEW (what your UI needs)
    businessName: clamp(businessName, 160),
    clientEmail: clamp(clientEmail, 160),
    requestedByName: clamp(requestedByName, 120),
    requestedByEmail: clamp(requestedByEmail, 160),
  };
});

// getAdminDownloadUrl (admin-only)
exports.getAdminDownloadUrl = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      const { auth, data } = request;

      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign-in required.");
      }

      await assertAdmin(auth.uid);

      const storagePath = (data?.storagePath || "").toString().trim();
      const rawFilename = (data?.filename || "").toString().trim();
      const contentType = (data?.contentType || "").toString().trim();

      if (!storagePath || !rawFilename) {
        throw new HttpsError(
          "invalid-argument",
          "storagePath and filename required."
        );
      }

      const safeName = safeFilename(rawFilename);

      const bucket = admin.storage().bucket();
      const file = bucket.file(storagePath);

      const options = {
        version: "v4",
        action: "read",
        expires: Date.now() + 5 * 60 * 1000,
        responseDisposition:
          `attachment; filename="${safeName}"; ` +
          `filename*=UTF-8''${encodeURIComponent(safeName)}`,
      };

      if (contentType) {
        options.responseType = contentType;
      }

      const [url] = await file.getSignedUrl(options);
      return { ok: true, url };
    } catch (err) {
      console.error("getAdminDownloadUrl failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Could not generate download URL.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

exports.softDeleteUploadFile = onCall(
  { region: "us-central1" },
  async ({ auth, data }) => {
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const docPath = String(data?.docPath || "").trim();
    if (!docPath) {
      throw new HttpsError("invalid-argument", "docPath is required.");
    }

    const fileRef = admin.firestore().doc(docPath);
    const snap = await fileRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "File not found.");
    }

    const file = snap.data();
    const requestId = file.requestId;
    const storagePath = file.storagePath || "";

    // Optional: delete storage object
    if (storagePath) {
      try {
        await admin.storage().bucket().file(storagePath).delete();
      } catch (_) {
        // ignore if already gone
      }
    }

    await fileRef.set(
      {
        deleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedByUid: auth.uid,
        deletedByRole: auth.token?.role || "unknown",
      },
      { merge: true }
    );

    // ✅ Audit log
    await admin.firestore().collection("file_activity").add({
      action: "delete",
      requestId,
      fileId: fileRef.id,
      actorUid: auth.uid,
      actorType: auth.token?.role || "unknown",
      actorEmail: auth.token?.email || "",
      occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true };
  }
);

exports.getDropoffDownloadUrl = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    await assertDropoffAccess(auth.uid); // ✅ admins OR associates w/ capability

    const storagePath = (data?.storagePath ?? "").toString().trim();
    const rawFilename = (data?.filename ?? "").toString().trim();
    const contentType = (data?.contentType ?? "").toString().trim();

    // ✅ NEW: optionally supplied by the app for stronger validation
    const requestIdFromData = (data?.requestId ?? "").toString().trim();
    const fileIdFromData = (data?.fileId ?? "").toString().trim();

    if (!storagePath || !rawFilename) {
      throw new HttpsError(
        "invalid-argument",
        "storagePath and filename required."
      );
    }

    // ✅ Extract requestId from: dropoff_uploads/{requestId}/...
    const parts = storagePath.split("/");
    const requestIdFromPath = parts.length >= 2 ? parts[1] : "";

    // Prefer explicit requestId if provided; otherwise use path-derived
    const requestId = requestIdFromData || requestIdFromPath;

    if (!requestId) {
      throw new HttpsError("invalid-argument", "Invalid storage path.");
    }

    // ✅ NEW: if both are present they must match (prevents cross-request abuse)
    if (requestIdFromData && requestIdFromPath && requestIdFromData !== requestIdFromPath) {
      throw new HttpsError("invalid-argument", "requestId mismatch.");
    }

    // ✅ Load dropoff request
    const reqSnap = await admin
      .firestore()
      .collection("dropoff_requests")
      .doc(requestId)
      .get();

    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "Drop-off request not found.");
    }

    const req = reqSnap.data() || {};

    // ✅ Enforce access:
    // - Admins
    // - Owner of the dropoff
    const callerSnap = await admin
      .firestore()
      .collection("users")
      .doc(auth.uid)
      .get();

    const role = (callerSnap.data()?.role || "").toLowerCase();
    const isAdmin = role === "admin";
    const isOwner = req.createdByUid === auth.uid;

    if (!isAdmin && !isOwner) {
      throw new HttpsError(
        "permission-denied",
        "Not allowed to download files for this request."
      );
    }

    // ============================
    // ✅ NEW: Server-side "deleted" guard (enterprise-grade)
    // ============================
    // If the caller provides fileId, verify metadata and block deleted files.
    if (fileIdFromData) {
      const fileSnap = await admin
        .firestore()
        .collection("dropoff_requests")
        .doc(requestId)
        .collection("files")
        .doc(fileIdFromData)
        .get();

      if (!fileSnap.exists) {
        throw new HttpsError("not-found", "File metadata not found.");
      }

      const fileMeta = fileSnap.data() || {};

      // If file is marked deleted -> block download immediately
      if (fileMeta.deleted === true) {
        throw new HttpsError(
          "failed-precondition",
          "This file was deleted and is no longer available for download."
        );
      }

      // Optional hardening: ensure the storagePath matches the file record
      const metaPath = (fileMeta.storagePath || "").toString().trim();
      if (metaPath && metaPath !== storagePath) {
        throw new HttpsError(
          "invalid-argument",
          "storagePath does not match the file record."
        );
      }
    }

    // ✅ Generate signed URL
    const safeName = safeFilename(rawFilename);
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);

    const options = {
      version: "v4",
      action: "read",
      expires: Date.now() + 5 * 60 * 1000,
      responseDisposition:
        `attachment; filename="${safeName}"; ` +
        `filename*=UTF-8''${encodeURIComponent(safeName)}`,
    };

    if (contentType) {
      options.responseType = contentType;
    }

    const [url] = await file.getSignedUrl(options);

    return { ok: true, url };
  }
);

// ============================
// getDropoffZipDownloadUrl (admin OR owner)
// Creates a ZIP in Cloud Storage and returns a signed download URL
// ============================

/*
exports.getDropoffZipDownloadUrl = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

    // Same gate as your dropoff module
    await assertDropoffAccess(auth.uid);

    const requestId = String(data?.requestId || "").trim();
    const fileIds = Array.isArray(data?.fileIds) ? data.fileIds : [];

    if (!requestId) {
      throw new HttpsError("invalid-argument", "requestId is required.");
    }
    if (!Array.isArray(fileIds) || fileIds.length < 2) {
      throw new HttpsError(
        "invalid-argument",
        "fileIds must be an array with at least 2 items."
      );
    }

    const db = admin.firestore();

    // Load dropoff request
    const reqSnap = await db.collection("dropoff_requests").doc(requestId).get();
    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "Drop-off request not found.");
    }
    const req = reqSnap.data() || {};
    const ownerUid = String(req.createdByUid || "").trim();

    // Determine caller role (admin/owner enforcement like your single-file download)
    const callerSnap = await db.collection("users").doc(auth.uid).get();
    const role = String(callerSnap.data()?.role || "").toLowerCase().trim();
    const isAdmin = role === "admin";
    const isOwner = ownerUid && ownerUid === auth.uid;

    if (!isAdmin && !isOwner) {
      throw new HttpsError(
        "permission-denied",
        "Not allowed to download files for this request."
      );
    }

    // Fetch file metadata docs and build list of eligible files
    const filesCol = db
      .collection("dropoff_requests")
      .doc(requestId)
      .collection("files");

    const wanted = fileIds.map((x) => String(x || "").trim()).filter(Boolean);

    // Limit for safety (enterprise guardrail)
    const MAX_FILES = 75;
    if (wanted.length > MAX_FILES) {
      throw new HttpsError(
        "failed-precondition",
        `Too many files selected. Max is ${MAX_FILES}.`
      );
    }

    const metas = [];
    const seenNames = new Set();

    for (const fid of wanted) {
      const snap = await filesCol.doc(fid).get();
      if (!snap.exists) continue;
      const m = snap.data() || {};

      // Enforce not deleted (same as your single-file guard)
      if (m.deleted === true) continue;

      const storagePath = String(m.storagePath || "").trim();
      if (!storagePath) continue;

      // Create a safe, unique filename inside the zip
      let name = safeFilename(String(m.originalName || `file-${fid}`));
      if (!name) name = `file-${fid}`;

      // Avoid collisions
      if (seenNames.has(name)) {
        const dot = name.lastIndexOf(".");
        const base = dot > 0 ? name.slice(0, dot) : name;
        const ext = dot > 0 ? name.slice(dot) : "";
        let n = 2;
        while (seenNames.has(`${base} (${n})${ext}`)) n++;
        name = `${base} (${n})${ext}`;
      }
      seenNames.add(name);

      metas.push({ fid, storagePath, name });
    }

    if (metas.length < 2) {
      throw new HttpsError(
        "failed-precondition",
        "Not enough eligible files to zip (files may be deleted or unavailable)."
      );
    }

    // Write zip to Cloud Storage
    const bucket = admin.storage().bucket();
    const ts = Date.now();
    const zipObjectPath = `bulk_zips/${requestId}/${auth.uid}/${ts}.zip`;
    const zipFile = bucket.file(zipObjectPath);

    const zipWriteStream = zipFile.createWriteStream({
      resumable: false,
      contentType: "application/zip",
      metadata: {
        cacheControl: "private, max-age=0, no-transform",
      },
    });

    const archive = archiver("zip", { zlib: { level: 9 } });

    // Pipe archive into the storage write stream
    archive.pipe(zipWriteStream);

    // Append each file as a stream
    for (const f of metas) {
      const src = bucket.file(f.storagePath).createReadStream();
      archive.append(src, { name: f.name });
    }

    // Finalize the zip
    await new Promise((resolve, reject) => {
      zipWriteStream.on("finish", resolve);
      zipWriteStream.on("error", reject);
      archive.on("error", reject);
      archive.finalize();
    });

    // Create a signed URL (short-lived like your single-file)
    const safeZipName = safeFilename(
      `Dropoff_${requestId}_${new Date(ts).toISOString().slice(0, 10)}.zip`
    );

    const [url] = await zipFile.getSignedUrl({
      version: "v4",
      action: "read",
      expires: Date.now() + 5 * 60 * 1000,
      responseDisposition:
        `attachment; filename="${safeZipName}"; ` +
        `filename*=UTF-8''${encodeURIComponent(safeZipName)}`,
      responseType: "application/zip",
    });

    return {
      ok: true,
      url,
      zipObjectPath,
      fileCount: metas.length,
      skipped: wanted.length - metas.length,
    };
  }
);
*/

exports.getDropoffZipDownloadUrl = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated");

      await assertDropoffAccess(auth.uid);

      const requestId = String(data?.requestId || "").trim();
      const fileIds = Array.isArray(data?.fileIds) ? data.fileIds : [];
      const requestedFiles = Array.isArray(data?.files)
        ? data.files
          .map((item) => ({
            requestId: String(item?.requestId || "").trim(),
            fileId: String(item?.fileId || "").trim(),
          }))
          .filter((item) => item.requestId && item.fileId)
        : [];

      if (requestedFiles.length === 0 && (!requestId || fileIds.length === 0)) {
        throw new HttpsError(
          "invalid-argument",
          "files[] or requestId and fileIds[] are required."
        );
      }

      const targets = requestedFiles.length > 0
        ? requestedFiles
        : fileIds
          .map((fileId) => ({
            requestId,
            fileId: String(fileId || "").trim(),
          }))
          .filter((item) => item.requestId && item.fileId);

      if (targets.length < 2) {
        throw new HttpsError(
          "invalid-argument",
          "At least two files are required for a ZIP download."
        );
      }

      const MAX_FILES = 75;
      if (targets.length > MAX_FILES) {
        throw new HttpsError(
          "failed-precondition",
          `Too many files selected. Max is ${MAX_FILES}.`
        );
      }

      const callerSnap = await db.collection("users").doc(auth.uid).get();
      const caller = callerSnap.data() || {};
      const callerRole = String(caller.role || "").toLowerCase().trim();
      const isAdmin = callerRole === "admin";
      const isAssociate = callerRole === "associate";

      const reqCache = new Map();
      const metas = [];

      for (const target of targets) {
        let req = reqCache.get(target.requestId);
        if (!req) {
          const reqRef = db.collection("dropoff_requests").doc(target.requestId);
          const reqSnap = await reqRef.get();
          if (!reqSnap.exists) continue;

          const reqData = reqSnap.data() || {};
          const isOwner = reqData.createdByUid === auth.uid;
          if (!isAdmin && !isOwner && !isAssociate) continue;

          req = { ref: reqRef, data: reqData, isOwner };
          reqCache.set(target.requestId, req);
        }

        const fileSnap = await req.ref.collection("files").doc(target.fileId).get();
        if (!fileSnap.exists) continue;

        const fileData = fileSnap.data() || {};
        if (fileData.deleted === true) continue;
        if (!fileData.storagePath) continue;

        const fileRequestCreatedByRole = String(fileData.requestCreatedByRole || "").toLowerCase().trim();
        const canAccessFile =
          isAdmin ||
          req.isOwner ||
          (isAssociate && fileRequestCreatedByRole === "associate");
        if (!canAccessFile) continue;

        metas.push({
          requestId: target.requestId,
          fileId: target.fileId,
          storagePath: String(fileData.storagePath || "").trim(),
          originalName: String(fileData.originalName || target.fileId).trim(),
        });
      }

      console.log("ZIP FILE METADATA LOADED", {
        requestedFiles: targets.length,
        foundFiles: metas.length,
        requestCount: reqCache.size,
      });

      if (metas.length < 2) {
        throw new HttpsError(
          "failed-precondition",
          "Not enough eligible files to zip."
        );
      }

      // ✅ Verify dropoff
      // ✅ Prepare temp ZIP
      const bucket = admin.storage().bucket();
      const tmpDir = os.tmpdir();
      const zipPath = path.join(tmpDir, `file_box_${auth.uid}_${Date.now()}.zip`);
      const output = fs.createWriteStream(zipPath);
      const archive = archiver("zip", { zlib: { level: 9 } });

      archive.on("warning", (w) => {
        console.warn("⚠️ ZIP warning:", w);
      });

      archive.on("error", (e) => {
        console.error("❌ ZIP archiver error:", e);
        throw e;
      });

      archive.pipe(output);

      const seenNames = new Set();
      function uniqueZipName(meta) {
        let name = safeFilename(meta.originalName || meta.fileId) || `file-${meta.fileId}`;
        if (!seenNames.has(name)) {
          seenNames.add(name);
          return name;
        }

        const dot = name.lastIndexOf(".");
        const base = dot > 0 ? name.slice(0, dot) : name;
        const ext = dot > 0 ? name.slice(dot) : "";
        let n = 2;
        while (seenNames.has(`${base} (${n})${ext}`)) n++;
        name = `${base} (${n})${ext}`;
        seenNames.add(name);
        return name;
      }

      for (const meta of metas) {
        const file = bucket.file(meta.storagePath);
        archive.append(file.createReadStream(), {
          name: uniqueZipName(meta),
        });
      }

      await archive.finalize();

      await new Promise((res) => output.on("close", res));

      // ✅ Upload ZIP
      const zipStoragePath = `tmp/zips/file_box_${auth.uid}_${Date.now()}.zip`;
      console.log("ZIP CREATED LOCALLY", {
        zipPath,
      });
      await bucket.upload(zipPath, {
        destination: zipStoragePath,
        contentType: "application/zip",
      });

      // ✅ Signed URL
      const [url] = await bucket.file(zipStoragePath).getSignedUrl({
        version: "v4",
        action: "read",
        expires: Date.now() + 5 * 60 * 1000,
        responseDisposition: 'attachment; filename="uploads.zip"',
      });

      return {
        ok: true,
        url,
        fileCount: metas.length,
      };
    } catch (err) {
      console.error("❌ ZIP GENERATION FAILED", {
        message: err?.message,
        stack: err?.stack,
        name: err?.name,
        code: err?.code,
      });

      // If this was already a structured HttpsError, pass it through
      if (err instanceof HttpsError) {
        throw err;
      }

      // Otherwise expose the REAL cause (enterprise-safe)
      throw new HttpsError(
        "internal",
        "ZIP generation failed.",
        {
          cause: err?.message || String(err),
        }
      );
    }

  }
);

function hashSharePassword(password, salt) {
  return crypto
    .createHash("sha256")
    .update(`${salt}:${password}`)
    .digest("hex");
}

function secureShareUrl(shareId) {
  const baseUrl = (APP_URL.value() || "https://portal.axumecpas.com")
    .toString()
    .replace(/\/$/, "");
  return `${baseUrl}/secure-share?sid=${encodeURIComponent(shareId)}`;
}

async function loadAuthorizedFileMetasForShare(auth, targets) {
  await assertDropoffAccess(auth.uid);

  const callerSnap = await db.collection("users").doc(auth.uid).get();
  const caller = callerSnap.data() || {};
  const callerRole = String(caller.role || "").toLowerCase().trim();
  const isAdmin = callerRole === "admin";
  const isAssociate = callerRole === "associate";

  const reqCache = new Map();
  const metas = [];

  for (const target of targets) {
    let req = reqCache.get(target.requestId);
    if (!req) {
      const reqRef = db.collection("dropoff_requests").doc(target.requestId);
      const reqSnap = await reqRef.get();
      if (!reqSnap.exists) continue;

      const reqData = reqSnap.data() || {};
      const isOwner = reqData.createdByUid === auth.uid;
      if (!isAdmin && !isOwner && !isAssociate) continue;

      req = { ref: reqRef, data: reqData, isOwner };
      reqCache.set(target.requestId, req);
    }

    const fileSnap = await req.ref.collection("files").doc(target.fileId).get();
    if (!fileSnap.exists) continue;

    const fileData = fileSnap.data() || {};
    if (fileData.deleted === true) continue;

    const storagePath = String(fileData.storagePath || "").trim();
    if (!storagePath) continue;

    const fileRequestCreatedByRole = String(
      fileData.requestCreatedByRole || ""
    ).toLowerCase().trim();
    const canAccessFile =
      isAdmin ||
      req.isOwner ||
      (isAssociate && fileRequestCreatedByRole === "associate");
    if (!canAccessFile) continue;

    metas.push({
      requestId: target.requestId,
      fileId: target.fileId,
      storagePath,
      originalName: String(fileData.originalName || target.fileId).trim(),
      contentType: String(fileData.contentType || "").trim(),
      sizeBytes: Number(fileData.sizeBytes || 0),
    });
  }

  return metas;
}

function renderSecureShareEmail({
  appName,
  recipientName,
  senderName,
  message,
  shareUrl,
  expiresLabel,
  fileCount,
}) {
  const greeting = recipientName ? `Hello ${escapeHtml(recipientName)},` : "Hello,";
  const safeMessage = String(message || "").trim();
  const fileLabel = `${fileCount} ${fileCount === 1 ? "file" : "files"}`;
  const safeAppName = escapeHtml(appName);
  const safeSenderName = escapeHtml(senderName || "Axume & Associates CPAs");
  const safeShareUrl = escapeHtml(shareUrl);
  const safeExpiresLabel = escapeHtml(expiresLabel);

  return `
<div style="margin:0; padding:0; background:#F6F7F9; font-family:Arial, Helvetica, sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F7F9; padding:24px 0;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:620px; background:#FFFFFF; border:1px solid #E4E7EC;">
          <tr>
            <td style="padding:22px 24px; border-bottom:1px solid #E4E7EC;">
              <img src="${getEmailLogoUrl()}" alt="${safeAppName}" style="max-height:42px; max-width:260px;" />
            </td>
          </tr>
          <tr>
            <td style="padding:24px;">
              <h1 style="margin:0 0 12px 0; font-size:20px; line-height:1.3; color:#101828;">Secure files shared with you</h1>
              <p style="margin:0 0 14px 0; font-size:14px; line-height:1.55; color:#344054;">${greeting}</p>
              <p style="margin:0 0 14px 0; font-size:14px; line-height:1.55; color:#344054;">
                ${safeSenderName} shared ${fileLabel} with you through ${safeAppName}.
              </p>
              ${safeMessage ? `<p style="margin:0 0 14px 0; font-size:14px; line-height:1.55; color:#344054;">${escapeHtml(safeMessage).replace(/\n/g, "<br/>")}</p>` : ""}
              <p style="margin:0 0 20px 0; font-size:13px; line-height:1.45; color:#667085;">
                This link is password protected. Use the password provided separately by our office.
              </p>
              <p style="margin:0 0 20px 0;">
                <a href="${safeShareUrl}" style="display:inline-block; background:#0B62D6; color:#FFFFFF; text-decoration:none; font-size:14px; font-weight:700; padding:11px 16px; border-radius:6px;">
                  Open secure files
                </a>
              </p>
              <p style="margin:0; font-size:12.5px; line-height:1.45; color:#667085;">
                ${safeExpiresLabel}
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:16px 24px; border-top:1px solid #E4E7EC; font-size:12px; color:#667085;">
              This message was generated by ${safeAppName}. Please do not forward this link.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</div>`;
}

exports.createSecureFileShare = onCall(
  { region: "us-central1", secrets: [GRAPH_TENANT_ID, GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET] },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

      const targets = Array.isArray(data?.files)
        ? data.files
          .map((item) => ({
            requestId: String(item?.requestId || "").trim(),
            fileId: String(item?.fileId || "").trim(),
          }))
          .filter((item) => item.requestId && item.fileId)
        : [];

      if (targets.length === 0) {
        throw new HttpsError("invalid-argument", "Select at least one file.");
      }
      if (targets.length > 75) {
        throw new HttpsError("failed-precondition", "Too many files selected. Max is 75.");
      }

      const password = String(data?.password || "").trim();
      if (password.length < 6) {
        throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
      }

      const recipientEmail = normalizeEmail(data?.recipientEmail);
      if (recipientEmail && !recipientEmail.includes("@")) {
        throw new HttpsError("invalid-argument", "Enter a valid client email.");
      }

      const recipientName = normalizeName(data?.recipientName);
      const message = normalizeName(data?.message);
      const sendEmail = data?.sendEmail === true;
      if (sendEmail && !recipientEmail) {
        throw new HttpsError("invalid-argument", "Client email is required to send email.");
      }

      const expirationDaysRaw = Number(data?.expirationDays || 7);
      const expirationDays = [1, 7, 14, 30].includes(expirationDaysRaw)
        ? expirationDaysRaw
        : 7;

      const metas = await loadAuthorizedFileMetasForShare(auth, targets);
      if (metas.length === 0) {
        throw new HttpsError("failed-precondition", "No eligible files selected.");
      }

      const salt = crypto.randomBytes(16).toString("hex");
      const passwordHash = hashSharePassword(password, salt);
      const ref = db.collection("secure_file_shares").doc();
      const expiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + expirationDays * 24 * 60 * 60 * 1000
      );
      const shareUrl = secureShareUrl(ref.id);

      const callerSnap = await db.collection("users").doc(auth.uid).get();
      const caller = callerSnap.data() || {};
      const first = normalizeName(caller.firstName);
      const last = normalizeName(caller.lastName);
      const displayName = normalizeName(caller.displayName);
      const senderName = first || last
        ? `${first} ${last}`.trim()
        : (displayName || normalizeEmail(auth.token?.email) || "Axume & Associates CPAs");

      await ref.set({
        shareId: ref.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdByUid: auth.uid,
        createdByEmail: normalizeEmail(auth.token?.email),
        createdByName: senderName,
        recipientEmail: recipientEmail || "",
        recipientName: recipientName || "",
        message: message || "",
        status: "active",
        expiresAt,
        passwordSalt: salt,
        passwordHash,
        files: metas,
        fileCount: metas.length,
        lastViewedAt: null,
        lastDownloadedAt: null,
      });

      if (sendEmail) {
        await sendAccountEmail({
          to: recipientEmail,
          subject: "Secure files from Axume & Associates CPAs",
          html: renderSecureShareEmail({
            appName: APP_NAME.value() || "Axume Portal",
            recipientName,
            senderName,
            message,
            shareUrl,
            expiresLabel: `This secure link expires in ${expirationDays} ${expirationDays === 1 ? "day" : "days"}.`,
            fileCount: metas.length,
          }),
        });
      }

      await db.collection("auditLogs").add({
        type: "secure_file_share_created",
        shareId: ref.id,
        fileCount: metas.length,
        recipientEmail: recipientEmail || "",
        emailed: sendEmail,
        actorUid: auth.uid,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        ok: true,
        shareId: ref.id,
        url: shareUrl,
        fileCount: metas.length,
        emailed: sendEmail,
        expiresAtMillis: expiresAt.toMillis(),
      };
    } catch (err) {
      console.error("createSecureFileShare failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Could not create secure share.", {
        message: err?.message || String(err),
      });
    }
  }
);

exports.openSecureFileShare = onCall(
  { region: "us-central1" },
  async (request) => {
    const shareId = String(request.data?.shareId || "").trim();
    const password = String(request.data?.password || "").trim();
    if (!shareId || !password) {
      throw new HttpsError("invalid-argument", "Share link and password are required.");
    }

    const ref = db.collection("secure_file_shares").doc(shareId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Secure share not found.");

    const share = snap.data() || {};
    if (String(share.status || "").toLowerCase() !== "active") {
      throw new HttpsError("failed-precondition", "This secure share is no longer active.");
    }

    const expiresAt = share.expiresAt;
    if (expiresAt && expiresAt.toMillis && expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "This secure share has expired.");
    }

    const expected = String(share.passwordHash || "");
    const actual = hashSharePassword(password, String(share.passwordSalt || ""));
    if (!expected || actual !== expected) {
      throw new HttpsError("permission-denied", "The password is incorrect.");
    }

    await ref.set(
      { lastViewedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    const files = Array.isArray(share.files) ? share.files : [];
    return {
      ok: true,
      shareId,
      recipientName: share.recipientName || "",
      message: share.message || "",
      expiresAtMillis: expiresAt?.toMillis?.() ?? null,
      files: files.map((f) => ({
        fileId: String(f.fileId || ""),
        originalName: String(f.originalName || "File"),
        contentType: String(f.contentType || ""),
        sizeBytes: Number(f.sizeBytes || 0),
      })),
    };
  }
);

exports.getSecureShareDownloadUrl = onCall(
  { region: "us-central1" },
  async (request) => {
    const shareId = String(request.data?.shareId || "").trim();
    const password = String(request.data?.password || "").trim();
    const fileId = String(request.data?.fileId || "").trim();
    if (!shareId || !password || !fileId) {
      throw new HttpsError("invalid-argument", "Share link, password, and file are required.");
    }

    const ref = db.collection("secure_file_shares").doc(shareId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Secure share not found.");

    const share = snap.data() || {};
    if (String(share.status || "").toLowerCase() !== "active") {
      throw new HttpsError("failed-precondition", "This secure share is no longer active.");
    }

    const expiresAt = share.expiresAt;
    if (expiresAt && expiresAt.toMillis && expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "This secure share has expired.");
    }

    const expected = String(share.passwordHash || "");
    const actual = hashSharePassword(password, String(share.passwordSalt || ""));
    if (!expected || actual !== expected) {
      throw new HttpsError("permission-denied", "The password is incorrect.");
    }

    const files = Array.isArray(share.files) ? share.files : [];
    const meta = files.find((f) => String(f.fileId || "") === fileId);
    if (!meta || !meta.storagePath) {
      throw new HttpsError("not-found", "File not found in this secure share.");
    }

    const safeName = safeFilename(meta.originalName || fileId);
    const [url] = await admin.storage().bucket().file(meta.storagePath).getSignedUrl({
      version: "v4",
      action: "read",
      expires: Date.now() + 5 * 60 * 1000,
      responseDisposition:
        `attachment; filename="${safeName}"; ` +
        `filename*=UTF-8''${encodeURIComponent(safeName)}`,
      ...(meta.contentType ? { responseType: meta.contentType } : {}),
    });

    await ref.set(
      { lastDownloadedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    return { ok: true, url };
  }
);

exports.listSecureFileShares = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

    await assertDropoffAccess(auth.uid);

    const callerSnap = await db.collection("users").doc(auth.uid).get();
    const caller = callerSnap.data() || {};
    const role = String(caller.role || "").toLowerCase().trim();
    const isAdmin = role === "admin";

    const snap = await db
      .collection("secure_file_shares")
      .orderBy("createdAt", "desc")
      .limit(200)
      .get();

    const now = Date.now();
    const shares = [];

    for (const doc of snap.docs) {
      const share = doc.data() || {};
      if (!isAdmin && share.createdByUid !== auth.uid) continue;

      const expiresAtMillis = share.expiresAt?.toMillis?.() ?? null;
      const rawStatus = String(share.status || "active").toLowerCase().trim();
      const expired = expiresAtMillis != null && expiresAtMillis <= now;
      const status = rawStatus === "revoked"
        ? "revoked"
        : expired
          ? "expired"
          : "active";

      const files = Array.isArray(share.files) ? share.files : [];
      shares.push({
        shareId: doc.id,
        url: secureShareUrl(doc.id),
        recipientName: String(share.recipientName || ""),
        recipientEmail: String(share.recipientEmail || ""),
        createdByName: String(share.createdByName || ""),
        createdByEmail: String(share.createdByEmail || ""),
        createdAtMillis: share.createdAt?.toMillis?.() ?? null,
        expiresAtMillis,
        lastViewedAtMillis: share.lastViewedAt?.toMillis?.() ?? null,
        lastDownloadedAtMillis: share.lastDownloadedAt?.toMillis?.() ?? null,
        status,
        fileCount: Number(share.fileCount || files.length || 0),
        files: files.map((f) => ({
          fileId: String(f.fileId || ""),
          originalName: String(f.originalName || "File"),
          contentType: String(f.contentType || ""),
          sizeBytes: Number(f.sizeBytes || 0),
        })),
      });
    }

    return { ok: true, shares };
  }
);

exports.revokeSecureFileShare = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

    await assertDropoffAccess(auth.uid);

    const shareId = String(data?.shareId || "").trim();
    if (!shareId) {
      throw new HttpsError("invalid-argument", "shareId is required.");
    }

    const ref = db.collection("secure_file_shares").doc(shareId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Secure share not found.");
    }

    const share = snap.data() || {};
    const callerSnap = await db.collection("users").doc(auth.uid).get();
    const caller = callerSnap.data() || {};
    const role = String(caller.role || "").toLowerCase().trim();
    const isAdmin = role === "admin";
    const isOwner = share.createdByUid === auth.uid;

    if (!isAdmin && !isOwner) {
      throw new HttpsError("permission-denied", "Not allowed to revoke this share.");
    }

    await ref.set(
      {
        status: "revoked",
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        revokedByUid: auth.uid,
      },
      { merge: true }
    );

    await db.collection("auditLogs").add({
      type: "secure_file_share_revoked",
      shareId,
      actorUid: auth.uid,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, shareId, status: "revoked" };
  }
);

// ============================
// logFileActivity (admin OR owner) — append-only audit trail
// action: 'view' (details/history), 'download' (optional later)
// ============================
exports.logFileActivity = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

    // Must have dropoff access capability (same gate as dropoff module)
    await assertDropoffAccess(auth.uid);

    const requestId = (data?.requestId || "").toString().trim();
    const fileId = (data?.fileId || "").toString().trim();
    const action = (data?.action || "view").toString().toLowerCase().trim(); // view | download
    const surface = (data?.surface || "").toString().toLowerCase().trim();   // details | history

    if (!requestId || !fileId) {
      throw new HttpsError("invalid-argument", "requestId and fileId are required.");
    }
    if (!["view", "download"].includes(action)) {
      throw new HttpsError("invalid-argument", "action must be 'view' or 'download'.");
    }

    // Load dropoff request
    const db = admin.firestore();
    const reqSnap = await db.collection("dropoff_requests").doc(requestId).get();
    if (!reqSnap.exists) throw new HttpsError("not-found", "Drop-off request not found.");

    const req = reqSnap.data() || {};
    const ownerUid = (req.createdByUid || "").toString().trim();

    // Determine caller role
    const callerSnap = await db.collection("users").doc(auth.uid).get();
    const caller = callerSnap.data() || {};
    const role = (caller.role || "").toString().toLowerCase().trim();
    const isAdmin = role === "admin";
    const isOwner = ownerUid && ownerUid === auth.uid;

    if (!isAdmin && !isOwner) {
      throw new HttpsError("permission-denied", "Not allowed to view activity for this request.");
    }

    // Actor display info
    const first = (caller.firstName || "").toString().trim();
    const last = (caller.lastName || "").toString().trim();
    const dn = (caller.displayName || "").toString().trim();
    const actorName = (first || last) ? `${first} ${last}`.trim() : dn;
    const actorEmail = (caller.email || auth.token?.email || "").toString().trim();

    // Append-only event
    await db.collection("file_activity").add({
      requestId,
      fileId,
      action,
      surface: surface || null,

      actorType: role || "unknown", // admin | associate | unknown
      actorUid: auth.uid,
      actorName: actorName || actorEmail || "—",
      actorEmail: actorEmail || "",

      // Useful context (helps filtering / reporting)
      requestCreatedByUid: ownerUid || "",
      requestCreatedByRole: (req.createdByRole || '').toString().toLowerCase(),
      occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true };
  }
);


// ============================
// deleteDropoffUploadsBatch (admin-only)
// ============================
/*
exports.deleteDropoffUploadsBatch = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      const { auth, data } = request;

      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign-in required.");
      }

      await assertAdmin(auth.uid);

      const items = Array.isArray(data?.items) ? data.items : [];
      if (items.length === 0) {
        throw new HttpsError(
          "invalid-argument",
          "items[] is required and cannot be empty."
        );
      }

      const bucket = admin.storage().bucket();
      const batch = admin.firestore().batch();

      for (const item of items) {
        const docPath = (item?.docPath || "").toString().trim();
        const storagePath = (item?.storagePath || "").toString().trim();

        if (docPath) {
          batch.delete(admin.firestore().doc(docPath));
        }

        if (storagePath) {
          await bucket.file(storagePath).delete().catch(() => { });
        }
      }

      await batch.commit();

      await admin.firestore().collection("auditLogs").add({
        type: "uploads_bulk_delete",
        count: items.length,
        actorUid: auth.uid,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true, deleted: items.length };
    } catch (err) {
      console.error("deleteDropoffUploadsBatch failed:", err);

      if (err instanceof HttpsError) throw err;

      throw new HttpsError("internal", "Bulk delete failed.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

*/

// ============================
// deleteDropoffUploadsBatch (admin-only)
// Deletes Firestore metadata doc + Storage object
// ============================
exports.deleteDropoffUploadsBatch = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");
      await assertAdmin(auth.uid);

      const items = Array.isArray(data?.items) ? data.items : [];
      if (items.length === 0) {
        throw new HttpsError("invalid-argument", "items[] is required.");
      }

      const db = admin.firestore();
      const bucket = admin.storage().bucket();

      const affectedRequestIds = new Set();

      // Delete files
      for (const it of items) {
        const docPath = (it?.docPath || "").toString().trim();
        if (!docPath) continue;

        // Extract requestId from:
        // dropoff_requests/{requestId}/files/{fileId}
        const parts = docPath.split("/");
        const idx = parts.indexOf("dropoff_requests");
        if (idx !== -1 && parts.length > idx + 1) {
          affectedRequestIds.add(parts[idx + 1]);
        }

        const fileRef = db.doc(docPath);
        const snap = await fileRef.get();
        if (!snap.exists) continue;

        const file = snap.data() || {};
        const storagePath = (file.storagePath || "").toString().trim();

        // ✅ Delete storage object ONLY (safe, non‑blocking)
        if (storagePath) {
          await bucket.file(storagePath).delete().catch(() => { });
        }

        // ✅ SOFT DELETE metadata (this preserves Upload Link history)
        await fileRef.set(
          {
            deleted: true,
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
            deletedByUid: auth.uid,
            deletedByRole: 'admin',
          },
          { merge: true }
        );
      }

      // ✅ Recalculate counters per request
      for (const requestId of affectedRequestIds) {
        const reqRef = db.collection("dropoff_requests").doc(requestId);
        const filesSnap = await reqRef.collection("files").get();

        let lastUploadedAt = null;
        for (const d of filesSnap.docs) {
          const ts = d.data().createdAt;
          if (
            ts &&
            (!lastUploadedAt || ts.toMillis() > lastUploadedAt.toMillis())
          ) {
            lastUploadedAt = ts;
          }
        }

        await reqRef.set(
          {
            fileCount: filesSnap.size,
            lastUploadedAt: lastUploadedAt || null,
          },
          { merge: true }
        );
      }

      await db.collection("auditLogs").add({
        type: "uploads_bulk_delete",
        deleted: items.length,
        affectedRequests: Array.from(affectedRequestIds),
        actorUid: auth.uid,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true, deleted: items.length };
    } catch (err) {
      console.error("deleteDropoffUploadsBatch failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Bulk delete failed.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

exports.setDropoffStatus = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

    // ✅ allow associates with dropoff access
    await assertDropoffAccess(auth.uid);

    const requestId = (data?.requestId || "").toString().trim();
    const status = (data?.status || "").toString().toLowerCase().trim();
    if (!requestId) throw new HttpsError("invalid-argument", "requestId required.");
    if (!["open", "closed", "expired"].includes(status)) {
      throw new HttpsError(
        "invalid-argument",
        "status must be 'open', 'closed', or 'expired'"
      );
    }


    const ref = admin.firestore().collection("dropoff_requests").doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Drop-off request not found.");

    const doc = snap.data() || {};

    // ✅ ownership OR admin
    const caller = await admin.firestore().collection("users").doc(auth.uid).get();
    const role = (caller.data()?.role || "").toString().toLowerCase().trim();
    const isAdmin = role === "admin";
    const isOwner = doc.createdByUid === auth.uid;

    if (!isAdmin && !isOwner) {
      throw new HttpsError("permission-denied", "Not allowed to update this request.");
    }

    const update = {
      status,
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedBy: auth.uid,
    };

    if (status === "open") {
      const expirationMinutes = data?.noExpiration === true
        ? null
        : normalizeExpirationMinutes(
            data?.expirationMinutes,
            data?.expirationHours,
            data?.expirationDays
          );
      const expirationHours = expirationMinutes == null
        ? null
        : Math.ceil(expirationMinutes / 60);
      update.noExpiration = expirationMinutes == null;
      update.expirationMinutes = expirationMinutes;
      update.expirationHours = expirationHours;
      update.expirationDays = expirationHours == null ? null : Math.ceil(expirationHours / 24);
      update.expiresAt = makeDropoffExpiresAtFromMinutes(expirationMinutes);
      update.expiredAt = null;
    }

    await ref.set(update, { merge: true });

    return { ok: true, requestId, status };
  }
);

// deleteDropoffRequest (admin OR owner with dropoff access)
exports.deleteDropoffRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

    // ✅ Allow admins OR associates with dropoff capability
    await assertDropoffAccess(auth.uid);

    const requestId = (data?.requestId || "").toString().trim();
    if (!requestId) throw new HttpsError("invalid-argument", "requestId required.");

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    const ref = db.collection("dropoff_requests").doc(requestId);
    const reqSnap = await ref.get();
    if (!reqSnap.exists) throw new HttpsError("not-found", "Drop-off request not found.");

    const req = reqSnap.data() || {};
    const createdByUid = (req.createdByUid || "").toString().trim();

    // ✅ Enforce: owner OR admin
    const callerSnap = await db.collection("users").doc(auth.uid).get();
    const callerRole = ((callerSnap.data()?.role || "") + "").toLowerCase().trim();
    const isAdmin = callerRole === "admin";
    const isOwner = createdByUid && createdByUid === auth.uid;

    if (!isAdmin && !isOwner) {
      throw new HttpsError("permission-denied", "Not allowed to delete this request.");
    }

    // ✅ Soft-delete the drop-off request (archive only)
    await ref.set(
      {
        status: "deleted",
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedBy: auth.uid,
      },
      { merge: true }
    );

    // Optional: audit log
    await db.collection("auditLogs").add({
      type: "dropoff_deleted",
      requestId,
      actorUid: auth.uid,
      actorRole: callerRole || null,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true };
  }
);

// purgeDropoffRequest (admin OR owner) — PERMANENT delete
exports.purgeDropoffRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");

    await assertDropoffAccess(auth.uid);

    const requestId = (data?.requestId || "").toString().trim();
    if (!requestId) throw new HttpsError("invalid-argument", "requestId required.");

    const ref = db.collection("dropoff_requests").doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Drop-off request not found.");

    const doc = snap.data() || {};
    const createdByUid = (doc.createdByUid || "").toString().trim();
    const status = (doc.status || "").toString().toLowerCase().trim();

    // Safety rail: only allow purging archived links
    if (status !== "deleted") {
      throw new HttpsError(
        "failed-precondition",
        "Only archived links can be permanently deleted."
      );
    }

    // Enforce owner/admin (same pattern as deleteDropoffRequest)
    const callerSnap = await db.collection("users").doc(auth.uid).get();
    const callerRole = ((callerSnap.data()?.role || "") + "").toLowerCase().trim();
    const isAdmin = callerRole === "admin";
    const isOwner = createdByUid && createdByUid === auth.uid;

    if (!isAdmin && !isOwner) {
      throw new HttpsError("permission-denied", "Not allowed to purge this request.");
    }

    const bucket = admin.storage().bucket();

    // 1) Delete Storage objects referenced by files subcollection
    const filesRef = ref.collection("files");
    const filesSnap = await filesRef.get();

    let deletedStorage = 0;
    for (const d of filesSnap.docs) {
      const f = d.data() || {};
      const storagePath = (f.storagePath || "").toString().trim();
      if (storagePath) {
        try {
          await bucket.file(storagePath).delete();
          deletedStorage++;
        } catch (_) {
          // ignore if already gone
        }
      }
    }

    // 2) Delete files subcollection docs in batches
    const BATCH_SIZE = 400;
    const fileDocs = filesSnap.docs;
    for (let i = 0; i < fileDocs.length; i += BATCH_SIZE) {
      const batch = db.batch();
      for (const d of fileDocs.slice(i, i + BATCH_SIZE)) {
        batch.delete(d.ref);
      }
      await batch.commit();
    }

    // 3) Delete the dropoff request doc itself
    await ref.delete();

    // Optional: audit
    await db.collection("auditLogs").add({
      type: "dropoff_purged",
      requestId,
      deletedStorage,
      actorUid: auth.uid,
      actorRole: callerRole || null,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, requestId, deletedStorage };
  }
);

// ============================
// markUserActive (self-callable, post-login)
// ============================
exports.markUserActive = onCall(
  { region: "us-central1" },
  async (request) => {
    console.log("markUserActive called");

    const { auth } = request;
    if (!auth) {
      console.log("NO AUTH CONTEXT");
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    console.log("AUTH UID:", auth.uid);

    const ref = admin.firestore().collection("users").doc(auth.uid);
    const snap = await ref.get();

    if (!snap.exists) {
      console.log("USER DOC DOES NOT EXIST");
      return { ok: true };
    }

    const status = (snap.data().status || "").toLowerCase();
    console.log("CURRENT STATUS:", status);

    if (status === "invited") {
      console.log("UPDATING STATUS TO ACTIVE");
      await ref.set(
        {
          status: "active",
          activatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSignInAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else {
      console.log("STATUS NOT INVITED — JUST UPDATING LAST SIGN-IN");
      await ref.set(
        {
          lastSignInAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    return { ok: true };
  }
);

exports.markNotificationsViewed = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated");
    }

    await admin.firestore()
      .collection("users")
      .doc(request.auth.uid)
      .set(
        {
          lastNotificationsViewedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    return { ok: true };
  }
);

exports.markNotificationsRead = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User not authenticated");
    }

    const uid = request.auth.uid;
    const notificationId = String(request.data?.notificationId || "").trim();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // ✅ Mark ONE notification (when user clicks a row)
    if (notificationId) {
      const ref = db.collection("notifications").doc(notificationId);
      const snap = await ref.get();
      if (!snap.exists) return { updated: 0 };

      const data = snap.data() || {};
      if (data.userUid !== uid) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }

      if (data.readAt != null) return { updated: 0 };

      await ref.update({ readAt: now });
      return { updated: 1 };
    }

    // ✅ Mark ALL unread (when user clicks "Mark all as read")
    const notificationsRef = db
      .collection("notifications")
      .where("userUid", "==", uid)
      .where("readAt", "==", null);

    let totalUpdated = 0;

    while (true) {
      const snap = await notificationsRef.limit(500).get();
      if (snap.empty) break;

      const batch = db.batch();
      snap.docs.forEach((doc) => {
        batch.update(doc.ref, { readAt: now });
      });

      await batch.commit();
      totalUpdated += snap.size;

      if (snap.size < 500) break;
    }

    return { updated: totalUpdated };
  }
);
