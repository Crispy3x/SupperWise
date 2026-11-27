import Foundation

/// The privacy policy and support text shown inside the app.
///
/// KEEP IN STEP: the server shows the same policy at /privacy from the copy in server/legal.mjs. A server test
/// (server/test/pages.test.mjs) compares the two word for word, so change both together. No backslashes or backticks
/// in this text, so it reads the same in Swift and in JavaScript.
public enum LegalText {
    public static let privacy = """
    Privacy Policy for Ridgeline Ops

    What stays on your device
    Your clients, sites, jobs, quotes, invoices, expenses and receipt photos, team, timesheets, proof-of-service photos and settings are saved on your own phone, iPad or Mac. We do not run a database of your business. If you sign in with Apple, the name and email address Apple gives the app are saved on your device only. Contacts you pick from your address book are copied into the app and stay on your device; the app never reads the rest of your address book. Reminders are notifications made on your device.

    What leaves your device, and why
    - Addresses you enter are sent to Apple to find their place on the map and to work out drive times (Apple Maps).
    - Your yard location is sent to the US National Weather Service to get the forecast. This works for places in the United States.
    - When you use the assistant, your question and the business details it looks up to answer (such as job titles and times, client names and addresses, invoice numbers and amounts, and team member names) are sent to Anthropic, the company that makes the AI model. Client phone numbers and email addresses are not sent. How it gets there depends on your setup: straight from your device if you saved your own Anthropic key (the key is kept in the Keychain on your device and sent only to Anthropic), through your own server if you set one up, and otherwise through the Ridgeline Ops assistant server. The assistant server passes your question on and does not store it. It keeps only a running total of how much each device has used, under a random number made by the app that is not tied to your name, your account or your Apple ID. You agree to this on the assistant's first screen and can turn the assistant off at any time.
    - If you tap to talk to the assistant, your speech is turned into text on your device when it can do that. On devices that cannot, Apple's speech service does it.
    - If you set up your own server, client pages, invoice emails and the live truck map go through it, and so do Google drive times if you added a Google key there. Client page data (a property label, status, arrival time, rounded map position and bills) is stored on that server so your clients can open their private link. If you let clients sign in on your website with their last name and house number, only a salted one-way code made from them is stored there, never the name itself. If you turn on "Show this truck to clients", your position is sent there up to three times a minute while the app is open, and is shown only to clients who are waiting for service.
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
    If this policy changes, the new version will be in the app and on the privacy page linked from the App Store.
    """

    public static let support = """
    Support

    Help and questions: use the Support link on the Ridgeline Ops page in the App Store.

    Cancel or change a plan: open Settings on your iPhone, tap your name, then Subscriptions. A plan stays active until the end of the period you paid for.
    Restore a plan you already bought: Menu, Subscription, Restore purchases. Use the same Apple ID you bought it with.
    Delete your account and data: Menu, Settings, Profile and sign-in, Delete my account and data. Deleting does not cancel a plan; cancel it in Settings on your iPhone first.
    The assistant is not answering: open the assistant and read the message under your question. It says what went wrong and what to do.
    """
}
