# Aster: Dodo checkout aur license setup

> **Future paid-release reference only.** The current Aster release makes all implemented features free for everyone, with no payment, license key, trial expiry, or first-100-user limit. `AsterAccessPolicy.requiresLicense = false` disables paid access requirements and Dodo licensing requests. Do not follow this guide to collect payments for the current free build. See [FREE_RELEASE.md](FREE_RELEASE.md) for the active release flow. Re-enabling paid access requires a deliberate reviewed change after Dodo approval, configuration, and end-to-end testing.

Verified against Dodo's official documentation on 19 October 2026.

**Launch setup: one global Dodo checkout, one-time purchase, one active Mac, no expiration.** Dodo hosts payment collection and sends the license email. Aster activates and checks that license through Dodo's public API. Is launch ke liye apna backend, webhook server, private API key, app signup ya email/password authentication nahi chahiye. The buyer enters an email at checkout to receive the receipt and key.

The repository starts unconfigured. A successful build is not evidence that a real payment, payout or license email has been tested. Real merchant/product IDs, account approval, end-to-end payment checks, Developer ID signing and notarization remain release steps.

## Free and Pro

| Free, with real data | Pro, after license activation |
| --- | --- |
| Disk scans and storage map | Move reviewed files to Trash |
| Large-file search with filenames and sizes | Full file paths, Copy Path and Show/Reveal in Finder |
| Cache/log/developer-cache inventory | Uninstall supported apps and selected related data |
| Installed app and possible-leftover inventory | Clean supported caches/logs and remove selected possible leftovers |
| Cleanup queue and preview, with full paths locked | Execute the selected cleanup after exact-path review and separate confirmation |

Free is the product preview; there is no timed Pro trial in this launch. Pro never bypasses macOS permissions, protected-path checks, running-app protection, partial-scan restrictions or the existing review/confirmation flow. “Detected cache” does not mean “unused” or automatically safe to remove. Docker-managed data and inspection-only items remain protected.

## 1. Prepare the merchant account

Open [Dodo Dashboard](https://app.dodopayments.com/). India is on Dodo's [supported merchant and payout country list](https://docs.dodopayments.com/miscellaneous/accepted-countries-and-territories).

In **Verification**, choose **Individual** or **Registered Entity** to match how you actually operate. Supply product information, identity verification and bank details; registered entities also complete business verification. The bank account name must match the verified individual or business. Live payments and payouts require the applicable reviews to pass; approval is not automatic.

Before submitting the product, publish a website with its actual features and price, terms, privacy policy, refund policy and working support contact. Explain the one-Mac license and update policy clearly. Dodo handles the transaction's applicable sales tax/VAT as Merchant of Record; your own business accounting remains separate. [Account verification](https://docs.dodopayments.com/miscellaneous/verification-process) · [Merchant of Record](https://docs.dodopayments.com/features/mor-introduction)

## 2. Create the product in Test Mode first

Keep the dashboard sidebar's **Live Mode** switch off.

1. Open **Products** and create a product named **Aster Pro — 1 Mac**.
2. Set **Pricing Type → One Time**, the chosen price/currency and the accurate software tax category. Do not choose a subscription.
3. Add a description such as: “Unlock reviewed cleanup, app removal and leftover removal on one active Mac. One payment; no recurring charge.”
4. Decide and disclose whether tax is included. Dodo supports tax-inclusive prices and localized prices; preview the buyer's total before publishing a price.
5. Save the product. Keep its product ID; this is a public identifier, not an API key.

These fields are documented in [One-Time Products](https://docs.dodopayments.com/features/one-time-payment-products) and [Products](https://docs.dodopayments.com/features/products). Pricing is configured in Dodo, not in the app's source code. An optional starting offer is ₹499 in India or US$9.99 globally, one time; no price has been configured or approved by this guide. Review taxes, fees and support costs before fixing prices. Define major-version upgrade rights before promising “all future updates forever.”

## 3. Attach automatic license delivery

Open **Entitlements → + → License Keys**. Name it **Aster Pro — 1 Mac** and set:

| Dashboard field | Value |
| --- | --- |
| Fulfillment Mode | Automatic |
| Activations Limit | 1 |
| License Length | No expiration |
| Activation Message | “Open Aster's Pro/license screen, paste this key and activate. To move to another Mac, deactivate on the current Mac first.” |

Save it. Open the product's **Entitlements** section and attach this entitlement. A successful one-time purchase generates one key per purchased unit and emails it; a successful one-time refund disables the key. [License Keys](https://docs.dodopayments.com/features/license-keys)

Keep the free downloadable app available from the website. Recommended buyer flow: download free → real scan → Buy Pro → pay → receive key by email → activate the same installed app. A download link can also appear after payment. A Digital Files entitlement is optional; it is not necessary for Aster's license flow.

For the onboarding questions, select **Payment links** and **API/SDK/Adapters**: checkout uses a hosted link, and the app uses public licensing APIs. Select **No human involvement** for product delivery because successful purchases generate and email the license automatically; ordinary customer support is separate from per-order fulfillment.

## 4. Copy the public configuration

The app needs only three public values in `Resources/DodoConfiguration.json`:

```json
{
  "environment": "test",
  "businessID": "",
  "productID": ""
}
```

Replace the empty IDs with your own values. Leave `environment` as `test` while testing. Do not paste a license key, customer email, API secret, payment credential or webhook secret into this file. Empty IDs intentionally leave purchases and paid activation unconfigured.

**Product ID:** copy the ID of your saved Aster product. You can also cross-check it against the product's hosted payment link: it is the segment after `/buy/`.

**Business ID:** a documented dashboard route is **Sales → Customers → your test customer → Share Invite → Static Link**. Complete one test purchase first to create that customer. The static portal URL ends with `/login/{business_id}`; use that final segment. Copy the **Static Link**, not the Dynamic Link, which signs a particular customer in. [Customer Portal](https://docs.dodopayments.com/features/customer-portal)

Aster derives the checkout link from the mode and product ID:

```text
Test: https://test.checkout.dodopayments.com/buy/{productID}?quantity=1
Live: https://checkout.dodopayments.com/buy/{productID}?quantity=1
```

The website's buy button can use that same hosted link. It does not need to create a checkout session on a server. Test products belong on the test host. The app never treats a successful browser redirect or a query parameter as proof of ownership. [Dodo's official static-link reference](https://github.com/dodopayments/skills/blob/main/dodo-payments/checkout-integration/SKILL.md#static-payment-links)

After editing the configuration, rebuild from the Aster folder:

```sh
bash scripts/build-app.sh
```

The script embeds the configuration in the app bundle. Changing the source JSON requires a new build; do not modify a signed distribution bundle afterward.

## 5. Activation, offline access and transfers

The buyer pays, receives the email, opens Aster and pastes the key. Activation uses the public `POST /licenses/activate` endpoint. Its response includes `business_id`, `product.product_id` and an activation instance ID. Aster must match both configured IDs before granting Pro and retain that verified provenance with the instance. A bare `valid: true` from an arbitrary key is insufficient. [Activate License](https://docs.dodopayments.com/api-reference/licenses/activate-license)

Aster keeps the key and activation record in macOS Keychain. It validates the key **and its instance** on launch, when returning to the foreground and periodically while open. Files, file paths, scan contents and cache contents stay on the Mac; the license service receives license/activation information. Payment and buyer information are handled in Dodo's hosted checkout.

**Aster's offline policy:** after a successful online check, Pro can continue for up to **7 days from that check** during a connection failure. This is our grace policy, not a Dodo trial. An explicit invalid/revoked response ends Pro immediately; a network outage does not create a fresh seven-day period. When grace expires, Free scans and previews remain available until a valid online check succeeds. Refund/revocation detection can therefore be delayed while a device is offline.

One active Mac means one activation slot. Use **Deactivate** before transferring. The public deactivation call sends the key and `license_key_instance_id`; success frees the slot. Reinstalling with the same usable Keychain record can reuse that instance. If the record is lost, or the old Mac is inaccessible, the owner must resolve the old activation through Dodo's license management/support before the replacement can activate. Do not promise unlimited reinstall recovery. [Validate License](https://docs.dodopayments.com/api-reference/licenses/validate-license) · [Deactivate License](https://docs.dodopayments.com/api-reference/licenses/deactivate-license)

## 6. End-to-end test checklist

Use an email you control: test mode can send real emails. Under **Settings → Communication → Email**, leave **Test Mode Emails** on. Test subjects start with `[TEST MODE]`, and Dodo limits test email volume. [Test email settings](https://docs.dodopayments.com/features/communication-preferences#test-mode-emails)

1. Open your test hosted link. Use Dodo's published test card, for example US Visa `4242 4242 4242 4242`, expiry `06/32`, CVV `123`, with the corresponding test billing country. No real card or charge is needed. [Official testing guide](https://docs.dodopayments.com/miscellaneous/testing-process)
2. Check the product, one-time amount, taxes, successful order and emailed license. If email is absent, check the entitlement, test email switch and delivery log before calling the flow complete.
3. With your test IDs embedded, activate the emailed key in Aster. Relaunch and confirm the activation survives.
4. Confirm an incorrect key fails, and a valid key from another product/business cannot unlock this app. Use only test keys you own.
5. Try the same key on a second test Mac: it must hit the one-activation limit. Deactivate on the first, then activate on the second. An offline deactivation must not claim that the server slot was freed.
6. With a valid activation, queue a disposable test file. Inspect the preview and confirmation. Test Trash only on that disposable file; do not use personal files for billing verification.
7. Simulate a refund of the test payment in Dodo. Refresh Aster's license and verify that Pro becomes unavailable while Free remains usable. Also exercise a manually revoked key.
8. Test the offline grace boundary with controlled test clocks/fixtures. Confirm repeated failed requests do not extend it. Never change the user's system clock to run this check.
9. Return to an unactivated installation and confirm every route that actually moves files to Trash requires Pro, including app removal and leftovers. Confirm full-path displays, Copy Path and Show/Reveal in Finder are also locked. Free previews still show real filenames, sizes and inventory without exposing the full paths.

## 7. Go live deliberately

Once verification is approved, create or copy the one-time product and automatic entitlement into **Live Mode**. Check the live product's one-Mac/no-expiration settings, final price and emails. Set `environment` to `live`, copy the correct live public IDs into the JSON and rebuild. Test keys and products do not become live purchases automatically.

Finish Developer ID signing, hardened runtime, notarization and release checks before publishing the downloadable Mac app. The current default build script produces a local ad-hoc build unless a signing identity is supplied. An Apple Developer account alone does not notarize it.

Record a controlled, owner-approved live purchase/refund and activation result before announcing paid availability. Until those checks happen, describe the status as **implemented and locally tested; live checkout/activation awaiting merchant configuration and verification**. No merchant account, product, price or real charge is created by building this repository.
