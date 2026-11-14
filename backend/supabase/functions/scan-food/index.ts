// Supperwise food scan: a photo of a plate, a packaged item or a single food in, an estimate of what it is,
// its ingredients and its nutrition out. The app turns the nutrition into the 1–100 health score it already uses
// for barcodes and restaurant dishes, and checks the ingredients against the household's allergies.
//
// Secrets (set in Supabase: Edge Functions → Secrets): ANTHROPIC_API_KEY.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MONTHLY_LIMIT = 100;          // per person; the app shows what's left
const MAX_IMAGE_BYTES = 3_500_000;  // the app sends a downscaled JPEG, usually 200–600 KB

const anthropic = new Anthropic();  // reads ANTHROPIC_API_KEY

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["kind", "name", "portion", "ingredients", "nutrition", "ultraProcessed", "confidence", "notes"],
  properties: {
    kind: { type: "string", enum: ["meal", "packaged", "single_food", "not_food"] },
    name: { type: "string", description: "Short everyday name, e.g. 'Chicken Caesar salad'" },
    portion: { type: "string", description: "The portion estimated, e.g. 'about 1½ cups (350 g)'" },
    ingredients: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "visible"],
        properties: {
          name: { type: "string" },
          visible: { type: "boolean", description: "true if seen in the photo, false if a likely hidden ingredient (oil, butter, dressing, cheese in a sauce)" },
        },
      },
    },
    nutrition: {
      type: "object",
      additionalProperties: false,
      required: ["kcal", "proteinG", "fiberG", "addedSugarG", "saturatedFatG", "sodiumMg"],
      properties: {
        kcal: { type: "number" }, proteinG: { type: "number" }, fiberG: { type: "number" },
        addedSugarG: { type: "number" }, saturatedFatG: { type: "number" }, sodiumMg: { type: "number" },
      },
    },
    allergens: {
      type: "array",
      items: { type: "string", enum: ["dairy", "egg", "gluten", "soy", "fish", "shellfish", "nuts", "sesame"] },
      description: "Allergens likely present, including hidden ones",
    },
    ultraProcessed: { type: "boolean" },
    fried: { type: "boolean" },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    notes: { type: "string", description: "One plain sentence: what was hard to judge, or empty" },
  },
} as const;

const SYSTEM = `You estimate the nutrition of food from a single photo for a family meal-planning app.
Identify the food, estimate the portion shown from visual cues (plate size, utensils, packaging), list the ingredients
(including likely hidden ones such as cooking oil, butter, dressings and sauces, marked visible=false), and estimate
nutrition for the portion shown. If a nutrition label or packaging is readable, use its numbers for the portion shown.
Be realistic rather than flattering: restaurant and takeout portions are usually large and oily.
List every allergen that is likely present. If the photo isn't food, set kind to not_food and use zeros.
These are estimates; say in notes what was hard to judge.`;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  // Who's asking: the app sends the person's Supabase session token.
  const auth = req.headers.get("authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { authorization: auth } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "Sign in to scan food." }, 401);

  let body: { image?: string; mediaType?: string; mode?: string; catalog?: { id: string; name: string }[] };
  try { body = await req.json(); } catch { return json({ error: "Send JSON with an image." }, 400); }
  const image = body.image ?? "";
  const mediaType = body.mediaType === "image/png" ? "image/png" : "image/jpeg";
  if (!image || image.length * 0.75 > MAX_IMAGE_BYTES) return json({ error: "The photo is missing or too large." }, 400);

  // Count the scan before calling the model, so a burst of requests can't go over the limit.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: used, error: usageError } = await admin.rpc("use_scan", { p_user: user.id, p_limit: MONTHLY_LIMIT });
  if (usageError) return json({ error: "Couldn't check your scans. Try again." }, 500);
  if (used === -1) return json({ error: `That's all ${MONTHLY_LIMIT} scans for this month. They reset on the 1st.`, remaining: 0 }, 429);

  // Fridge or pantry photo: which of the app's catalog ingredients are on the shelves.
  if (body.mode === "fridge") {
    const catalog = (body.catalog ?? []).filter((c) => c && typeof c.id === "string" && typeof c.name === "string").slice(0, 500);
    if (catalog.length === 0) return json({ error: "Missing the ingredient list." }, 400);
    const ids = catalog.map((c) => c.id);
    const schema = {
      type: "object", additionalProperties: false, required: ["items", "notes"],
      properties: {
        items: { type: "array", items: { type: "object", additionalProperties: false, required: ["id", "seen"],
          properties: { id: { type: "string", enum: ids }, seen: { type: "string", description: "What you saw, e.g. 'carton of eggs'" } } } },
        notes: { type: "string" },
      },
    };
    try {
      const response = await anthropic.beta.messages.create({
        model: "claude-opus-5-5",
        max_tokens: 4000,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: { effort: "low", format: { type: "json_schema", schema } },
        system: "You look at a photo of a fridge, freezer, pantry shelf or counter and list which of the given grocery " +
          "ingredients are clearly visible. Use only ids from the list. Match sensibly (a block of orange cheese is sharp " +
          "cheddar; a bag of shredded cheese is shredded mozzarella or Monterey Jack, whichever fits; a carton of eggs is eggs). " +
          "Don't guess at things you can't see or hidden inside closed opaque containers. Each id at most once.",
        messages: [{ role: "user", content: [
          { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
          { type: "text", text: "Ingredient list (id: name):\n" + catalog.map((c) => `${c.id}: ${c.name}`).join("\n") },
        ] }],
      });
      if (response.stop_reason === "refusal") return json({ error: "That photo couldn't be scanned." }, 422);
      const text = response.content.find((b) => b.type === "text");
      if (!text || text.type !== "text") return json({ error: "The scan didn't return a result." }, 502);
      return json({ result: JSON.parse(text.text), remaining: MONTHLY_LIMIT - (used as number) });
    } catch (e) {
      if (e instanceof Anthropic.RateLimitError) return json({ error: "Scanning is busy. Try again in a moment." }, 503);
      return json({ error: "The scan failed. Try again." }, 502);
    }
  }

  try {
    const response = await anthropic.beta.messages.create({
      model: "claude-opus-5-5",
      max_tokens: 4000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
      system: SYSTEM,
      messages: [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
          { type: "text", text: "Estimate this food." },
        ],
      }],
    });
    if (response.stop_reason === "refusal") return json({ error: "That photo couldn't be scanned." }, 422);
    if (response.stop_reason === "max_tokens") return json({ error: "The scan didn't finish. Try again." }, 502);
    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") return json({ error: "The scan didn't return a result." }, 502);
    const result = JSON.parse(text.text);
    return json({ result, remaining: MONTHLY_LIMIT - (used as number) });
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) return json({ error: "Scanning is busy. Try again in a moment." }, 503);
    if (e instanceof Anthropic.APIConnectionError) return json({ error: "Couldn't reach the scanner. Try again." }, 503);
    if (e instanceof Anthropic.APIError) return json({ error: "The scan failed. Try again." }, 502);
    return json({ error: "The scan failed. Try again." }, 500);
  }
});
