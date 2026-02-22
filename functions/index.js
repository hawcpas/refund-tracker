const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

function normalizeEmail(email) {
  return (email || "").toLowerCase().trim();
}

function normalizeName(s) {
  return (s || "").toString().trim();
}

async function assertAdmin(callerUid) {
  const callerSnap = await admin.firestore().collection("users").doc(callerUid).get();
  const role = (callerSnap.data()?.role || "").toLowerCase();
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Admins only.");
  }
}

exports.inviteUser = onCall(async (request) => {
  const { auth, data } = request;

  if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
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
  } catch (e) {
    userRecord = await admin.auth().createUser({
      email,
      displayName: displayName || undefined,
    });
  }

  // Generate password reset link for invite onboarding
  const resetLink = await admin.auth().generatePasswordResetLink(email);

  // Write Firestore user profile (invite-only model)
  await admin.firestore().collection("users").doc(userRecord.uid).set(
    {
      uid: userRecord.uid,
      email,
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

  // Track invites (optional but useful)
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

  // Return reset link (until you wire actual email sending)
  return { ok: true, uid: userRecord.uid, email, role, resetLink };
});

exports.deleteUser = onCall(async (request) => {
  const { auth, data } = request;

  if (!auth) throw new HttpsError("unauthenticated", "You must be signed in.");
  await assertAdmin(auth.uid);

  const targetUid = (data.uid || "").toString().trim();
  const email = normalizeEmail(data.email); // optional but helpful for invites cleanup

  if (!targetUid) {
    throw new HttpsError("invalid-argument", "uid is required.");
  }

  // ❌ Never allow deleting yourself
  if (targetUid === auth.uid) {
    throw new HttpsError("failed-precondition", "You cannot delete yourself.");
  }

  // Delete Auth user (ignore if already missing)
  try {
    await admin.auth().deleteUser(targetUid);
  } catch (e) {
    // If user doesn't exist in Auth, still proceed deleting Firestore docs.
  }

  // Delete Firestore user doc + invite doc (best-effort)
  const batch = admin.firestore().batch();
  batch.delete(admin.firestore().collection("users").doc(targetUid));
  if (email) {
    batch.delete(admin.firestore().collection("invites").doc(email));
  }
  await batch.commit();

  return { ok: true, uid: targetUid, email };
});