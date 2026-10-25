# Ko-fi and Buy Me a Coffee: setup (do these yourself, about 10 minutes)

Account creation, payout details and identity checks have to be done by you in your browser. The repo already links to
`ko-fi.com/closedesign` and `buymeacoffee.com/closedesign`, so **use exactly the handle `closedesign`** on both (if it is
taken, tell me and I'll change the links).

## Ko-fi (do this first; no platform fee on donations)
1. Go to ko-fi.com → *Sign up*. Choose the page name `closedesign`.
2. Settings → *Payments*: connect PayPal and/or Stripe (payout goes to the name on that account).
3. Upload `docs/images/profile-closedesign.png` as the avatar; for the cover use `docs/images/social-preview.png`.
4. Page text (paste into "About"):

   > BalDente is a free, open-source battery charge limiter for macOS, an alternative to paid apps like AlDente.
   > It will stay free. If it saved your battery, a coffee helps me keep fixing bugs and supporting more Macs.
   > Source: github.com/closedesign/BalDente

5. Donation button text: "Buy me a coffee". Suggested amounts: $3, $5, $10.

## Buy Me a Coffee
1. buymeacoffee.com → *Start my page*, username `closedesign`.
2. Connect Stripe or PayPal for payouts (it takes a few minutes and an identity check).
3. Same avatar, same About text as above.
4. Turn on a simple thank-you message: "Thank you! You just made BalDente better for everyone."

## GitHub Sponsors (optional, later)
Enable under your profile → Sponsors. It needs approval and bank details. When approved, uncomment the `github:` line in
`.github/FUNDING.yml`.

## After the pages exist
- Open the README on GitHub and click both donate buttons to check they land on your pages.
- The repo's **Sponsor** button comes from `.github/FUNDING.yml` and appears once the repo is pushed.
