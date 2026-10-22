# Orvyqmedia Employee Device Usage & Privacy Agreement

**Purpose:** Verification of business outbound calls conducted via personal SIM devices.  
**Applicability:** All calling agents and sales representatives utilizing personal Android devices for Orvyqmedia lead outreach.

---

## 1. Background & Purpose

Orvyqmedia utilizes a native Android application ("Orvyqmedia Caller") to verify outbound business cold calls made by employees from their personal SIM cards. This eliminates the need for expensive third-party bridge telephony providers while ensuring verified work productivity.

---

## 2. Guaranteed Privacy Safeguards & Data Lifecycle

Orvyqmedia explicitly warrants and agrees to the following technical and operational privacy protections:

1. **On-Device Memory Filtering:**
   - To match an outbound work call to an assigned lead, Android architecture requires the application to query recent outgoing call log entries within the active dial window into volatile device memory.
   - The application checks each entry's dialed number against the assigned lead's E.164 phone number.
   - Any unrelated or personal call records queried into memory are immediately discarded on-device. They are **NEVER saved to persistent device storage, NEVER logged to disk, and NEVER transmitted or uploaded to Orvyqmedia servers**.
2. **Absolute Non-Retention of Personal Data:**
   - Personal incoming calls, personal outgoing calls, contacts, SMS messages, WhatsApp communications, photos, and browser history are strictly non-retained. The application requests only the minimum necessary telephony permissions for outgoing verification.
3. **No Audio Recording:**
   - The application contains zero voice recording code and does not record, intercept, or store any call audio.
4. **Data Verification Scope (What is Uploaded):**
   - Only work calls placed to assigned leads are recorded upon post-call dialog submission:
     1. Outgoing phone number (matching assigned lead).
     2. Call initiation timestamp.
     3. Duration of the call in seconds (evaluated against the ≥10-second connected threshold).
     4. SIM slot identifier (if reported by the Android OS).
     5. Verification evidence source (`device_log` vs `manual`).

---

## 3. Data Retention & Departure Protocol

1. **Retention Period:**
   - Device-specific call logs are retained for performance audit purposes for a maximum of 90 days, after which they are archived or scrubbed.
2. **Employee Departure:**
   - Upon conclusion of employment or contract with Orvyqmedia:
     - The employee's account and device binding are immediately deactivated in Supabase.
     - The employee may uninstall the application, which immediately purges all local cache and tokens.
     - Device identifiers associated with the employee are permanently disassociated.

---

## 4. Employee Acknowledgement & Signature

By signing below, I acknowledge that:
1. I have read and understood the terms of this Device Usage & Privacy Agreement.
2. I consent to the installation of the Orvyqmedia Caller application on my Android device.
3. I understand that only work calls placed to assigned leads will be verified, and my personal calls remain completely private.

---

**Employee Name:** _____________________________________________  

**Mobile SIM Number:** _________________________________________  

**Signature:** _________________________________________________  

**Date:** _____________________________________________________  

---

**Approved on behalf of Orvyqmedia:**  

**Manager Name:** _____________________________________________  

**Signature:** _________________________________________________  

**Date:** _____________________________________________________  
