# App Store Connect checklist (who does each)

## You: before anything else
- [ ] Apple Developer Program membership ($99/yr)
- [ ] Agreements, Tax and Banking: **Paid Apps Agreement active**, with bank and tax forms done. It's needed for subscriptions.
- [ ] A bundle id you own. `com.supperwise.app` may be taken; change it in Xcode and in the product ids if so.
- [ ] A real privacy policy URL and support URL/email. Replace `supperwise.app/privacy` and `support@supperwise.app` in SettingsView.swift and FirstWeekView.swift.
- [ ] A trademark check on "Supperwise" in each country you'll sell in. The store search only showed the name is free on the US store.

## App information
- [ ] Name, subtitle, category (Food & Drink), content rights ("does not contain third-party content"), age rating (age-rating.md), privacy policy URL
- [ ] EU: trader status under the Digital Services Act, if you sell in the EU

## Subscriptions
- [ ] Subscription group "Supperwise" with localizations
- [ ] `com.supperwise.app.yearly`: price (placeholder $29.99), 7-day free introductory offer **on this product**, display name, description, review screenshot
- [ ] `com.supperwise.app.monthly`: price (placeholder $7.99), display name, description, review screenshot
- [ ] Both **Ready to Submit** and **added to this version's submission**

## App privacy
- [ ] "No data collected" (privacy-label.md), published

## The version
- [ ] Screenshots (6.9" iPhone at minimum), made from real captures in step 4.4
- [ ] Description, keywords, promotional text, support URL, marketing URL (optional)
- [ ] Build uploaded from **Xcode 26 / iOS 26 SDK**, version 1.0 (1)
- [ ] Export compliance: no non-exempt encryption (already set in the build: ITSAppUsesNonExemptEncryption = NO)
- [ ] Review notes: paste review-notes.txt. No demo account needed.
- [ ] Release: manual, so you choose the day

## Before you press Submit
- [ ] TestFlight on a real iPhone: the full walk in README.md, including a sandbox purchase and Restore
- [ ] Recipe photos replaced with your own; the dish_* stand-ins are Unsplash images
