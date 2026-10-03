# Rolvexa

<img src="screenshots/splash-screen.png" alt="Rolvexa splash screen" width="180" />

**Your AI copilot for landing the job.** Rolvexa is an iOS app that reviews, builds, and tailors resumes and cover letters — entirely on-device, with no cloud AI and no network access at any point.

## What it does

Rolvexa supports two ways to start:

- **Upload an existing resume** (PDF, Word, or a photo/screenshot) — get an instant score, a breakdown (ATS compatibility, content & impact, grammar & clarity, formatting), and concrete suggestions for improving it. Photos are read with on-device OCR, so a picture of a printed resume becomes fully editable, fixable, and exportable as a real PDF or Word document.
- **Write a resume from scratch** — fill in your contact info, education, and professional experience, and Rolvexa assembles a structured resume from it.

From there, Rolvexa:

- Picks a professional template (Modern Edge, Minimal Pro, Creative Bold, Executive Suite) — or keeps your uploaded file's original layout untouched if you'd rather not restyle it.
- Scores your resume and flags issues: spelling, weak passive phrasing ("responsible for" → "Led"), repeated words, missing sections, missing quantifiable metrics, and more.
- **"Fix It For Me"** — applies safe, deterministic fixes automatically, and on Apple Intelligence devices also rewrites bullet points and paragraphs for punchier phrasing (never inventing facts, numbers, or achievements that aren't already there).
- Suggests other job titles you're a good fit for, based on your skills.
- Generates a tailored cover letter and a job-fit analysis alongside your resume.
- Exports everything as PDF or Word, ready to send.

## How it works, technically

Everything runs locally on the device — no cloud AI, no API keys, no network calls:

- **Text extraction** from uploaded files: `PDFKit` for text-based PDFs, a minimal in-house zip reader for DOCX, and `Vision` OCR for photos, screenshots, and scanned image-only PDFs. Photos are normalized upright first (a camera photo stores its rotation in an EXIF tag, and Vision reports text positions in the *stored* pixel space — without normalizing, a sideways photo's sections come out in reverse order).
- **Scoring and suggestions** via `NaturalLanguage` tokenization, the system spell checker (`UITextChecker`), and deterministic heuristics.
- **"Fix It For Me"** layers Apple Intelligence's on-device system model — via the [Foundation Models](https://developer.apple.com/documentation/foundationmodels) framework, using `@Generable` guided generation so the response is a guaranteed-shape Swift type rather than parsed free text — on top of the deterministic fixes.
- Built with **SwiftUI**. No third-party package dependencies.

### Graceful degradation

Apple Intelligence requires capable hardware (A17 Pro or newer). The app checks `SystemLanguageModel.availability` and tiers accordingly:

| Tier | Devices | Capability |
|---|---|---|
| Apple Intelligence | iPhone 15 Pro and newer | Full phrasing rewrites + all of the below |
| Deterministic engine | **All supported devices** | Spelling, weak-verb fixes, scoring, structure analysis |

Spelling and grammar deliberately stay on the deterministic path even where the model is available — a rules engine can't "autocorrect" someone's surname into a different word, which is exactly the kind of silent corruption a resume can't tolerate.

## Setup

Open `Rolvexa.xcodeproj` in Xcode and build. Nothing else to configure — no model weights to download, no dependencies to resolve.

Minimum deployment target is iOS 18. The Foundation Models code path is gated behind `if #available(iOS 26, *)` and an availability check, so it compiles and runs fine on older systems — it just falls back to the deterministic engine there.
