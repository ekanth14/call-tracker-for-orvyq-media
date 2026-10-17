# Orvyqmedia Android Pilot Runbook (Phase 5)

**Objective:** Validate Android-first device-log verification with 2 active callers for 1 week before company-wide rollout.

---

## 1. Pilot Setup

- **Callers:** 2 callers (e.g. `ekanthbs45@gmail.com` + 1 additional agent).
- **Target Phones:** Primary personal Android devices (ideally different brands like Samsung, Xiaomi/Redmi, or OnePlus to test background sync variances).
- **Duration:** 5 business days (Mon–Fri).
- **Daily Volume:** 25–40 dials per caller.
- **Threshold Rule:** Minimum 10 seconds connected talk time (§5.1).

---

## 2. Day 1: Installation & Smoke Testing

### Step 1: Account Provisioning
1. Owner opens Web Dashboard at **`http://localhost:3000/callers`**.
2. Confirms active caller accounts exist with assigned mobile SIM numbers.

### Step 2: App Installation
1. Provide `app-release.apk` to pilot callers.
2. Callers install APK and allow installation from unknown sources.
3. Callers open **Orvyqmedia Caller** and sign in.
4. Callers review and accept the **Privacy Notice** (§6).
5. Callers open **Health Check** (`/health`) and verify Phone and Battery Optimization permissions are enabled.

---

## 3. Mandatory Test Matrix (Day 1 Afternoon)

Each pilot caller must execute the following 5 controlled test scenarios:

| Test ID | Scenario | Expected Behavior | Verification Check |
|---|---|---|---|
| **TC-01** | Call answered, talk time **> 10s** (e.g. 35s) | App automatically pre-fills duration as 35s. Status is "Connected (≥10s)". "Interested" and "Not Interested" outcomes are active. | Lead moves to `interested` or `not_interested`. Log appears on `/calls` with `Clear` flag. |
| **TC-02** | Call answered, talk time **< 10s** (e.g. 4s) | App pre-fills duration as 4s. Status is "Not Connected (<10s)". "Interested" button is disabled. Caller can only select Unreachable/Declined. | Log appears on `/calls`. If caller attempts to bypass, `CLAIM_MISMATCH` or `SHORT_INTERESTED` flag triggers. |
| **TC-03** | Call unanswered / ringing (0s) | No answer detected. Caller submits dialog as "No Answer / Ringing". Duration is 0s. | Lead status moves to `called`. Next dial unlocked. |
| **TC-04** | **Call Lock Test** | Caller initiates a call. While on the calling screen or before submitting notes, attempts to open another lead. | **Queue is locked.** Alert banner appears: *"Call Lock Active: Notes Required"*. App refuses second call until dialog 1 is submitted. |
| **TC-05** | **Privacy Verification (§6)** | Caller dials a personal number (family, friend, bank). Then opens Orvyqmedia app. | **Zero personal data captured.** Personal call is never logged in app or uploaded to server. |

---

## 4. Daily Monitoring (Days 2–5)

1. **Owner Morning Review (`http://localhost:3000/calls`):**
   - Check total calls placed yesterday.
   - Filter by **Flagged Calls Only**. Inspect any `CLAIM_MISMATCH` or `CLOCK_SKEW` flags.
2. **Review Reasons Breakdown (`http://localhost:3000/reports`):**
   - Check top reasons why leads are not interested.
   - Discuss objections during daily team standup.
3. **Check Background Sync Health:**
   - In `/flags`, verify no persistent `LOG_GAP` flags appear (indicates OEM background killing).

---

## 5. End of Pilot Review & Tuning

At the end of Day 5:
- [ ] Calculate actual connection rate across both callers.
- [ ] Confirm whether 10s threshold accurately filters out voicemails and immediate hang-ups.
- [ ] Confirm no personal call logs were ever transmitted.
- [ ] Export pilot call logs via **Export CSV** button on `/calls`.
- [ ] Approve rollout to remaining Android callers (Phase 6).
