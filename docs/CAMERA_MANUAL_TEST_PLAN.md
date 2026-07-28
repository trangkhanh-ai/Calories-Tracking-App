# Camera Manual Verification Plan

Status: **Manual pending**. This document defines checks to run; it does not claim that any test has been executed.

## Test Matrix

Run the full checklist on each target and record the device, OS, browser/app version, result, and evidence.

| Target | Status | Notes |
| --- | --- | --- |
| Chrome on Android mobile web | Manual pending | Test in a normal browser tab. |
| Samsung Internet on Android | Manual pending | Test in a normal browser tab. |
| Safari on iOS | Manual pending | Test in a normal browser tab. |
| Installed PWA | Manual pending | A PWA uses browser web camera APIs and permissions; it is not equivalent to the Android APK. |
| Android APK | Manual pending | Include native permission and system Settings cases. |

## Checklist

Repeat these checks for every applicable target in the matrix.

- [ ] Open the camera flow and allow permission. Confirm the preview loads and capture controls are usable.
- [ ] Deny camera permission. Confirm the app shows a clear recovery message and does not hang or crash.
- [ ] Android APK only: deny permission permanently (for example, select **Don't ask again** where available). Confirm the app explains how to restore access and opens or directs the user to system Settings; restore permission and retry.
- [ ] While another app or browser context is using the camera, open the camera flow. Confirm the "camera in use" failure is handled clearly and retry works after the camera is released.
- [ ] Switch between front and rear cameras at least **five consecutive times**. Confirm each switch selects the requested camera, keeps a live preview, and does not freeze, crash, or leave duplicate camera sessions.
- [ ] Start with the rear camera. If normal rear-camera startup fails, confirm the rear-camera fallback opens a one-shot capture flow and the UI remains responsive afterward.
- [ ] When live camera capture is unavailable, confirm the gallery/file fallback is offered and a supported image can be selected.
- [ ] Capture a food image and submit it to Gemini analysis. Confirm loading, success, and error states are understandable and no duplicate submission occurs.
- [ ] Return from the Gemini result to the camera flow, then capture and analyze another image. Confirm the preview restarts and the second capture succeeds without reloading the app.
- [ ] Background and reopen the browser, PWA, or APK during the camera flow. Confirm the camera resumes or offers a clear retry path without retaining a stale session.

## Result Record

For each target, record:

- Device and OS version
- Browser/app version and install mode
- Permission state tested: allowed, denied, and permanently denied where applicable
- Front/rear switch count and outcome
- Camera-in-use, rear fallback, and gallery outcome
- Gemini analysis and return-to-camera outcome
- Result: Pass / Fail / Blocked / Not applicable
- Screenshot, screen recording, logs, and issue link for failures
