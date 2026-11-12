# First batch: 10 slideshows (TikTok photo posts / Instagram)

| id | angle | slide one |
|---|---|---|
| 01-six-pm | pain | 6pm, fridge open, four people asking what's for dinner |
| 02-receipt | pain | the meal plan said $80. the receipt said otherwise |
| 03-whole-jar | curiosity | the recipe needs one teaspoon. the store sells the whole jar |
| 04-veg-at-table | curiosity | one vegetarian at the table changes the whole list |
| 05-shared-ingredients | list | 5 weeknight dinners that share half their ingredients |
| 06-not-spicy | list | dinners that work when one kid won't eat spicy |
| 07-cumin-thread | story | text thread: three jars of cumin |
| 08-sister-visiting | story | text thread: the vegetarian sister visits |
| 09-four-people | demo | what happens when you type in 4 people and $95 |
| 10-plan-first | demo | when the "free trial" charges you before you see a recipe |

**Missing from this batch:**
- **The "screen" look** (the app's real screen in a phone). It needs simulator captures.
- **The "photo" look.** It needs photos you own.

The demo posts describe the app in words until captures exist.

**Facts on every slide** are checked against the recipes in the app (ingredients shared, mild versions, the vegetarian plate). Nothing is invented: no results, no testimonials, no numbers about users.

## Posting (you post; nothing is posted for you)
1. Upload the numbered PNGs in order as a TikTok photo post, and paste caption.txt.
2. Add a sound from TikTok's library when you post.
3. Instagram crops the top and bottom. The words survive, but check the preview.
4. One or two posts a day beats ten in an afternoon.
5. Each final slide says "coming soon to iPhone". Change it to "on the App Store" once the app is live.

## After posting, log it
```
node <app-marketer>/scripts/content.mjs posted 01-six-pm tiktok
node <app-marketer>/scripts/content.mjs numbers 01-six-pm tiktok views=12000 likes=300 saves=90
```
Or just tell Claude the numbers in plain words. After 5 posts have numbers, `winners` says what to remake.
