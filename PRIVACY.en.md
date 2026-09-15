# FreeCAD for HarmonyOS Privacy Policy

**Effective date**: September 15, 2026 · **Version**: 1.0
**Applies to**: FreeCAD (HarmonyOS PC / 2in1, bundle name `com.liangxiaohui.freecad`)

This app is a fully **local** 3D parametric CAD application. It has **no account system and does not collect, upload or share your personal information**.

---

## 1. Developer and contact

- **Developer**: liangxiaohui (individual developer)
- **Contact**: project repository issues at <https://github.com/liang-xiaohui/freecad-on-harmonyos/issues>, or the developer details published on this app's AppGallery page.

---

## 2. Summary

No server, no account, no ads, no analytics. Your models, settings and API keys stay on your own device. Other than the two opt-in online features (Add-on Manager and the AI assistant), the app makes no network requests.

---

## 3. Information we do not collect

| Category | Collected | Notes |
| --- | --- | --- |
| Account or identity data (name, phone, email, ID) | **No** | The app has no sign-up or sign-in |
| Device identifiers (IMEI, OAID, ODID, MAC, …) | **No** | No identifier-collection code is included |
| Location | **No** | No location permission is requested |
| Contacts, SMS, call logs, photo library | **No** | No such permission is requested |
| Installed-app list | **No** | No such permission is requested |
| Clipboard contents | **No** | Read only once, when you press Ctrl+V inside the app; no background polling and no history |
| Your CAD files and project data | **Never uploaded** | Stored only in the app's private sandbox directory |
| Usage statistics, crash reports, diagnostics | **Never uploaded** | The package bundles no analytics, ads or crash-reporting SDK |

---

## 4. Permissions and why they are needed

The app requests **two** permissions, each tied to one feature:

| Permission | Granted how | Purpose | When it is used |
| --- | --- | --- | --- |
| `ohos.permission.INTERNET` | `system_grant` (automatic, no prompt) | (a) Add-on Manager fetches add-on and macro catalogs; (b) the FreeCAD AI workbench calls the third-party LLM endpoint **you configured yourself** | Only when you actively use those features |
| `ohos.permission.READ_PASTEBOARD` | `system_basic` + `user_grant`; applied for in AppGallery Connect and declared in the signing profile | Paste text you copied in another app (e.g. an API key) into an input field | Only when you press Ctrl+V |

You can revoke either permission at any time in **Settings > Privacy & Security > Permission manager**. The related feature stops working; everything else is unaffected.

**Third-party SDK list**: none. Apart from the open-source libraries shipped with the package (Qt 6, Open CASCADE Technology, Coin3D, Python 3.11, OpenSSL and others), the app embeds no analytics, advertising, push or social SDK. Those libraries provide UI, geometry, rendering and scripting only and perform no data collection.

---

## 5. When the app goes online, and which third parties are involved

| Scenario | Network request | Relation to your data |
| --- | --- | --- |
| Add-on Manager | Fetches add-on/macro catalogs and files from GitHub and the FreeCAD wiki (`raw.githubusercontent.com`, `github.com`, `wiki.freecad.org`) | A **download**; it carries no model or personal data. The remote host may log your IP address and request time |
| FreeCAD AI workbench (third-party open-source add-on) | After **you** enter an endpoint and API key in its settings, your conversation and the necessary model context are sent **directly from your device** to that provider | The request never passes through the developer; you decide what is sent |
| Opening the online manual or external links | Opens the URL you clicked | Handled under that website's own privacy policy |

The AI workbench ships optional endpoints for common providers (OpenAI, Anthropic, DeepSeek, Moonshot/Kimi, Qwen/DashScope, Google Gemini, xAI, Groq, OpenRouter, and any OpenAI-compatible or local endpoint). Those services are operated independently and handle data under their own privacy policies. The developer has **no access to, and keeps no copy of**, anything you send to them.

The app contains no content push, advertising, profiling or data monetization of any kind.

---

## 6. Where data is stored, and for how long

- All data the app produces (documents, settings, thumbnails, cache, logs) lives in the app's private sandbox directory, e.g. `/data/storage/el2/base/haps/entry/files/freecad-home/`, unreadable by other apps.
- **API keys are stored in plain text** in `config.json` inside that private directory, readable only on your device. Do not store someone else's key on a shared device; clear it in the add-on settings or delete the file to remove it.
- **Retention is up to you**: deleting a file deletes the data, and **uninstalling the app removes everything** in its private directory. No cloud copy exists. Back up important documents yourself.
- The developer **cannot access** any data on your device and keeps no copy.

---

## 7. Sharing, transfer and disclosure

Because the app collects no personal information, there is nothing to share, transfer or disclose. We would only respond to a lawful, compulsory request from a competent authority — and under this app's data design there is no personal information we could provide.

---

## 8. Your rights

- **Access, correct, delete**: edit or delete your files and settings inside the app; clearing app data or uninstalling removes everything.
- **Withdraw consent**: revoke the network or pasteboard permission in system settings; stop using the Add-on Manager and AI features and no further network requests occur.
- Since the developer holds no personal data, we cannot query or delete data on your behalf. Use the contact in section 1 for any question.

---

## 9. Minors

This is a general-purpose 3D design tool, **not directed at children**, and it collects no one's personal information. If a minor uses it under a guardian's guidance, note that the AI assistant requires a third-party API key (which may incur provider fees and involve content exchange); a guardian should configure and supervise it.

---

## 10. Data security

- Local data relies on HarmonyOS sandbox isolation and is removed on uninstall.
- Permissions follow least privilege: two, both revocable in system settings.
- Communication with third parties happens directly on your device; whether it is encrypted depends on the endpoint you configure.
- As neither the app nor the developer stores your data, there is no server-side store to breach.

---

## 11. Changes to this policy

Material changes will come with an updated version number and effective date, published in the release notes of the new app version and in this repository. Significant changes to permissions or data handling will be highlighted. Continued use of the app means you accept the updated policy.

---

## 12. Relation to the upstream FreeCAD project

This app is a port of the open-source [FreeCAD](https://www.freecad.org/) 1.1.2, distributed under the GNU Lesser General Public License v2.1 (LGPL-2.1). It is an **unofficial community port** and is not affiliated with, sponsored by or endorsed by the FreeCAD project or its trademark holder. The upstream privacy policy, which likewise states that no personal data is collected, is at [FreeCAD/FreeCAD/PRIVACY_POLICY.md](https://github.com/FreeCAD/FreeCAD/blob/main/PRIVACY_POLICY.md).

---

## Version history

| Version | Date | Notes |
| --- | --- | --- |
| 1.0 | 2026-09-15 | First release, shipped with the first AppGallery submission (based on FreeCAD 1.1.2) |

---

*简体中文版：[PRIVACY.md](PRIVACY.md)*
