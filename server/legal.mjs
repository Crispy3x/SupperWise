// The words for the three public pages the App Store listing links to: /privacy, /support and /terms.
// No token is needed to read them. They are served by portal.mjs in the same card style as the client page.
//
// KEEP IN STEP: PRIVACY is the same text as LegalText.privacy in the app (Sources/RidgelineCore/LegalText.swift).
// test/pages.test.mjs compares the two word for word, so change both together. No backslashes or backticks in it.

export const PRIVACY = `Privacy Policy for Ridgeline Ops

What stays on your device
Your clients, sites, jobs, quotes, invoices, expenses and receipt photos, team, timesheets, proof-of-service photos and settings are saved on your own phone, iPad or Mac. We do not run a database of your business. If you sign in with Apple, the name and email address Apple gives the app are saved on your device only. Contacts you pick from your address book are copied into the app and stay on your device; the app never reads the rest of your address book. Reminders are notifications made on your device.

What leaves your device, and why
- Addresses you enter are sent to Apple to find their place on the map and to work out drive times (Apple Maps).
- Your yard location is sent to the US National Weather Service to get the forecast. This works for places in the United States.
- When you use the assistant, your question and the business details it looks up to answer (such as job titles and times, client names and addresses, invoice numbers and amounts, and team member names) are sent to Anthropic, the company that makes the AI model. Client phone numbers and email addresses are not sent. How it gets there depends on your setup: straight from your device if you saved your own Anthropic key (the key is kept in the Keychain on your device and sent only to Anthropic), through your own server if you set one up, and otherwise through the Ridgeline Ops assistant server. The assistant server passes your question on and does not store it. It keeps only a running total of how much each device has used, under a random number made by the app that is not tied to your name, your account or your Apple ID. You agree to this on the assistant's first screen and can turn the assistant off at any time.
- If you tap to talk to the assistant, your speech is turned into text on your device when it can do that. On devices that cannot, Apple's speech service does it.
- If you set up your own server, client pages, invoice emails and the live truck map go through it, and so do Google drive times if you added a Google key there. Client page data (a property label, status, arrival time, rounded map position and bills) is stored on that server so your clients can open their private link. If you turn on "Show this truck to clients", your position is sent there up to three times a minute while the app is open, and is shown only to clients who are waiting for service.
- When you email an invoice, a payment reminder or a season link, the client's email address and the message go through your server to your email provider.
- Text messages to clients are written in the app and sent by you from your own Messages app.
- Purchases are handled by Apple. We never see your card.

What we do not do
We do not sell your data, show ads, track you across other apps or websites, or build a profile of you.

Your choices and deleting your data
You can delete your account and all data on the device in Menu, Settings, Profile and sign-in, Delete my account and data. That also removes your saved server token and Anthropic key from the device. Client pages and requests held on your server are removed after their time limit. Ask your server's owner (you, if you set it up) to delete them sooner. Anthropic keeps what the assistant is sent for a limited time under its own privacy policy.

Children
Ridgeline Ops is business software and is not for children.

Changes
If this policy changes, the new version will be in the app and on the privacy page linked from the App Store.`;

/** Apple's standard licence agreement, which covers the app (no custom terms). */
export const TERMS_URL = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/** A support address is only an address: one line, no spaces, something@something.tld. Anything else is left out. */
export function cleanSupportEmail(v) {
  const t = typeof v === 'string' ? v.trim() : '';
  return t.length <= 254 && /^[^\s@<>"'&]+@[^\s@<>"'&]+\.[^\s@<>"'&]+$/.test(t) ? t : '';
}

/** The support page as [heading, lines] sections. Mirrors LegalText.support in the app, with the contact line added when set. */
export function supportSections(email) {
  const contact = cleanSupportEmail(email);
  return [
    ['Get help', contact
      ? [`Email ${contact} and say what you were doing and what you saw. We read every message.`]
      : ['Use the App Support link on the Ridgeline Ops page in the App Store.']],
    ['Cancel or change a plan', ['Plans are bought with your Apple ID, so Apple handles them. On your iPhone open Settings, tap your name, then Subscriptions, and choose Ridgeline Ops.',
      'A plan stays active until the end of the period you paid for. Deleting the app does not cancel it.']],
    ['Restore a plan you already bought', ['In the app open Menu, Subscription, then tap Restore purchases. Use the same Apple ID you bought the plan with.']],
    ['Delete your account and data', ['In the app open Menu, Settings, Profile and sign-in, then tap Delete my account and data. This removes everything the app saved on that device, including your saved server token and Anthropic key.',
      'Deleting does not cancel a plan: cancel it first in Settings on your iPhone.',
      'Client pages kept on a server you set up are removed after their time limit, or sooner if you delete them there.']],
    ['The assistant is not answering', ['Open the assistant and read the message under your question: it says what went wrong and what to do. Starting a new chat (the pencil button) fixes most problems.']],
  ];
}

/** Splits the policy into a title and [heading, paragraphs, bullets] sections, the way the app's text is laid out. */
export function privacySections(text = PRIVACY) {
  const [title, ...blocks] = text.split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean);
  return { title, sections: blocks.map((b) => {
    const [heading, ...rest] = b.split('\n');
    return { heading, paragraphs: rest.filter((l) => !l.startsWith('- ')), bullets: rest.filter((l) => l.startsWith('- ')).map((l) => l.slice(2)) };
  }) };
}
