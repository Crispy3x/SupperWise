// Ridgeline Ops: Edge Function `team` (see supabase/CONTRACT.md).
// Lets the owner (or a member with manageTeam) create employee logins, reset their passwords, change their access
// and remove them. Runs with the service role key, which Supabase provides to Edge Functions automatically; the key
// never leaves the server.
//
// POST /functions/v1/team   Authorization: Bearer <caller's access token>
// Body {action, business_id, ...}. Replies 200 {ok:true} or 4xx/5xx {error:"plain sentence"}.

import { createClient } from "npm:@supabase/supabase-js@2";

const ROLES = ["manager", "dispatcher", "crewLead", "crewMember", "office"] as const;
const PERMISSIONS = [
  "viewAllJobs", "editJobs", "logVisits", "useTimeClock", "viewClients", "editClients", "viewRequests",
  "answerRequests", "viewQuotes", "editQuotes", "viewRevenue", "viewTeam", "manageTeam", "manageSettings",
] as const;
const EMAIL_DOMAIN = "crew.ridgelineops.app";
const USERNAME_RE = /^[a-z0-9._-]{3,32}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false, autoRefreshToken: false } },
);

type MemberRow = {
  business_id: string;
  user_id: string;
  member_id: string | null;
  role: string;
  permissions: string[];
  username: string | null;
  disabled: boolean;
};

// ---------- input validation ----------

function str(body: Record<string, unknown>, key: string): string {
  const v = body[key];
  if (typeof v !== "string" || v.trim() === "") throw new HttpError(400, `Please provide ${key.replace("_", " ")}.`);
  return v;
}

function uuid(body: Record<string, unknown>, key: string): string {
  const v = str(body, key).trim().toLowerCase();
  if (!UUID_RE.test(v)) throw new HttpError(400, `The ${key.replace("_", " ")} is not valid.`);
  return v;
}

function username(body: Record<string, unknown>): string {
  const v = str(body, "username").trim().toLowerCase();
  if (!USERNAME_RE.test(v)) {
    throw new HttpError(
      400,
      "Usernames must be 3 to 32 characters using only lowercase letters, numbers, dots, dashes and underscores.",
    );
  }
  return v;
}

function password(body: Record<string, unknown>): string {
  const v = body.password;
  if (typeof v !== "string" || v.length < 8) throw new HttpError(400, "The password must be at least 8 characters.");
  if (new TextEncoder().encode(v).length > 72) throw new HttpError(400, "The password must be at most 72 characters.");
  return v;
}

function role(body: Record<string, unknown>): string {
  const v = body.role;
  if (typeof v !== "string" || !(ROLES as readonly string[]).includes(v)) {
    throw new HttpError(400, `The role must be one of: ${ROLES.join(", ")}.`);
  }
  return v;
}

function permissions(body: Record<string, unknown>): string[] {
  const v = body.permissions;
  if (!Array.isArray(v) || v.some((p) => typeof p !== "string")) {
    throw new HttpError(400, "Permissions must be a list of permission names.");
  }
  const unknown = v.filter((p) => !(PERMISSIONS as readonly string[]).includes(p));
  if (unknown.length > 0) throw new HttpError(400, `Unknown permission: ${unknown.join(", ")}.`);
  return PERMISSIONS.filter((p) => v.includes(p)); // de-duplicated, canonical order
}

function bool(body: Record<string, unknown>, key: string): boolean {
  const v = body[key];
  if (typeof v !== "boolean") throw new HttpError(400, `Please say whether the login is ${key} (true or false).`);
  return v;
}

// ---------- caller and target ----------

async function callerUserId(req: Request): Promise<string> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401, "Please sign in first.");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user) throw new HttpError(401, "Your sign-in has expired. Please sign in again.");
  return data.user.id;
}

// Returns the caller's permission set in the business (all permissions for the owner), or throws 403.
async function callerPermissions(businessId: string, userId: string): Promise<{ isOwner: boolean; perms: Set<string> }> {
  const notAllowed = new HttpError(403, "You are not allowed to manage this team.");
  const { data: biz, error: bizErr } = await admin.from("businesses").select("owner_id").eq("id", businessId)
    .maybeSingle();
  if (bizErr) throw new HttpError(500, "Could not check your access. Please try again.");
  if (!biz) throw notAllowed;
  if (biz.owner_id === userId) return { isOwner: true, perms: new Set(PERMISSIONS) };

  const { data: me, error: meErr } = await admin.from("members").select("*").eq("business_id", businessId)
    .eq("user_id", userId).maybeSingle<MemberRow>();
  if (meErr) throw new HttpError(500, "Could not check your access. Please try again.");
  if (!me || me.disabled || !me.permissions.includes("manageTeam")) throw notAllowed;
  return { isOwner: false, perms: new Set(me.permissions) };
}

async function findTarget(businessId: string, name: string): Promise<MemberRow> {
  const { data, error } = await admin.from("members").select("*").eq("business_id", businessId)
    .eq("username", name).maybeSingle<MemberRow>();
  if (error) throw new HttpError(500, "Could not look up that team member. Please try again.");
  if (!data) throw new HttpError(404, "There is no team member with that username in this business.");
  if (data.role === "owner") throw new HttpError(403, "The owner's login cannot be changed here.");
  return data;
}

function requireSubset(wanted: string[], caller: { isOwner: boolean; perms: Set<string> }) {
  if (caller.isOwner) return;
  const missing = wanted.filter((p) => !caller.perms.has(p));
  if (missing.length > 0) {
    throw new HttpError(403, `You can't give a permission you don't have yourself (${missing.join(", ")}).`);
  }
}

// A manager may only touch logins whose current access is within their own (otherwise resetting a password would
// let them sign in as someone with more access).
function requireCanManage(target: MemberRow, caller: { isOwner: boolean; perms: Set<string> }, callerId: string) {
  if (caller.isOwner) return;
  if (target.user_id === callerId) throw new HttpError(403, "Ask the owner to change your own login.");
  if (target.permissions.some((p) => !caller.perms.has(p))) {
    throw new HttpError(403, "You can't change a team member who has permissions you don't have.");
  }
}

// ---------- actions ----------

async function create(body: Record<string, unknown>, businessId: string, caller: { isOwner: boolean; perms: Set<string> }) {
  const memberId = uuid(body, "member_id");
  const name = username(body);
  const pw = password(body);
  const r = role(body);
  const perms = permissions(body);
  requireSubset(perms, caller);

  const { data: taken } = await admin.from("members").select("user_id").eq("username", name).maybeSingle();
  if (taken) throw new HttpError(409, "username taken");
  const { data: hasLogin } = await admin.from("members").select("user_id").eq("business_id", businessId)
    .eq("member_id", memberId).maybeSingle();
  if (hasLogin) throw new HttpError(409, "This team member already has a login.");

  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email: `${name}@${EMAIL_DOMAIN}`,
    password: pw,
    email_confirm: true,
    user_metadata: { username: name },
  });
  if (createErr || !created?.user) {
    const msg = `${createErr?.message ?? ""} ${(createErr as { code?: string } | null)?.code ?? ""}`.toLowerCase();
    if (msg.includes("already") || msg.includes("exists") || createErr?.status === 422) {
      throw new HttpError(409, "username taken");
    }
    if (msg.includes("password")) throw new HttpError(400, "That password is too weak. Please choose a longer one.");
    throw new HttpError(500, "Could not create the login. Please try again.");
  }

  const { error: insErr } = await admin.from("members").insert({
    business_id: businessId,
    user_id: created.user.id,
    member_id: memberId,
    role: r,
    permissions: perms,
    username: name,
    disabled: false,
  });
  if (insErr) {
    await admin.auth.admin.deleteUser(created.user.id); // roll back so the username is free again
    if (insErr.code === "23505") throw new HttpError(409, "username taken");
    throw new HttpError(500, "Could not save the team member. Please try again.");
  }
}

async function resetPassword(
  body: Record<string, unknown>, businessId: string, caller: { isOwner: boolean; perms: Set<string> }, callerId: string,
) {
  const name = username(body);
  const pw = password(body);
  const target = await findTarget(businessId, name);
  requireCanManage(target, caller, callerId);
  const { error } = await admin.auth.admin.updateUserById(target.user_id, { password: pw });
  if (error) throw new HttpError(500, "Could not change the password. Please try again.");
}

async function setAccess(
  body: Record<string, unknown>, businessId: string, caller: { isOwner: boolean; perms: Set<string> }, callerId: string,
) {
  const name = username(body);
  const r = role(body);
  const perms = permissions(body);
  const disabled = bool(body, "disabled");
  const target = await findTarget(businessId, name);
  requireCanManage(target, caller, callerId);
  requireSubset(perms, caller);
  const { error } = await admin.from("members").update({ role: r, permissions: perms, disabled })
    .eq("business_id", businessId).eq("user_id", target.user_id);
  if (error) throw new HttpError(500, "Could not save the new access. Please try again.");
}

async function remove(
  body: Record<string, unknown>, businessId: string, caller: { isOwner: boolean; perms: Set<string> }, callerId: string,
) {
  const name = username(body);
  const target = await findTarget(businessId, name);
  requireCanManage(target, caller, callerId);
  const { error } = await admin.auth.admin.deleteUser(target.user_id);
  if (error && error.status !== 404) {
    console.error("deleteUser failed", error);
    throw new HttpError(500, "Could not remove the login. Please try again.");
  }
  // The members row goes with the auth user (on delete cascade); make sure even if the user was already gone.
  await admin.from("members").delete().eq("business_id", businessId).eq("user_id", target.user_id);
}

async function deleteMe(callerId: string) {
  const { data: owned, error } = await admin.from("businesses").select("id").eq("owner_id", callerId);
  if (error) throw new HttpError(500, "Could not delete the account. Please try again.");
  for (const b of owned ?? []) {
    const { data: crew } = await admin.from("members").select("user_id").eq("business_id", b.id).neq("user_id", callerId);
    for (const m of crew ?? []) await admin.auth.admin.deleteUser(m.user_id);        // employee logins of this business
    const { data: files } = await admin.storage.from("photos").list(b.id, { limit: 1000 });
    if (files && files.length > 0) await admin.storage.from("photos").remove(files.map((f) => `${b.id}/${f.name}`));
    await admin.from("businesses").delete().eq("id", b.id);                           // records and members cascade
  }
  const { error: delErr } = await admin.auth.admin.deleteUser(callerId);
  if (delErr && delErr.status !== 404) {
    console.error("deleteUser failed", delErr);
    throw new HttpError(500, "Could not delete the account. Please try again.");
  }
}

// ---------- entry point ----------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply(405, { error: "Please use POST." });

  try {
    let body: Record<string, unknown>;
    try {
      const parsed = await req.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
      body = parsed as Record<string, unknown>;
    } catch {
      throw new HttpError(400, "The request body must be a JSON object.");
    }

    const callerId = await callerUserId(req);
    const action = typeof body.action === "string" ? body.action : "";
    // Delete my account (App Store rule 5.1.1(v)): any signed-in person may delete their own login. An owner's
    // business, with every record and every employee login in it, goes too. Needs no business_id.
    if (action === "delete_me") {
      await deleteMe(callerId);
      return reply(200, { ok: true });
    }
    if (!["create", "reset_password", "set_access", "remove"].includes(action)) {
      throw new HttpError(400, "Unknown action. Use create, reset_password, set_access or remove.");
    }
    const businessId = uuid(body, "business_id");
    const caller = await callerPermissions(businessId, callerId);

    switch (action) {
      case "create":
        await create(body, businessId, caller);
        break;
      case "reset_password":
        await resetPassword(body, businessId, caller, callerId);
        break;
      case "set_access":
        await setAccess(body, businessId, caller, callerId);
        break;
      case "remove":
        await remove(body, businessId, caller, callerId);
        break;
    }
    return reply(200, { ok: true });
  } catch (e) {
    if (e instanceof HttpError) return reply(e.status, { error: e.message });
    console.error(e);
    return reply(500, { error: "Something went wrong on the server. Please try again." });
  }
});
