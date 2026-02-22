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
// Secrets (stored in Secret Manager)
// ============================
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");

// ============================
// Non-secret params (from functions/.env.local or CLI prompts)
// ============================
const APP_NAME = defineString("APP_NAME", { default: "Axume Portal" });
const APP_URL = defineString("APP_URL");

const SMTP_HOST = defineString("SMTP_HOST"); // e.g. smtp.gmail.com
const SMTP_PORT = defineInt("SMTP_PORT", { default: 587 });
const SMTP_SECURE = defineBoolean("SMTP_SECURE", { default: false }); // false for 587 STARTTLS
const SMTP_FROM = defineString("SMTP_FROM"); // e.g. "Axume Portal <yourgmail@gmail.com>"

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

function buildTransport() {

  console.log("SMTP CONFIG:", {
    host: SMTP_HOST.value(),
    port: SMTP_PORT.value(),
    secure: SMTP_SECURE.value(),
    from: SMTP_FROM.value(),
  });
  // Uses parameterized config + secrets. Your config values are loaded by the Firebase CLI from .env files. [1](https://github.com/firebase/firebase-functions/issues/1342)[2](https://axumecpa-my.sharepoint.com/personal/guillermo_axumecpas_com/Documents/Personal_Files/Other/Microsoft%20Related/Microsoft%20Copilot%20Chat%20Files/firebase.json)
  return nodemailer.createTransport({
    host: SMTP_HOST.value(),
    port: SMTP_PORT.value(),
    secure: SMTP_SECURE.value(), // false for 587 STARTTLS
    auth: {
      user: SMTP_USER.value(),
      pass: SMTP_PASS.value(),
    },
    // Helpful when providers require STARTTLS explicitly
    requireTLS: !SMTP_SECURE.value(),
    tls: {
      // Keep strict in production; set to true only if you hit cert issues.
      rejectUnauthorized: true,
    },
  });
}

// ============================
// inviteUser (admin-only)
// ============================
exports.inviteUser = onCall(
  {
    region: "us-central1",
    secrets: [SMTP_USER, SMTP_PASS], // makes secrets available at runtime [2](https://axumecpa-my.sharepoint.com/personal/guillermo_axumecpas_com/Documents/Personal_Files/Other/Microsoft%20Related/Microsoft%20Copilot%20Chat%20Files/firebase.json)
  },
  async (request) => {
    try {
      const { auth, data } = request;

      if (!auth) {
        throw new HttpsError("unauthenticated", "You must be signed in.");
      }
      await assertAdmin(auth.uid);

      const email = normalizeEmail(data.email);
      const role = (data.role || "associate").toLowerCase().trim();
      const firstName = normalizeName(data.firstName);
      const lastName = normalizeName(data.lastName);
      const displayName = `${firstName} ${lastName}`.trim();

      if (!email || !email.includes("@")) {
        throw new HttpsError("invalid-argument", "Valid email is required.");
      }
      if (!firstName) {
        throw new HttpsError("invalid-argument", "First name is required.");
      }
      if (!lastName) {
        throw new HttpsError("invalid-argument", "Last name is required.");
      }

      // Create or fetch Auth user
      let userRecord;
      try {
        userRecord = await admin.auth().getUserByEmail(email);
      } catch (_) {
        userRecord = await admin.auth().createUser({
          email,
          displayName: displayName || undefined,
          emailVerified: false,
        });
      }

      // Generate verification link
      const actionCodeSettings = {
        url: `${APP_URL.value()}/login`,
        handleCodeInApp: false,
      };
      const verifyLink = await admin
        .auth()
        .generateEmailVerificationLink(email, actionCodeSettings);

      // Write Firestore user profile
      await admin.firestore().collection("users").doc(userRecord.uid).set(
        {
          uid: userRecord.uid,
          email,
          firstName,
          lastName,
          displayName,
          role,
          status: "invited",
          emailVerified: false,
          invitedAt: admin.firestore.FieldValue.serverTimestamp(),
          invitedBy: auth.uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Track invites by email
      await admin.firestore().collection("invites").doc(email).set(
        {
          email,
          uid: userRecord.uid,
          firstName,
          lastName,
          displayName,
          role,
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
          subject: `You're invited to ${APP_NAME.value()} — verify your email`,
          html: `
            <div style="font-family:Arial,sans-serif;line-height:1.5">
              <p>Hi ${firstName},</p>
              <p>You’ve been invited to <b>${APP_NAME.value()}</b>.</p>
              <p>Please verify your email to continue:</p>
              <p><a href="${verifyLink}">Verify Email</a></p>
              <p>If the button doesn’t work, copy &amp; paste:</p>
              <p><a href="${verifyLink}">${verifyLink}</a></p>
            </div>
          `,
        });

        console.log("✅ Email sent successfully:", info.messageId);
      } catch (err) {
        console.error("❌ Email send FAILED:", err);
        // Return a clearer error to the client (and your UI)
        throw new HttpsError("internal", "SMTP send failed.", {
          message: err?.message ?? String(err),
        });
      }

      console.log("inviteUser completed for:", email);
      return { ok: true, email, role, sent: true };
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
    secrets: [SMTP_USER, SMTP_PASS], // harmless here
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

      // Delete Auth user (ignore if missing)
      try {
        await admin.auth().deleteUser(targetUid);
      } catch (_) { }

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