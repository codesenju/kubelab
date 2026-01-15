# TikTok Multi-User Content Publishing Platform – Requirements & Build Prompt

## 1. Purpose & Goal
Build a **TikTok-approved, multi-user content publishing platform** that allows **independent creators, businesses, and agencies** to authenticate their own TikTok accounts and schedule, upload, and publish content using TikTok’s official APIs. The platform must comply fully with **TikTok for Developers App Review Guidelines** and explicitly **avoid personal or internal-only usage**.

The product is positioned as a **creator-facing SaaS**, not a private automation tool.

---

## 2. Target Users
### Primary Users
- Independent TikTok creators  
- Small and medium businesses  
- Coaches, educators, influencers  
- Agencies managing multiple client accounts (with explicit client consent)

### Explicitly Excluded
- Personal posting bots  
- Internal-only company tools  
- Single-account automation utilities  

---

## 3. Core Compliance Principles (CRITICAL)
- Multi-user by design  
- TikTok Login Kit (OAuth) required  
- Posting only to authenticated user-owned accounts  
- No hardcoded or owner-managed accounts  
- Full transparency and user consent  

---

## 4. Functional Requirements

### 4.1 Authentication
- Email/password or SSO login
- TikTok Login Kit required for posting
- Token refresh and revocation supported

### 4.2 TikTok Connection
- “Connect TikTok” button
- OAuth consent screen shown
- Minimal scopes requested

### 4.3 Content Management
- Upload video files (mp4/mov)
- Add captions and hashtags
- Draft, scheduled, published states

### 4.4 Scheduling & Publishing
- Immediate or scheduled posting
- Draft-first upload preferred
- Direct posting optional and user-enabled only

### 4.5 API Usage
**Required Products**
- Login Kit
- Content Posting API

**Minimum Scopes**
- user.info.basic
- video.upload

---

## 5. UI Requirements
- Landing page
- User dashboard
- TikTok connection screen
- Upload & scheduler UI
- Posting status & history

---

## 6. Security & Privacy
- Encrypted token storage
- HTTPS only
- Public Privacy Policy & Terms of Service

---

## 7. Demo Video Requirements (For Review)
- User login
- TikTok OAuth flow
- Content upload
- Scheduling or publishing
- Post appearing on the user’s TikTok account

---

## 8. Disallowed Behavior
- Internal automation
- Posting to developer-owned accounts
- Background-only bots
- Missing user interaction

---

## 9. App Description (Suggested)
A web-based platform that enables creators and businesses to authenticate their own TikTok accounts and schedule or publish original content. Users maintain full control and ownership of their accounts through TikTok Login Kit authorization.

---

## 10. System / AI Build Prompt
You are building a TikTok-compliant, multi-user SaaS platform for creators.

Constraints:
- Multi-tenant
- OAuth required
- User-owned posting only
- No internal-only usage
- All actions user-initiated

Design the system to pass TikTok App Review without policy violations.
