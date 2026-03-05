const { onCall, HttpsError } = require("firebase-functions/v2/https");
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
function safeFilename(name) {
  return name
    .replace(/[/\\?%*:|"<>]/g, "_") // illegal filesystem chars
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

async function assertAdmin(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Admins only.");
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
  await transporter.sendMail({
    from: SMTP_FROM.value(),
    to,
    subject,
    html,
  });
}

// ============================
// createDropoffRequest (admin-only)
// ============================
exports.createDropoffRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    await assertAdmin(auth.uid);

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
    if (!isValidHttpUrl(baseUrl)) {
      throw new HttpsError("failed-precondition", "APP_URL is invalid.");
    }

    const cleanBase = baseUrl.replace(/\/$/, "");
    const url = `${cleanBase}/#/dropoff?rid=${ref.id}&t=${token}`;

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

// ============================
// validateDropoffLink (public)
// ============================
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

    const doc = snap.data();

    if ((doc.status || "open") !== "open") {
      throw new HttpsError(
        "failed-precondition",
        "This drop-off link is no longer active."
      );
    }

    if (sha256(token) !== doc.tokenHash) {
      throw new HttpsError("permission-denied", "Invalid token.");
    }

    await ref.set(
      { lastViewedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    return {
      ok: true,
      requestId: rid,
      clientName: doc.clientName || "",
      message: doc.message || "",
      status: doc.status || "open",
    };
  }
);

// ============================
// getAdminDownloadUrl (admin-only)
// ============================
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
// setDropoffStatus (admin-only)
// Enables/disables a drop-off link by setting status=open|closed
// ============================
exports.setDropoffStatus = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;

    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    await assertAdmin(auth.uid);

    const requestId = (data?.requestId || "").toString().trim();
    const status = (data?.status || "").toString().toLowerCase().trim();

    if (!requestId) {
      throw new HttpsError("invalid-argument", "requestId required.");
    }

    if (!["open", "closed"].includes(status)) {
      throw new HttpsError(
        "invalid-argument",
        "status must be 'open' or 'closed'"
      );
    }

    const ref = admin.firestore().collection("dropoff_requests").doc(requestId);
    const snap = await ref.get();

    if (!snap.exists) {
      throw new HttpsError("not-found", "Drop-off request not found.");
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

// ============================
// deleteDropoffRequest (admin-only)
// ============================
exports.deleteDropoffRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    const { auth, data } = request;
    if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    await assertAdmin(auth.uid);

    const requestId = (data.requestId || "").trim();
    if (!requestId) {
      throw new HttpsError("invalid-argument", "requestId required.");
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const ref = db.collection("dropoff_requests").doc(requestId);

    const filesSnap = await ref.collection("files").get();
    for (const doc of filesSnap.docs) {
      const path = doc.data().storagePath;
      if (path) {
        await bucket.file(path).delete().catch(() => { });
      }
    }

    const batch = db.batch();
    filesSnap.docs.forEach((d) => batch.delete(d.ref));
    batch.delete(ref);
    await batch.commit();

    return { ok: true };
  }
);