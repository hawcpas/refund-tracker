const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  defineSecret,
  defineString,
  defineInt,
  defineBoolean,
} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

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
function normalizeEmail(email) {
  return (email || "").toLowerCase().trim();
}
function normalizeName(s) {
  return (s || "").toString().trim();
}

async function assertAdmin(callerUid) {
  const snap = await admin.firestore().collection("users").doc(callerUid).get();
  if (!snap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Admin profile missing in users/{uid}."
    );
  }
  const role = (snap.data()?.role || "").toLowerCase().trim();
  if (role !== "admin") throw new HttpsError("permission-denied", "Admins only.");
}

function isValidHttpUrl(url) {
  return (
    typeof url === "string" &&
    url.trim() !== "" &&
    /^https?:\/\/[^\s]+$/.test(url.trim())
  );
}

function buildTransport() {
  console.log("SMTP CONFIG:", {
    host: SMTP_HOST.value(),
    port: SMTP_PORT.value(),
    secure: SMTP_SECURE.value(),
    from: SMTP_FROM.value(),
  });

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
  const info = await transporter.sendMail({
    from: SMTP_FROM.value(),
    to,
    subject,
    html,
  });
  console.log("✅ Email sent:", info.messageId);
  return info.messageId;
}

async function getUserDocByUid(uid) {
  const ref = admin.firestore().collection("users").doc(uid);
  const snap = await ref.get();
  return { ref, snap, data: snap.exists ? (snap.data() || {}) : {} };
}

// ============================
// inviteUser (admin-only)
// ============================
exports.inviteUser = onCall(
  {
    region: "us-central1",
    secrets: [SMTP_USER, SMTP_PASS],
  },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const email = normalizeEmail(data.email);
      const requestedRole = (data.role || "associate").toLowerCase().trim();
      const firstName = normalizeName(data.firstName);
      const lastName = normalizeName(data.lastName);
      const displayName = `${firstName} ${lastName}`.trim();

      if (!email || !email.includes("@")) {
        throw new HttpsError("invalid-argument", "Valid email is required.");
      }
      if (!firstName) throw new HttpsError("invalid-argument", "First name is required.");
      if (!lastName) throw new HttpsError("invalid-argument", "Last name is required.");

      // BLOCK SELF-INVITE
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
      console.log("RAW APP_URL:", JSON.stringify(rawAppUrl));
      if (!isValidHttpUrl(rawAppUrl)) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${rawAppUrl}"`);
      }

      const actionCodeSettings = {
        url: rawAppUrl.trim(),
        handleCodeInApp: false,
      };

      const resetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
      const verifyLink = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);

      // Firestore profile
      const userDocRef = admin.firestore().collection("users").doc(userRecord.uid);
      const existingSnap = await userDocRef.get();
      const existingData = existingSnap.exists ? (existingSnap.data() || {}) : {};
      const existingRole = (existingData.role || "").toString().toLowerCase().trim();
      const existingStatus = (existingData.status || "").toString().toLowerCase().trim();

      if (existingRole === "admin" && requestedRole !== "admin") {
        throw new HttpsError("failed-precondition", "Admins cannot be downgraded via invites.");
      }

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
      };

      if (shouldWriteRoleStatus) {
        userPayload.role = requestedRole;
        userPayload.status = "invited";
      }

      await userDocRef.set(userPayload, { merge: true });

      // invites ledger
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

      // send invite email
      const transporter = buildTransport();
      await transporter.sendMail({
        from: SMTP_FROM.value(),
        to: email,
        subject: `You're invited to ${APP_NAME.value()} — set your password`,
        html: `
<div style="font-family:Arial,sans-serif;line-height:1.5">
  <p>Hi ${firstName},</p>
  <p>You’ve been invited to <b>${APP_NAME.value()}</b>.</p>

  <p><b>Step 1:</b> Set your password to activate your account:</p>
  <p><a href="${resetLink}">Set Password</a></p>

  <p>If the button doesn’t work, copy & paste:</p>
  <p><a href="${resetLink}">${resetLink}</a></p>

  <hr style="margin:16px 0" />

  <p><b>Step 2 (optional):</b> Verify your email:</p>
  <p><a href="${verifyLink}">Verify Email</a></p>
</div>
`,
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

// ============================
// deleteUser (admin-only)
// ============================
exports.deleteUser = onCall(
  {
    region: "us-central1",
    secrets: [SMTP_USER, SMTP_PASS],
  },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const targetUid = (data.uid || "").toString().trim();
      const email = normalizeEmail(data.email);
      if (!targetUid) throw new HttpsError("invalid-argument", "uid is required.");

      if (targetUid === auth.uid) {
        throw new HttpsError("failed-precondition", "You cannot delete yourself.");
      }

      const targetSnap = await admin.firestore().collection("users").doc(targetUid).get();
      const targetRole = (targetSnap.data()?.role || "").toString().toLowerCase().trim();
      if (targetRole === "admin") {
        const adminsSnap = await admin.firestore().collection("users").where("role", "==", "admin").get();
        if (adminsSnap.size <= 1) {
          throw new HttpsError("failed-precondition", "At least one admin must remain.");
        }
      }

      try { await admin.auth().deleteUser(targetUid); } catch (_) {}

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
  {
    region: "us-central1",
    secrets: [SMTP_USER, SMTP_PASS],
  },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const uid = (data.uid || "").toString().trim();
      if (!uid) throw new HttpsError("invalid-argument", "uid is required.");
      if (uid === auth.uid) throw new HttpsError("failed-precondition", "You cannot edit yourself here.");

      const email = normalizeEmail(data.email);
      const role = (data.role || "").toString().toLowerCase().trim();
      let status = (data.status || "").toString().toLowerCase().trim();
      const reason = (data.reason || "").toString().trim();
      const communicationsRaw = data.communications ?? null;

      const allowedRoles = new Set(["associate", "admin"]);
      if (status === "inactive") status = "disabled";
      if (status === "pending") status = "invited";
      const allowedStatus = new Set(["active", "invited", "disabled"]);

      if (email && !email.includes("@")) throw new HttpsError("invalid-argument", "Valid email is required.");
      if (role && !allowedRoles.has(role)) throw new HttpsError("invalid-argument", "Invalid role.");
      if (status && !allowedStatus.has(status)) throw new HttpsError("invalid-argument", "Invalid status.");

      if (email) await admin.auth().updateUser(uid, { email });

      const { ref, data: existing } = await getUserDocByUid(uid);

      if ((existing.role || "").toString().toLowerCase() === "admin" && role === "associate") {
        const adminsSnap = await admin.firestore().collection("users").where("role", "==", "admin").get();
        if (adminsSnap.size <= 1) throw new HttpsError("failed-precondition", "At least one admin must remain.");
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
        if (Object.keys(clean).length > 0) patch.communications = clean;
      }

      await ref.set(patch, { merge: true });

      const commsChange = patch.communications
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
  {
    region: "us-central1",
    secrets: [SMTP_USER, SMTP_PASS],
  },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const uid = (data.uid || "").toString().trim();
      const disabled = !!data.disabled;
      const reason = (data.reason || "").toString().trim();

      if (!uid) throw new HttpsError("invalid-argument", "uid is required.");
      if (uid === auth.uid) throw new HttpsError("failed-precondition", "You cannot disable yourself.");

      if (disabled) {
        const targetSnap = await admin.firestore().collection("users").doc(uid).get();
        const targetRole = (targetSnap.data()?.role || "").toString().toLowerCase().trim();
        if (targetRole === "admin") {
          const adminsSnap = await admin.firestore().collection("users").where("role", "==", "admin").get();
          if (adminsSnap.size <= 1) throw new HttpsError("failed-precondition", "At least one admin must remain.");
        }
      }

      await admin.auth().updateUser(uid, { disabled });

      const prevSnap = await admin.firestore().collection("users").doc(uid).get();
      const prevStatus = (prevSnap.data()?.status || "").toString().toLowerCase().trim();
      const nextStatus = disabled ? "disabled" : (prevStatus === "invited" ? "invited" : "active");

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
  {
    region: "us-central1",
    secrets: [SMTP_USER, SMTP_PASS],
  },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const email = normalizeEmail(data.email);
      const uid = (data.uid || "").toString().trim();

      if (!email || !email.includes("@")) throw new HttpsError("invalid-argument", "Valid email is required.");
      if (!isValidHttpUrl(APP_URL.value())) throw new HttpsError("failed-precondition", `APP_URL is invalid: "${APP_URL.value()}"`);

      if (uid) {
        const u = await admin.auth().getUser(uid);
        const authEmail = normalizeEmail(u.email);
        if (authEmail && authEmail !== email) throw new HttpsError("failed-precondition", "UID/email mismatch.");
      }

      const resetLink = await admin.auth().generatePasswordResetLink(email, {
        url: APP_URL.value().trim(),
        handleCodeInApp: false,
      });

      await sendAccountEmail({
        to: email,
        subject: `Reset your password — ${APP_NAME.value()}`,
        html: `
<div style="font-family:Arial,sans-serif;line-height:1.5">
  <p>Hi,</p>
  <p>Use the link below to reset your password:</p>
  <p><a href="${resetLink}">Reset Password</a></p>
  <p>If the button doesn’t work, copy & paste:</p>
  <p><a href="${resetLink}">${resetLink}</a></p>
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
  {
    region: "us-central1",
    secrets: [SMTP_USER, SMTP_PASS],
  },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const uid = (data.uid || "").toString().trim();
      if (!uid) throw new HttpsError("invalid-argument", "uid is required.");

      const userRecord = await admin.auth().getUser(uid);
      const email = normalizeEmail(userRecord.email);

      if (!email) throw new HttpsError("failed-precondition", "Target user has no email.");
      if (!isValidHttpUrl(APP_URL.value())) throw new HttpsError("failed-precondition", `APP_URL is invalid: "${APP_URL.value()}"`);

      const actionCodeSettings = { url: APP_URL.value().trim(), handleCodeInApp: false };
      const resetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
      const verifyLink = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);

      await sendAccountEmail({
        to: email,
        subject: `You're invited to ${APP_NAME.value()} — set your password`,
        html: `
<div style="font-family:Arial,sans-serif;line-height:1.5">
  <p>Hi,</p>
  <p>Here are your account links:</p>
  <p><b>Set your password:</b> <a href="${resetLink}">Set Password</a></p>
  <p><b>Verify email:</b> <a href="${verifyLink}">Verify Email</a></p>
  <hr style="margin:16px 0" />
  <p>If the buttons don’t work, copy & paste:</p>
  <p><a href="${resetLink}">${resetLink}</a></p>
  <p><a href="${verifyLink}">${verifyLink}</a></p>
</div>
`,
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
      throw new HttpsError("internal", "Resend invite failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

// ============================
// Drop-Off Helpers
// ============================
const crypto = require("crypto");
function sha256(s) {
  return crypto.createHash("sha256").update(String(s)).digest("hex");
}

// ============================
// createDropoffRequest (admin-only)
// ============================
exports.createDropoffRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
      await assertAdmin(auth.uid);

      const firstName = normalizeName(data.firstName);
      const lastName = normalizeName(data.lastName);
      const message = normalizeName(data.message);

      const clientEmailRaw = normalizeEmail(data.clientEmail);
      const clientEmail =
        clientEmailRaw && clientEmailRaw.includes("@") ? clientEmailRaw : "";

      if (!firstName) throw new HttpsError("invalid-argument", "First name is required.");
      if (!lastName) throw new HttpsError("invalid-argument", "Last name is required.");

      const clientName = `${firstName} ${lastName}`.trim();

      // token in URL only; tokenHash stored
      const token = crypto.randomBytes(32).toString("hex");
      const tokenHash = sha256(token);

      // create unique request id
      const ref = admin.firestore().collection("dropoff_requests").doc();

      // build url and store it
      const baseUrl = APP_URL.value();
      if (!isValidHttpUrl(baseUrl)) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${baseUrl}"`);
      }
      const cleanBase = baseUrl.replace(/\/$/, "");
      const url = `${cleanBase}/#/dropoff?rid=${ref.id}&t=${token}`;

      await ref.set({
        requestId: ref.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdByUid: auth.uid,
        createdByEmail: normalizeEmail(auth.token?.email),

        clientEmail,
        clientName,
        clientFirstName: firstName,
        clientLastName: lastName,

        message: message || "",
        status: "open",
        expiresAt: null,

        tokenHash,
        url,

        lastViewedAt: null,
        lastUploadedAt: null,
        fileCount: 0,
      });

      await admin.firestore().collection("auditLogs").add({
        type: "dropoff_created",
        requestId: ref.id,
        actor: {
          type: "staff",
          uid: auth.uid,
          email: normalizeEmail(auth.token?.email),
        },
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true, requestId: ref.id, url };
    } catch (err) {
      console.error("createDropoffRequest failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Create dropoff failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

// ============================
// validateDropoffLink (public callable)
// ============================
exports.validateDropoffLink = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      const { data } = request;

      const rid = (data.rid || "").toString().trim();
      const token = (data.token || "").toString().trim();

      if (!rid || !token) {
        throw new HttpsError("invalid-argument", "rid and token are required.");
      }

      const ref = admin.firestore().collection("dropoff_requests").doc(rid);
      const snap = await ref.get();

      if (!snap.exists) {
        throw new HttpsError("not-found", "Drop-off request not found.");
      }

      const doc = snap.data() || {};
      const status = (doc.status || "").toString().toLowerCase().trim();
      if (status !== "open") {
        throw new HttpsError("failed-precondition", "This drop-off link is not open.");
      }

      const tokenHash = sha256(token);
      if (tokenHash !== doc.tokenHash) {
        throw new HttpsError("permission-denied", "Invalid token.");
      }

      // mark viewed
      await ref.set(
        { lastViewedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );

      await admin.firestore().collection("auditLogs").add({
        type: "dropoff_viewed",
        requestId: rid,
        actor: {
          type: "client",
          uid: null,
          email: normalizeEmail(doc.clientEmail),
        },
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        ok: true,
        requestId: rid,
        clientEmail: normalizeEmail(doc.clientEmail),
        clientName: (doc.clientName || "").toString(),
        message: (doc.message || "").toString(),
      };
    } catch (err) {
      console.error("validateDropoffLink failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Validate dropoff failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);

// ============================
// deleteDropoffRequest (admin-only)
// ============================
exports.deleteDropoffRequest = onCall(
  { region: "us-central1" },
  async (request) => {
    try {
      const { auth, data } = request;
      if (!auth) throw new HttpsError("unauthenticated", "Sign-in required.");
      await assertAdmin(auth.uid);

      const requestId = (data.requestId || "").toString().trim();
      if (!requestId) throw new HttpsError("invalid-argument", "requestId is required.");

      const db = admin.firestore();
      const bucket = admin.storage().bucket();

      const ref = db.collection("dropoff_requests").doc(requestId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError("not-found", "Drop-off request not found.");

      // delete storage files
      const filesSnap = await ref.collection("files").get();
      for (const doc of filesSnap.docs) {
        const path = doc.data().storagePath;
        if (path) {
          try {
            await bucket.file(path).delete();
          } catch (e) {
            console.warn("Failed to delete storage file:", path, e?.message || e);
          }
        }
      }

      // delete firestore docs
      const batch = db.batch();
      for (const doc of filesSnap.docs) batch.delete(doc.ref);
      batch.delete(ref);
      await batch.commit();

      await db.collection("auditLogs").add({
        type: "dropoff_deleted",
        requestId,
        actor: {
          type: "staff",
          uid: auth.uid,
          email: normalizeEmail(auth.token?.email),
        },
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true };
    } catch (err) {
      console.error("deleteDropoffRequest failed:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Delete dropoff failed on server.", {
        message: err?.message ?? String(err),
      });
    }
  }
);