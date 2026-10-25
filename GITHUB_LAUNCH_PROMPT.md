# BalDente → GitHub launch prompt (paste into a fresh session in this folder)

```text
Get BalDente ready to publish as an open-source project on GitHub under the account
`closedesign` (repo: closedesign/BalDente), and make the repo attractive enough that people
want to install it and donate. Work inline, no subagents. Read CLAUDE.md and PLAN.md first,
and read source only where you need facts.

## 1. Repo setup
- This folder is not a git repo yet. Run `git init`, add a `.gitignore` (.build/, dist/,
  .DS_Store, *.xcuserstate), and make one clean initial commit on `main`.
- Add a LICENSE. Recommend MIT, and ask me before choosing. Do not copy code from
  actuallymentor/battery, charlie0129/batt, or mhaeuser/Battery-Toolkit (GPL, see CLAUDE.md).
- Do NOT create the GitHub repo, push, or publish anything until I approve the final README
  and the list of files to be pushed. Use `gh` for that step once I say go.

## 2. Branding (already created, reuse it, do not redesign)
- The app's real icon is Resources/AppIcon-1024.png (copied to docs/images/icon.png). Use it at
  the top of the README (centered, ~128px) and keep its palette (navy, pink→purple→cyan) for
  badges and any extra graphics.
- Social card: docs/images/social-preview.png (1280x640, built from the app icon). I upload it
  under repo Settings → Social preview.
- Profile picture for the closedesign account/org: docs/images/profile-closedesign.svg/.png
  (flat closed hexagon, a deliberate "closed" counterpart to open-source AI lab marks; it
  does not copy any existing logo). I upload it in the account settings.
- Do not change make_app.sh or the app icon.

## 3. Screenshots (docs/images/)
- Build with ./make_app.sh, then take clean, scaled screenshots of the real app: Overview,
  Charging (limit slider), Zones, History chart, Appearance, and the menu bar item and panel.
  Use the throwaway-bundle method from CLAUDE.md for the debug build. Light and dark variants
  where it helps.
- Fake or generic data only: no real Wi-Fi names, addresses or calendar events. Check each image.
- Make one hero image (main window + menu bar) for the top of the README.

## 4. Demo video
- Write docs/promo/demo-script.md, a 45-60 second shot list: each screen, what the cursor
  clicks, and a one-line caption per beat. Fake data only.
- Write docs/promo/make-demo.md: macOS recording setup (⌘⇧5 → Options → Show Mouse Clicks),
  ffmpeg commands to compress to under 10 MB and to make a ~800px hero GIF, and how to drag the
  .mp4 into the README editor on github.com so GitHub hosts it. Embed the GIF near the top of
  the README, linking to the full video. (I record the video myself; you only prep the script.)

## 5. README.md (the main sales page)
1. Centered logo, title, one-line pitch: "BalDente: the free, open-source battery charge
   limiter for macOS." Badges: macOS version, license, latest release, downloads.
2. Hero screenshot/GIF, then a prominent "Download latest release" button.
3. "Why BalDente?" Say plainly it is a free alternative to paid battery-limiting apps such as
   AlDente Pro and BattOpt; use the phrase "free alternative to AlDente" for search. Say only
   "alternative to" and "inspired by". No logos of theirs, no implied affiliation, no
   unverifiable claims. Describe the real gap: features that cost money elsewhere (Wi-Fi /
   location zones, Ready-by-calendar, history, etc.) are free here.
4. Features: scannable list with a screenshot each. Take the list from the actual code, not
   guesses: charge limit, zones, Calendar "Ready by", History charts, menu bar status item,
   CLI, settings search, compact layout.
5. Comparison table vs. paid apps: only rows I can verify; mark unsure ones "check their site".
6. Install: download .dmg, drag to Applications, approve the helper in System Settings
   (SMAppService). Be honest that the app is ad-hoc signed and not notarized, so first launch
   needs right-click → Open (or Privacy & Security → Open Anyway). Homebrew cask section only
   if we really publish one.
7. How it works & safety: honest explanation of the root helper (baldented), what it can and
   can't do, which permissions are used and why (Location for Wi-Fi zones, Calendar for Ready
   by), and how to uninstall the helper completely.
8. CLI usage examples.
9. Build from source (swift build, ./make_app.sh, ./install.sh).
10. Compatibility: only list what is tested; "community reports welcome" for the rest.
11. Support the project: friendly, non-pushy ("BalDente is free and will stay free. If it saves
    your battery, consider chipping in.") with Ko-fi and GitHub Sponsors buttons. Use
    placeholder usernames and list exactly what I must fill in.
12. Contributing, roadmap (from PLAN.md), credits.

## 6. Other GitHub files
- .github/FUNDING.yml (github: [closedesign], ko_fi: PLACEHOLDER), issue templates (bug report
  asking for Mac model, macOS version, `smcprobe` output; feature request), PR template.
- CONTRIBUTING.md and SECURITY.md (private vulnerability reporting, since the helper runs as root).
- CHANGELOG.md and a v1.0.0 release draft with notes, attaching dist/BalDente.dmg. Don't upload
  until I approve.
- Wiki pages as markdown in docs/wiki/ to push to the repo wiki: Home, Installation, Features,
  Zones guide, Calendar Ready-by, CLI reference, Troubleshooting (incl. SMC backend
  differences), FAQ, Uninstall, Roadmap.

## 7. Promotion kit (docs/promo/, write only, post nothing)
- Repo "About" description and topics (macos, battery, battery-health, menubar, swift, swiftui,
  aldente-alternative, smc, open-source).
- Draft posts: Reddit (r/macapps, r/MacOS, r/opensource), Show HN, Product Hunt tagline +
  description, short tweet/thread. Honest, humble, focused on the problem solved.

## Rules
- No claims about battery-health benefits beyond what is generally accepted. No invented
  features, stats or testimonials.
- Friendly, plain, not hypey.
- When done, give me a checklist of what I must do by hand: create the repo under closedesign,
  record the video, fill in donation usernames, upload the social preview, enable Wiki and
  Sponsors, and optionally Apple Developer notarization.
```
