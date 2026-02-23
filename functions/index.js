const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString, defineInt, defineBoolean } = require("firebase-functions/params");
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
const APP_URL  = defineString("APP_URL");

const SMTP_HOST   = defineString("SMTP_HOST");
const SMTP_PORT   = defineInt("SMTP_PORT", { default: 587 });
const SMTP_SECURE = defineBoolean("SMTP_SECURE", { default: false });
const SMTP_FROM   = defineString("SMTP_FROM");

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
    throw new HttpsError("permission-denied", "Admin profile missing in users/{uid}.");
  }
  const role = (snap.data()?.role || "").toLowerCase().trim();
  if (role !== "admin") throw new HttpsError("permission-denied", "Admins only.");
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
      const lastName  = normalizeName(data.lastName);
      const displayName = `${firstName} ${lastName}`.trim();

      if (!email || !email.includes("@")) {
        throw new HttpsError("invalid-argument", "Valid email is required.");
      }
      if (!firstName) throw new HttpsError("invalid-argument", "First name is required.");
      if (!lastName)  throw new HttpsError("invalid-argument", "Last name is required.");

      // ✅ BLOCK SELF-INVITE (prevents overwriting your own role/status)
      // Prefer token email, fallback to Admin Auth lookup if needed.
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

      // ✅ Validate APP_URL
      const rawAppUrl = APP_URL.value();
      console.log("RAW APP_URL:", JSON.stringify(rawAppUrl));
      if (
        typeof rawAppUrl !== "string" ||
        rawAppUrl.trim() === "" ||
        !/^https?:\/\/[^\s]+$/.test(rawAppUrl.trim())
      ) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${rawAppUrl}"`);
      }

      const actionCodeSettings = {
        url: rawAppUrl.trim(), // redirect after password set
        handleCodeInApp: false,
      };

      const resetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
      const verifyLink = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);

      // ✅ Fetch existing Firestore profile (if any)
      const userDocRef = admin.firestore().collection("users").doc(userRecord.uid);
      const existingSnap = await userDocRef.get();
      const existingData = existingSnap.exists ? (existingSnap.data() || {}) : {};
      const existingRole = (existingData.role || "").toString().toLowerCase().trim();
      const existingStatus = (existingData.status || "").toString().toLowerCase().trim();

      // ✅ Prevent downgrading an existing admin via invite (even by another admin)
      if (existingRole === "admin" && requestedRole !== "admin") {
        throw new HttpsError(
          "failed-precondition",
          "Admins cannot be downgraded via invites."
        );
      }

      // ✅ Do not overwrite role/status for already-active users
      // Allow re-invites to resend reset/verify links, but keep current role/status.
      const shouldWriteRoleStatus =
        !existingSnap.exists || existingStatus === "" || existingStatus === "invited" || existingStatus === "pending";

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
      console.log("About to send invite email to:", email);
      const transporter = buildTransport();

      try {
        const info = await transporter.sendMail({
          from: SMTP_FROM.value(),
          to: email,
          subject: `You're invited to ${APP_NAME.value()} — set your password`,
          html: `
  <div style="font-family:Arial,sans-serif;line-height:1.5">
    <p>Hi ${firstName},</p>
    <p>You’ve been invited to <b>${APP_NAME.value()}</b>.</p>

    <p><b>Step 1:</b> Set your password to activate your account:</p>
    <p><a href="${resetLink}">Set Password</a></p>

    <p>If the button doesn’t work, copy &amp; paste:</p>
    <p><a href="${resetLink}">${resetLink}</a></p>

    <hr style="margin:16px 0" />

    <p><b>Step 2 (optional):</b> Verify your email:</p>
    <p><a href="${verifyLink}">Verify Email</a></p>
  </div>
`,
        });

        console.log("✅ Email sent successfully:", info.messageId);
      } catch (err) {
        console.error("❌ Email send FAILED:", err);
        throw new HttpsError("internal", "SMTP send failed.", {
          message: err?.message ?? String(err),
        });
      }

      console.log("inviteUser completed for:", email);
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

      // Never allow deleting yourself
      if (targetUid === auth.uid) {
        throw new HttpsError("failed-precondition", "You cannot delete yourself.");
      }

      // ✅ Prevent deleting the last remaining admin
      const targetSnap = await admin.firestore().collection("users").doc(targetUid).get();
      const targetRole = (targetSnap.data()?.role || "").toString().toLowerCase().trim();

      if (targetRole === "admin") {
        const adminsSnap = await admin.firestore()
          .collection("users")
          .where("role", "==", "admin")
          .get();

        if (adminsSnap.size <= 1) {
          throw new HttpsError(
            "failed-precondition",
            "At least one admin must remain."
          );
        }
      }

      // Delete Auth user (ignore if missing)
      try {
        await admin.auth().deleteUser(targetUid);
      } catch (_) {}

      // Delete Firestore docs (best-effort)
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