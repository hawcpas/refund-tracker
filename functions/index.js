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
// Params (existing)
// ============================
const APP_NAME = defineString("APP_NAME", {
  // Use plain text here (no HTML entities). We escape when rendering.
  default: "Associate Portal - Axume & Associates CPAs",
}); // kept for backward compatibility

const APP_URL = defineString("APP_URL", {
  default: "https://axume-portal-6bfd3.web.app",
});

const SMTP_HOST = defineString("SMTP_HOST");
const SMTP_PORT = defineInt("SMTP_PORT", { default: 587 });
const SMTP_SECURE = defineBoolean("SMTP_SECURE", { default: false });
const SMTP_FROM = defineString("SMTP_FROM");

// ============================
// Params (NEW - Branding + Versioning)
// ============================
const BRAND_NAME = defineString("BRAND_NAME", {
  // Plain text (no HTML entities)
  default: "Axume & Associates CPAs, AAC",
});
const PORTAL_NAME = defineString("PORTAL_NAME", { default: "Associate Portal" });
const BRAND_PRIMARY = defineString("BRAND_PRIMARY", { default: "#0B1220" }); // dark/navy
const BRAND_ACCENT = defineString("BRAND_ACCENT", { default: "#0B5FFF" }); // blue
const BRAND_LOGO_URL = defineString("BRAND_LOGO_URL", { default: "" }); // https://.../logo.png
const EMAIL_TEMPLATE_VERSION = defineString("EMAIL_TEMPLATE_VERSION", {
  default: "v1",
});

// ============================
// Helpers
// ============================
function normalizeEmail(email) {
  return (email || "").toLowerCase().trim();
}

function normalizeName(s) {
  return (s || "").toString().trim();
}

// Correct HTML escaping: escape characters, not entity strings.
function escapeHtml(str) {
  return String(str ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
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

// Prefer branded name if provided; otherwise fall back to APP_NAME for compatibility.
function appDisplayName() {
  const brand = (BRAND_NAME.value() || "").trim();
  const portal = (PORTAL_NAME.value() || "").trim();

  if (brand || portal) {
    return [brand, portal].filter(Boolean).join(" - ").trim();
  }
  return (APP_NAME.value() || "Axume Portal").trim();
}

function buildTransport() {
  console.log("SMTP CONFIG:", {
    host: SMTP_HOST.value(),
    port: SMTP_PORT.value(),
    secure: SMTP_SECURE.value(),
    from: SMTP_FROM.value(),
    user: "*****", // don't print secrets
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
// Email Template System (Centralized + Versioned)
// ============================

function renderEmailShell({ title, preheader, contentHtml, footerNote }) {
  const primary = (BRAND_PRIMARY.value() || "#0B1220").trim();
  const accent = (BRAND_ACCENT.value() || "#0B5FFF").trim();
  const logoUrl = (BRAND_LOGO_URL.value() || "").trim();
  const brandLine = appDisplayName();
  const portalUrl = (APP_URL.value() || "").trim();

  const hiddenPreheader = preheader
    ? `<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;mso-hide:all;">
         ${escapeHtml(preheader)}
       </div>`
    : "";

  const logoImg = logoUrl
    ? `<img
         src="${logoUrl}"
         alt="${escapeHtml(brandLine)}"
         width="210"
         height="52"
         style="display:block;height:34px;width:auto;max-width:140px;border:0;outline:none;text-decoration:none;"
       />`
    : "";

  return `
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>${escapeHtml(brandLine)}</title>
  </head>
  <body style="margin:0;padding:0;background:#F6F7FB;">
    ${hiddenPreheader}

    <div style="background:#F6F7FB;padding:24px 0;">
      <div style="max-width:620px;margin:0 auto;">
        <div style="background:#FFFFFF;border:1px solid rgba(0,0,0,0.06);border-radius:14px;overflow:hidden;font-family:Arial,sans-serif;line-height:1.45;color:#101828;">

          <!-- Header (tight logo + text lockup) -->
<table role="presentation" cellpadding="0" cellspacing="0" width="100%"
       style="border-bottom:1px solid rgba(0,0,0,0.06);">
  <tr>
    <!-- Logo -->
    <td style="padding:12px 4px 12px 14px; vertical-align:middle;">
      ${logoUrl
      ? `<img
               src="${logoUrl}"
               alt="${escapeHtml(brandLine)}"
               width="190"
               height="46"
               style="
                 display:block;
                 height:46px;
                 width:auto;
                 max-width:190px;
                 border:0;
                 outline:none;
                 text-decoration:none;
               "
             />`
      : ""
    }
    </td>

    <!-- Brand text (very close to logo) -->
    <td style="padding:12px 16px 12px 4px; vertical-align:middle;">
      <div style="
        font-weight:900;
        font-size:15px;
        letter-spacing:0.2px;
        color:${primary};
        line-height:1.15;
      ">
        ${escapeHtml(brandLine)}
      </div>

      ${preheader
      ? `<div style="
               font-size:12.5px;
               color:#667085;
               margin-top:2px;
               line-height:1.25;
             ">
               ${escapeHtml(preheader)}
             </div>`
      : ""
    }
    </td>
  </tr>
</table>

          <!-- Body -->
          <div style="padding:22px 20px;">
            ${title
      ? `<h2 style="margin:0 0 14px 0;font-size:18px;line-height:1.2;color:${primary};">
                     ${escapeHtml(title)}
                   </h2>`
      : ""
    }

            ${contentHtml}

            <div style="margin-top:18px;">
              <a href="${portalUrl}"
                 style="color:${accent};font-weight:800;text-decoration:none;">
                Visit Portal
              </a>
            </div>
          </div>

          <!-- Footer -->
          <div style="padding:14px 20px;background:#F9FAFB;border-top:1px solid rgba(0,0,0,0.06);font-size:12.5px;color:#667085;">
            ${footerNote || "If you did not request this email, you can safely ignore it."}
          </div>
        </div>

        <div style="max-width:620px;margin:10px auto 0 auto;text-align:center;color:#98A2B3;font-size:12px;font-family:Arial,sans-serif;">
          © ${new Date().getFullYear()} ${escapeHtml(BRAND_NAME.value() || "Axume")}
        </div>
      </div>
    </div>
  </body>
</html>
  `;
}

function primaryButton(label, url) {
  const accent = (BRAND_ACCENT.value() || "#0B5FFF").trim();
  return `
    <a href="${url}"
       style="display:inline-block;background:${accent};color:#FFFFFF;text-decoration:none;
              font-weight:900;padding:11px 16px;border-radius:10px;mso-padding-alt:11px 16px;">
      ${escapeHtml(label)}
    </a>
  `;
}

function linkBlock(url) {
  const accent = (BRAND_ACCENT.value() || "#0B5FFF").trim();
  return `
    <div style="word-break:break-all;margin:8px 0 0 0;">
      <a href="${url}" style="color:${accent};text-decoration:none;">
        ${escapeHtml(url)}
      </a>
    </div>
  `;
}

// v1 Invite template
function renderInviteEmailV1({ firstName, resetLink, verifyLink }) {
  const safeName = firstName ? escapeHtml(firstName) : "there";

  const contentHtml = `
    <p style="margin:0 0 12px 0;">Hi ${safeName},</p>

    <p style="margin:0 0 14px 0;">
      You’ve been invited to <b>${escapeHtml(appDisplayName())}</b>.
    </p>

    <p style="margin:0 0 10px 0;color:#475467;">
      <b>Step 1:</b> Set your password to activate your account.
    </p>

    <div style="margin:12px 0 10px 0;">
      ${primaryButton("Set Password", resetLink)}
    </div>

    <p style="margin:10px 0 0 0;color:#475467;">If the button doesn’t work, copy &amp; paste:</p>
    ${linkBlock(resetLink)}

    <hr style="margin:18px 0;border:none;border-top:1px solid rgba(0,0,0,0.08);" />

    <p style="margin:0 0 10px 0;color:#475467;">
      <b>Step 2 (optional):</b> Verify your email.
    </p>

    <div style="margin:12px 0 8px 0;">
      <a href="${verifyLink}" style="color:${(BRAND_ACCENT.value() || "#0B5FFF").trim()};font-weight:900;text-decoration:none;">
        Verify Email
      </a>
    </div>

    ${linkBlock(verifyLink)}
  `;

  return renderEmailShell({
    title: "Activate your account",
    preheader: "Set your password to start using the portal.",
    contentHtml,
    footerNote:
      "If you weren’t expecting an invite, you can ignore this message. The links will expire after a period of time.",
  });
}

// v1 Password reset template
function renderPasswordResetEmailV1({ resetLink }) {
  const contentHtml = `
    <p style="margin:0 0 12px 0;">Hi,</p>

    <p style="margin:0 0 14px 0;color:#475467;">
      Use the button below to reset your password.
    </p>

    <div style="margin:12px 0 10px 0;">
      ${primaryButton("Reset Password", resetLink)}
    </div>

    <p style="margin:10px 0 0 0;color:#475467;">If the button doesn’t work, copy &amp; paste:</p>
    ${linkBlock(resetLink)}
  `;

  return renderEmailShell({
    title: "Reset your password",
    preheader: "Use the secure link to reset your password.",
    contentHtml,
    footerNote:
      "If you did not request a password reset, you can ignore this email. Your account will remain unchanged.",
  });
}

// Unified selectors (versioning)
function renderInviteEmail(args) {
  switch ((EMAIL_TEMPLATE_VERSION.value() || "v1").trim()) {
    case "v1":
    default:
      return renderInviteEmailV1(args);
  }
}

function renderPasswordResetEmail(args) {
  switch ((EMAIL_TEMPLATE_VERSION.value() || "v1").trim()) {
    case "v1":
    default:
      return renderPasswordResetEmailV1(args);
  }
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

      // ✅ BLOCK SELF-INVITE
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
      if (!isValidHttpUrl(rawAppUrl)) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${rawAppUrl}"`);
      }

      const actionCodeSettings = {
        url: rawAppUrl.trim(),
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

      // ✅ Prevent downgrading an existing admin via invite
      if (existingRole === "admin" && requestedRole !== "admin") {
        throw new HttpsError("failed-precondition", "Admins cannot be downgraded via invites.");
      }

      // ✅ Do not overwrite role/status for already-active users
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
      try {
        await sendAccountEmail({
          to: email,
          subject: `You're invited to ${appDisplayName()} — set your password`,
          html: renderInviteEmail({ firstName, resetLink, verifyLink }),
        });
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
          throw new HttpsError("failed-precondition", "At least one admin must remain.");
        }
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

      // optional guard: don’t edit yourself through this endpoint
      if (uid === auth.uid) {
        throw new HttpsError("failed-precondition", "You cannot edit yourself here.");
      }

      const email = normalizeEmail(data.email);
      const role = (data.role || "").toString().toLowerCase().trim();
      let status = (data.status || "").toString().toLowerCase().trim();
      const reason = (data.reason || "").toString().trim();
      const communicationsRaw = data.communications ?? null;

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
          if (adminsSnap.size <= 1) {
            throw new HttpsError("failed-precondition", "At least one admin must remain.");
          }
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
        subject: `Reset your password — ${appDisplayName()}`,
        html: renderPasswordResetEmail({ resetLink }),
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
      if (!isValidHttpUrl(APP_URL.value())) {
        throw new HttpsError("failed-precondition", `APP_URL is invalid: "${APP_URL.value()}"`);
      }

      const actionCodeSettings = { url: APP_URL.value().trim(), handleCodeInApp: false };
      const resetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
      const verifyLink = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);

      await sendAccountEmail({
        to: email,
        subject: `You're invited to ${appDisplayName()} — set your password`,
        html: renderInviteEmail({ firstName: "", resetLink, verifyLink }),
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