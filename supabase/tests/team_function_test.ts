// Behaviour tests for functions/team/index.ts against an in-memory fake of Supabase Auth + PostgREST.
// Run: deno test --allow-env --allow-net=registry.npmjs.org supabase/tests/team_function_test.ts
// (No real Supabase project is touched: global fetch is replaced before the function is loaded.)

Deno.env.set("SUPABASE_URL", "https://fake.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-test-key");

type Row = Record<string, unknown>;
const users = new Map<string, { id: string; email: string; password: string }>();
const tokens = new Map<string, string>(); // access token -> user id
let businesses: Row[] = [];
let members: Row[] = [];

function addUser(id: string, email: string, token?: string) {
  users.set(id, { id, email, password: "x" });
  if (token) tokens.set(token, id);
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function matches(row: Row, params: URLSearchParams) {
  for (const [k, v] of params) {
    if (["select", "order", "limit", "columns"].includes(k)) continue;
    if (!v.startsWith("eq.")) throw new Error("fake only supports eq filters: " + k + "=" + v);
    if (String(row[k]) !== v.slice(3)) return false;
  }
  return true;
}

globalThis.fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
  const req = input instanceof Request ? input : new Request(input, init);
  const url = new URL(req.url);
  const method = req.method;
  const path = url.pathname;
  const body = ["POST", "PUT", "PATCH"].includes(method) ? await req.json() : null;

  if (path === "/auth/v1/user") {
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const id = tokens.get(token);
    return id ? json(200, { id, email: users.get(id)!.email }) : json(401, { code: 401, msg: "invalid JWT" });
  }
  if (path === "/auth/v1/admin/users" && method === "POST") {
    if ([...users.values()].some((u) => u.email === body.email)) {
      return json(422, { code: "email_exists", msg: "A user with this email address has already been registered" });
    }
    const id = crypto.randomUUID();
    users.set(id, { id, email: body.email, password: body.password });
    return json(200, { id, email: body.email });
  }
  const m = path.match(/^\/auth\/v1\/admin\/users\/(.+)$/);
  if (m) {
    const u = users.get(m[1]);
    if (!u) return json(404, { code: "user_not_found", msg: "User not found" });
    if (method === "GET") return json(200, { id: u.id, email: u.email });
    if (method === "PUT") {
      if (body.password) u.password = body.password;
      return json(200, { id: u.id, email: u.email });
    }
    if (method === "DELETE") {
      users.delete(u.id);
      members = members.filter((r) => r.user_id !== u.id); // on delete cascade
      return json(200, {});
    }
  }
  const t = path.match(/^\/rest\/v1\/(businesses|members)$/);
  if (t) {
    const table = t[1] === "businesses" ? businesses : members;
    if (method === "GET") return json(200, table.filter((r) => matches(r, url.searchParams)));
    if (method === "POST") {
      const rows = Array.isArray(body) ? body : [body];
      for (const r of rows) {
        if (members.some((x) => r.username && x.username === r.username)) {
          return json(409, { code: "23505", message: "duplicate key value violates unique constraint" });
        }
        members.push({ ...r });
      }
      return json(201, []);
    }
    if (method === "PATCH") {
      table.filter((r) => matches(r, url.searchParams)).forEach((r) => Object.assign(r, body));
      return new Response(null, { status: 204 });
    }
    if (method === "DELETE") {
      members = members.filter((r) => !matches(r, url.searchParams));
      return new Response(null, { status: 204 });
    }
  }
  return json(500, { message: "fake: unhandled " + method + " " + path });
};

// Capture the handler instead of starting a server.
let handler: (req: Request) => Promise<Response> = () => Promise.reject("not loaded");
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: typeof handler) => {
  handler = h;
  return { finished: Promise.resolve(), shutdown() {} };
};
await import("../functions/team/index.ts");

const B = "11111111-1111-1111-1111-111111111111";
const OTHER_B = "22222222-2222-2222-2222-222222222222";
const OWNER = "aaaaaaaa-0000-0000-0000-000000000001";
const MGR = "aaaaaaaa-0000-0000-0000-000000000002";
const CREW = "aaaaaaaa-0000-0000-0000-000000000003";
const OUTSIDER = "aaaaaaaa-0000-0000-0000-000000000004";

function reset() {
  users.clear();
  tokens.clear();
  addUser(OWNER, "owner@x.test", "t-owner");
  addUser(MGR, "mgr@crew.ridgelineops.app", "t-mgr");
  addUser(CREW, "crew@crew.ridgelineops.app", "t-crew");
  addUser(OUTSIDER, "out@x.test", "t-out");
  businesses = [{ id: B, owner_id: OWNER }, { id: OTHER_B, owner_id: OUTSIDER }];
  members = [
    { business_id: B, user_id: OWNER, member_id: null, role: "owner", permissions: [], username: null, disabled: false },
    { business_id: B, user_id: MGR, member_id: "m-mgr", role: "manager", permissions: ["manageTeam", "viewAllJobs", "logVisits"], username: "mgr", disabled: false },
    { business_id: B, user_id: CREW, member_id: "m-crew", role: "crewMember", permissions: ["logVisits"], username: "crew", disabled: false },
    { business_id: OTHER_B, user_id: OUTSIDER, member_id: null, role: "owner", permissions: [], username: null, disabled: false },
  ];
}

async function call(token: string | null, body: unknown, method = "POST") {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await handler(new Request("https://fake.supabase.co/functions/v1/team", {
    method, headers, body: method === "POST" ? JSON.stringify(body) : undefined,
  }));
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null, cors: res.headers.get("Access-Control-Allow-Origin") };
}

function eq(a: unknown, b: unknown, what: string) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${what}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}

const newMember = (over: Row = {}) => ({
  action: "create", business_id: B, member_id: "33333333-3333-3333-3333-333333333333", username: "Jake.S",
  password: "longenough", role: "crewMember", permissions: ["logVisits", "useTimeClock"], ...over,
});

Deno.test("OPTIONS answers CORS preflight", async () => {
  reset();
  const handled = await handler(new Request("https://fake.supabase.co/functions/v1/team", { method: "OPTIONS" }));
  eq(handled.status, 200, "status");
  eq(handled.headers.get("Access-Control-Allow-Origin"), "*", "cors");
});

Deno.test("owner creates a login: lowercased username, crew email, members row", async () => {
  reset();
  const r = await call("t-owner", newMember());
  eq(r, { status: 200, body: { ok: true }, cors: "*" }, "response");
  const u = [...users.values()].find((x) => x.email === "jake.s@crew.ridgelineops.app");
  if (!u) throw new Error("auth user not created");
  const row = members.find((x) => x.username === "jake.s")!;
  eq([row.business_id, row.user_id, row.role, row.permissions, row.disabled], [B, u.id, "crewMember", ["logVisits", "useTimeClock"], false], "row");
});

Deno.test("duplicate username -> 409 username taken", async () => {
  reset();
  await call("t-owner", newMember());
  const r = await call("t-owner", newMember({ member_id: "44444444-4444-4444-4444-444444444444" }));
  eq([r.status, r.body], [409, { error: "username taken" }], "409");
});

Deno.test("validation: username, password, role, permissions", async () => {
  reset();
  eq((await call("t-owner", newMember({ username: "ab" }))).status, 400, "short username");
  eq((await call("t-owner", newMember({ username: "bad name" }))).status, 400, "space in username");
  eq((await call("t-owner", newMember({ password: "short" }))).status, 400, "short password");
  eq((await call("t-owner", newMember({ role: "owner" }))).status, 400, "owner role");
  eq((await call("t-owner", newMember({ permissions: ["fly"] }))).status, 400, "unknown permission");
  eq((await call("t-owner", newMember({ member_id: "nope" }))).status, 400, "bad member id");
  eq((await call("t-owner", { action: "explode", business_id: B })).status, 400, "unknown action");
  const r = await call("t-owner", newMember({ password: "short" }));
  if (typeof r.body.error !== "string") throw new Error("error must be a sentence");
});

Deno.test("auth: no token 401, crew 403, other business owner 403", async () => {
  reset();
  eq((await call(null, newMember())).status, 401, "no token");
  eq((await call("t-bogus", newMember())).status, 401, "bad token");
  eq((await call("t-crew", newMember())).status, 403, "crew");
  eq((await call("t-out", newMember())).status, 403, "outsider");
  eq((await call("t-owner", newMember({ business_id: OTHER_B }))).status, 403, "owner of A acting on B");
});

Deno.test("manager: may only grant own permissions; cannot touch owner, self, or stronger members", async () => {
  reset();
  eq((await call("t-mgr", newMember({ permissions: ["logVisits"] }))).status, 200, "grant subset");
  const r = await call("t-mgr", newMember({ username: "x.y", member_id: "55555555-5555-5555-5555-555555555555", permissions: ["viewRevenue"] }));
  eq(r.status, 403, "grant viewRevenue");
  eq((await call("t-mgr", { action: "set_access", business_id: B, username: "crew", role: "crewLead", permissions: ["manageSettings"], disabled: false })).status, 403, "escalate crew");
  eq((await call("t-mgr", { action: "set_access", business_id: B, username: "mgr", role: "manager", permissions: ["manageTeam"], disabled: false })).status, 403, "self");
  members.push({ business_id: B, user_id: OUTSIDER, member_id: "m-off", role: "office", permissions: ["viewRevenue"], username: "office", disabled: false });
  eq((await call("t-mgr", { action: "reset_password", business_id: B, username: "office", password: "newpassword" })).status, 403, "reset stronger member");
  eq((await call("t-mgr", { action: "reset_password", business_id: B, username: "crew", password: "newpassword" })).status, 200, "reset crew");
});

Deno.test("set_access, reset_password, remove", async () => {
  reset();
  let r = await call("t-owner", { action: "set_access", business_id: B, username: "CREW", role: "crewLead", permissions: ["logVisits", "viewAllJobs", "logVisits"], disabled: true });
  eq(r.status, 200, "set_access");
  const row = members.find((x) => x.username === "crew")!;
  eq([row.role, row.permissions, row.disabled], ["crewLead", ["viewAllJobs", "logVisits"], true], "row updated");
  r = await call("t-owner", { action: "set_access", business_id: B, username: "crew", role: "crewLead", permissions: [] });
  eq(r.status, 400, "missing disabled");
  r = await call("t-owner", { action: "reset_password", business_id: B, username: "crew", password: "brandnewpw" });
  eq(r.status, 200, "reset");
  eq(users.get(CREW)!.password, "brandnewpw", "password changed");
  r = await call("t-owner", { action: "remove", business_id: B, username: "nobody" });
  eq(r.status, 404, "unknown username");
  r = await call("t-owner", { action: "remove", business_id: B, username: "crew" });
  eq([r.status, r.body], [200, { ok: true }], "remove");
  eq([users.has(CREW), members.some((x) => x.user_id === CREW)], [false, false], "gone");
});

Deno.test("GET is refused", async () => {
  reset();
  eq((await call("t-owner", null, "GET")).status, 405, "GET");
});
