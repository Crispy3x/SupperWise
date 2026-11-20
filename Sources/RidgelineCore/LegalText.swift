import Foundation

/// The privacy policy and support text shown inside the app. The same text is served by the server at /privacy.
public enum LegalText {
    public static let privacy = """
    Privacy Policy for Ridgeline Ops

    What stays on your device
    Your clients, sites, jobs, quotes, invoices, team, timesheets, photos and settings are saved on your own phone, iPad or Mac. We do not run a database of your business.

    What leaves your device, and why
    - Addresses you enter are sent to Apple to find their place on the map and to work out drive times (Apple Maps).
    - Your location is sent to the US National Weather Service to get the forecast. This works for places in the United States.
    - If you set up a server, the assistant, client pages, invoice emails and live truck map go through it. Client page data (a property label, status, arrival time, rounded map position and bills) is stored on that server so your clients can open their private link. If you turn on "Show this truck to clients", your truck's position is sent there every half minute while the app is open.
    - When you use the assistant, your question and the business details it looks up (such as client names, addresses and invoice amounts) are sent through your server to Anthropic, which makes the AI model. You agree to this on the assistant's first screen and can turn it off.
    - When you email an invoice or season link, the client's email address and the message go through your server to your email provider.
    - Purchases are handled by Apple. We never see your card.

    What we do not do
    We do not sell your data, show ads, track you across other apps or websites, or build a profile of you.

    Your choices and deleting your data
    You can delete your account and all data on the device in Profile, Delete account. Client pages and requests held on your server are removed after their time limit. Ask your server's owner (you, if you set it up) to delete them sooner.

    Children
    Ridgeline Ops is business software and is not for children.

    Changes
    If this policy changes, the new version will be in the app.
    """

    public static let support = """
    Support

    Help and questions: use the Support link on the Ridgeline Ops page in the App Store.

    Cancel or change a plan: open Settings on your iPhone, tap your name, then Subscriptions.
    Restore a plan you already bought: Menu, Settings, Subscription, Restore purchases.
    Delete your account and data: Menu, Settings, Profile and sign-in, Delete account.
    """
}
