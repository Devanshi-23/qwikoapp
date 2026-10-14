# Qwiko Delivery Partner

Flutter app for Qwiko delivery partners (riders): sign-in and KYC, going online, accepting orders, pickup and delivery, earnings and payouts, incentives, profile, support and safety.

The app currently runs entirely on **local demo data**. There is no backend, and no network requests are made while delivering an order. Orders, customers, calls, chats, maps, payouts and SOS alerts are simulated and labelled `DEMO`. The only external action is **Call 112** on the Safety screen.

The full roadmap is in [`DELIVERY_PARTNER_APP_PLAN.md`](DELIVERY_PARTNER_APP_PLAN.md).

## Run in demo mode

```powershell
flutter pub get
flutter run
```

After changing services or demo data, use a hot restart (not hot reload).

## Demo sign-in

- **Phone:** any valid 10-digit mobile number, then OTP `123456`.
- **Email:** any valid email with a password of at least 8 characters (for example `arjun@example.com` / `password123`).

After the first login the app remembers you: the next launch opens straight to Home, even with no internet. **Log out** forgets it. In a real build, the first OTP login needs the internet, because the server sends and checks the code. The demo checks `123456` on the phone, so it also works in airplane mode.

Which account you land in is chosen in Demo Controls:

| Demo account | What it shows |
| --- | --- |
| Verified partner | Ready to deliver, with 60 days of history |
| New sign-up | Needs vehicle, documents and bank details |
| Verification pending | Documents under review; approve or reject from Demo Controls |
| Rejected document | Aadhaar card needs a new upload |
| Suspended | Account on hold; only Help is available |

## Demo Controls

Open them from **Settings → Demo controls**, or long-press any `DEMO` pill.

- **Scenarios:** pick one of the 26 scripted demos, read its steps, and tap **Run scenario**. This resets the data and applies the setup; trip scenarios run at 5× speed.
- **Offers:** send an offer now (normal, cash on delivery, batched, short expiry, taken by another rider).
- **Simulation:** speed, jump to the store or customer, lose GPS, location permission, network offline, rain, zone demand.
- **Customer:** never answers, shares a new location, UPI fails, tips after delivery; reveal the delivery OTP.
- **Failures:** next request fails, next photo capture fails, payout fails, reject the next document upload.
- **Account:** switch demo account, expire a document, set cash in hand, run the weekly payout.
- **Reset demo data** (with confirmation) and the component gallery.

## Checks

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build web
```

## Google Maps (later)

Maps and routes use an offline demo renderer by default. To switch to Google:

- Android: add `MAPS_API_KEY=your_key` to `android/local.properties`.
- iOS: replace the placeholder in `ios/Runner/AppDelegate.swift`.
- Dart: run with `--dart-define=MAP_PROVIDER=google --dart-define=MAPS_API_KEY=your_key`.

Without a key, the app logs a warning and keeps the demo map. See section 7 of the plan for the other integration points (backend, push notifications, payments, persistence).

## Before a store release

`applicationId` is still `com.example.qwiko_delivery_agent` and must be changed, together with the signing configuration. iOS builds need a Mac.
