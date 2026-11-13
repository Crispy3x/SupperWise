// Deletes the signed-in person's account (App Store guideline 5.1.1(v)): their shared recipes, reports and scan
// counts go with it (database cascades), and their uploaded photos are removed from storage.
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { authorization: req.headers.get("authorization") ?? "" } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "Sign in first." }, 401);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  // Photos live under <user id>/ in the recipe-photos bucket.
  const { data: files } = await admin.storage.from("recipe-photos").list(user.id, { limit: 1000 });
  if (files && files.length) await admin.storage.from("recipe-photos").remove(files.map((f) => `${user.id}/${f.name}`));
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) return json({ error: "Couldn't delete the account. Try again, or email support." }, 500);
  return json({ deleted: true });
});
