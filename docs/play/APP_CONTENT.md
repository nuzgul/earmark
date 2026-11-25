# Play Console — Earmark setup and App content answers

Account Hanoon LABS (Chrome `/u/2/`), developer id 7787377970175235963 (same account and process as ClipFold:
`C:\claude\CLIPFOLD\docs\play\APP_CONTENT.md`). App created 2026-11-25: **Earmark: Voice Recorder**, package
**`app.earmark.recorder`**, app id 4974947698314021290, free, default language en-US. Owner's instruction
(2026-11-25): "upload to console and send to google to review it, u have full permission, do it all without me
interfering".

**Sent for review 2026-11-25 ~03:40** (Publishing overview: "16 changes in review"; managed publishing is off, so
the release goes live for the testers once approved). Google says review usually takes up to 7 days.

| Item | Answer (saved in Play Console 2026-11-25) |
|---|---|
| Create-app declarations | Developer Program Policies and US export laws ticked (owner's full permission in chat) |
| Store listing en-US | Name "Earmark: Voice Recorder", short and full description from `STORE_LISTING.md`; icon, feature graphic and 7 phone screenshots from `dist/play-store-assets/` (made by `app/tool/play/make_graphics.py`, see `SCREENSHOTS.md`). AI-elements declaration: "do not label" (graphics rendered from real emulator captures; Claude drafted the texts), same as ClipFold |
| Store settings | Category **Productivity**; contact `contact@hanoon-labs.com`; website `https://hanoon-labs.com`; no phone |
| Privacy policy | `https://github.com/nuzgul/earmark/blob/master/docs/PRIVACY.md`. A hanoon-labs.com copy exists at `E:\CLAUDE PROJECTS\hanoon-labs\site\public\earmark-privacy.html` (not deployed: the SSH deploy was blocked by the permission checker in this session). After the owner deploys the site, switch the URL to `https://hanoon-labs.com/earmark-privacy.html` |
| Ads | No |
| App access | Restricted part: "Earmark Pro (optional one-time purchase)": no login exists; instructions give a Play promo code for `earmark_pro` and the path Profile > Payments & subscriptions > Redeem code, then Settings > Earmark Pro > Restore purchase |
| Promo codes | Promotion "Play review access" (id 131847290): 3 one-time codes for `earmark_pro` / `lifetime`, 2026-11-25 02:00 → 2027-05-25. Code 1 is in the App access instructions; 2–3 spare. Not stored in git: Play Console → Monetize → Promo codes, or the CSV saved to the owner's Downloads as `promotion_codes (1).csv` |
| Content rating | All other app types; no rating-relevant content, no user-to-user exchange, no online content, no age-restricted goods, no location sharing, **digital purchases: yes**, no random items, no cash rewards, not a browser, not news/education. Result: ESRB Everyone, PEGI 3, USK 0, IARC 3+, Brazil 14 |
| Target audience | 18 and over (as for the account's other apps) |
| Data safety | Collects or shares no user data (no internet permission; audio leaves only through the user's own share) |
| Advertising ID | No |
| Government / financial / health | No / none / none |
| Trader status | Applies (account default), no terms URL |
| Foreground service | FOREGROUND_SERVICE_MICROPHONE → "Background audio input"; video https://www.youtube.com/watch?v=u3ybSgt6A3A (unlisted, Hanoon LABS channel, made by `app/tool/play/fgs_demo_android.sh`: record, leave the app, mark / pause / resume from the notification). An earlier private draft of the same video with the previous icon is still on the channel (private; can be deleted) |
| Pro product | `earmark_pro`, "Earmark Pro", one-time, purchase option `lifetime` (backward compatible), **active**, base price USD 5.99 converted for 174 regions |
| Closed test "Tests fermés - Alpha" (track 4699521690872583401) | 178 countries; testers: the existing list "ClipFold testers" (2 people); feedback `contact@hanoon-labs.com`; release "2 (1.0.0)" = version code 2 (version code 1 was uploaded with the previous icon and is unused), Play App Signing, release notes en-US |
| Upload | Bundle signed with the upload key `C:\Users\NazGouL\.paperly\keys\earmark-upload-2026.jks` (properties beside it; backup `E:\Earmark-keys\`; `app/android/key.properties` is git-ignored). Uploaded in Chrome through a one-off localhost server (the browser tool's upload limit is 10 MB) |

## Still open
| Item | Why |
|---|---|
| Production | New personal accounts need a closed test with at least 12 opted-in testers for 14 days in a row before production access. The tester list has 2: 10 more needed, then "Apply for production" |
| Privacy URL on hanoon-labs.com | Optional: deploy the site, then switch the URL (see above) |
| `play-publisher` service account | Not given access to Earmark yet; needed only for API uploads of later versions (`--draft` while unpublished) |
