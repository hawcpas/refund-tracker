const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const {
  defineSecret,
  defineString,
  defineInt,
  defineBoolean,
} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();

// ============================
// Secrets
// ============================
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");

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
// Helpers
// ============================
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
                src="https://axume-portal-6bfd3.web.app/icons/axumecpaslogoold.png"
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

function safeFilename(name) {
  return (name || "")
    .toString()
    .replace(/[/\\?%*:|"<>]/g, "_")
    .replace(/[\r\n]+/g, " ")
    .replace(/"/g, "'");
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

function buildTransport() {
  return nodemailer.createTransport({
    host: SMTP_HOST.value(),
    port: SMTP_PORT.value(),
    secure: SMTP_SECURE.value(),
    auth: { user: SMTP_USER.value(), pass: SMTP_PASS.value() },
    requireTLS: !SMTP_SECURE.value(),
    tls: { rejectUnauthorized: true },
  });
}

async function sendAccountEmail({ to, subject, html }) {
  const transporter = buildTransport();

  // Expect SMTP_FROM to be an email address only (no display name)
  const fromAddress = (SMTP_FROM.value() || SMTP_USER.value() || "")
    .toString()
    .trim();

  if (!fromAddress || !fromAddress.includes("@")) {
    console.error("SMTP_FROM (or SMTP_USER fallback) is invalid:", { fromAddress });
    throw new Error("SMTP_FROM not configured or invalid");
  }

  console.log("Sending email:", { to, subject, fromAddress });

  const info = await transporter.sendMail({
    // ✅ Use structured From to avoid formatting bugs
    from: { name: "Axume & Associates CPAs", address: fromAddress },

    // ✅ Reply-To can stay as-is, or structure it too
    replyTo: { name: "Axume & Associates IT Dept.", address: "guillermo@axumecpas.com" },

    to,
    subject,
    html,
  });

  console.log("Email sent messageId:", info.messageId);
  return info.messageId;
}

async function getUserDocByUid(uid) {
  const ref = admin.firestore().collection("users").doc(uid);
  const snap = await ref.get();
  return { ref, snap, data: snap.exists ? (snap.data() || {}) : {} };
}

exports.notifyDropoffBatchUpload = onCall(
  { region: "us-central1", secrets: [SMTP_USER, SMTP_PASS] },
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
      const portalUrl = baseUrl ? `${baseUrl}/admin-dropoffs` : "";

      const subject = `${clientName} has uploaded files.`;
      // ✅ MULTI‑FILE LIST (this is the only difference)
      const safeFiles = files
        .map((n) => safeFilename((n || "").toString().trim()))
        .filter((n) => n);

      // Build <li> list items (enterprise email-safe)
      const fileLines = safeFiles
        .map((n) => `<li style="margin:0 0 6px 0;"><b>${n}</b></li>`)
        .join("");

      const html = `
<div style="font-family:Segoe UI, Arial, sans-serif; background:#ffffff; color:#0B1F33; line-height:1.55;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width:620px; margin:0 auto; background:#ffffff;">

    <!-- Header / Logo -->
    <tr>
      <td style="padding:28px 24px 18px 24px; border-bottom:1px solid #E4E7EC; background:#F9FAFB;">
        <img
          src="https://axume-portal-6bfd3.web.app/icons/axumecpaslogoold.png"
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
  { region: "us-central1", secrets: [SMTP_USER, SMTP_PASS] },
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

    if (sha256(token) !== doc.tokenHash) {
      throw new HttpsError("permission-denied", "Invalid token.");
    }

    // ✅ determine who created the request (staff)
    const requestCreatedByUid = (doc.createdByUid || "").toString().trim();

    // ✅ determine the creator role (admin/associate)
    let requestCreatedByRole = "unknown";
    if (requestCreatedByUid) {
      const creatorSnap = await db.collection("users").doc(requestCreatedByUid).get();
      requestCreatedByRole = ((creatorSnap.data()?.role || "") + "").toLowerCase().trim() || "unknown";
    }

    // generate a server-side fileId
    const fileId = db.collection("_tmp").doc().id;

    await ref.collection("files").doc(fileId).set({
      // existing fields you already write
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      originalName: file.originalName || "",
      storagePath: file.storagePath || "",
      sizeBytes: file.sizeBytes || 0,
      contentType: file.contentType || "",
      uploadedBy: {
        type: "client",
        name: doc.clientName || "",
      },

      // ✅ NEW fields (power the “admin vs associate visibility” rule + query)
      requestId: rid,
      requestCreatedByUid,
      requestCreatedByRole, // "admin" | "associate" | "unknown"
    });

    // bump counters
    await ref.set(
      {
        lastUploadedAt: admin.firestore.FieldValue.serverTimestamp(),
        fileCount: admin.firestore.FieldValue.increment(1),
      },
      { merge: true }
    );

    return { ok: true, fileId };
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
    secrets: [SMTP_USER, SMTP_PASS],
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
        const portalUrl = baseUrl ? `${baseUrl}/admin-dropoffs` : "";

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
          src="https://axume-portal-6bfd3.web.app/icons/axumecpaslogoold.png"
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
  { region: "us-central1", secrets: [SMTP_USER, SMTP_PASS] },
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
  { region: "us-central1", secrets: [SMTP_USER, SMTP_PASS] },
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

      if (email) {
        await admin.auth().updateUser(uid, { email });
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
  { region: "us-central1", secrets: [SMTP_USER, SMTP_PASS] },
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

// ============================
// sendPasswordReset (admin-only)
// ============================
exports.sendPasswordReset = onCall(
  { region: "us-central1", secrets: [SMTP_USER, SMTP_PASS] },
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
          src="https://axume-portal-6bfd3.web.app/icons/axumecpaslogoold.png"
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
  { region: "us-central1", secrets: [SMTP_USER, SMTP_PASS] },
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

    if (!firstName || !lastName) {
      throw new HttpsError("invalid-argument", "First and last name required.");
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
      message: message || "",
      status: "open",
      tokenHash,
      url,
      lastViewedAt: null,
      lastUploadedAt: null,
      fileCount: 0,
    });

    return { ok: true, requestId: ref.id, url };
  }
);

exports.validateDropoffLink = onCall(
  { region: "us-central1" },
  async (request) => {
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

    // ✅ Validate token first (still an error if wrong)
    if (sha256(token) !== doc.tokenHash) {
      throw new HttpsError("permission-denied", "Invalid token.");
    }

    // ✅ Always stamp view time
    await ref.set(
      { lastViewedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    // ✅ Always return status (open OR closed)
    return {
      ok: true,
      requestId: rid,
      clientName: doc.clientName || "",
      message: doc.message || "",
      status: doc.status || "open",
    };
  }
);

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

// ============================
// deleteDropoffUploadsBatch (admin-only)
// ============================
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
      await assertAdmin(auth.uid); // uses your existing helper [1](https://axumecpa-my.sharepoint.com/personal/guillermo_axumecpas_com/Documents/Forms/DispForm.aspx?ID=658&web=1)

      const items = data?.items;
      if (!Array.isArray(items) || items.length === 0) {
        throw new HttpsError("invalid-argument", "items[] is required.");
      }

      const db = admin.firestore();
      const bucket = admin.storage().bucket();

      const results = [];
      for (const it of items) {
        const docPath = (it?.docPath || "").toString().trim();
        const storagePath = (it?.storagePath || "").toString().trim();

        if (!docPath) {
          results.push({ ok: false, docPath, error: "missing docPath" });
          continue;
        }

        try {
          // Delete Firestore metadata doc
          await db.doc(docPath).delete().catch(() => { });

          // Delete Storage object (if provided)
          if (storagePath) {
            await bucket.file(storagePath).delete().catch(() => { });
          }

          results.push({ ok: true, docPath });
        } catch (e) {
          console.error("deleteDropoffUploadsBatch item failed", {
            docPath,
            storagePath,
            message: e?.message ?? String(e),
          });
          results.push({
            ok: false,
            docPath,
            error: e?.message ?? String(e),
          });
        }
      }

      const deleted = results.filter((r) => r.ok).length;
      return { ok: true, deleted, results };
    } catch (err) {
      console.error("deleteDropoffUploadsBatch failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Delete batch failed.", {
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
    if (!["open", "closed"].includes(status)) {
      throw new HttpsError("invalid-argument", "status must be 'open' or 'closed'");
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

    await ref.set(
      {
        status,
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusUpdatedBy: auth.uid,
      },
      { merge: true }
    );

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

    // Delete storage files listed in subcollection
    const filesSnap = await ref.collection("files").get();
    for (const doc of filesSnap.docs) {
      const path = doc.data().storagePath;
      if (path) {
        await bucket.file(path).delete().catch(() => { });
      }
    }

    // Delete subcollection docs + request doc
    const batch = db.batch();
    filesSnap.docs.forEach((d) => batch.delete(d.ref));
    batch.delete(ref);
    await batch.commit();

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