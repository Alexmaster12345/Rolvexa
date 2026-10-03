# Rolvexa

[![CI](https://github.com/Alexmaster12345/Rolvexa/actions/workflows/ci.yml/badge.svg)](https://github.com/Alexmaster12345/Rolvexa/actions/workflows/ci.yml)

**An offline resume parser, analyser and document generator for iOS.** Rolvexa reads a resume from a PDF, a Word file or a photo, scores it, compares it against a job posting, and regenerates it as a styled PDF or Word document — entirely on-device, with no cloud AI and no network access at any point.

<p align="center">
  <img src="screenshots/review-score.png" alt="Resume score with a four-axis breakdown and improvement suggestions" width="30%" />
  <img src="screenshots/job-fit.png" alt="Job fit match against a pasted posting, showing matched and missing skills" width="30%" />
  <img src="screenshots/resume-preview.png" alt="Live resume preview in the Modern Edge template" width="30%" />
</p>

<p align="center">
  <em>Scoring with an explainable breakdown · job fit against a real posting · live template preview</em>
</p>

The download isn't a re-flowed approximation of that preview. Both are built from the same structured model and emit the same sections in the same order — contact icons, the circular headshot, education and skills in the coloured column — and a test asserts the parity across all four templates in both formats:

<p align="center">
  <img src="screenshots/exported-pdf.png" alt="The generated PDF: circular headshot, contact block with icons, education and skills in the coloured sidebar, structured job entries in the main column" width="62%" />
</p>

### What's interesting under the hood

- **Reading-order reconstruction.** Recursive XY-cut page segmentation over Vision OCR output, so a two-column or sidebar resume extracts in the order a person reads it rather than the order the OCR engine emits. Choosing the split axis by recursion depth matters: the gutter *inside* a job entry is wider than the gap *between* two jobs, so "widest gap wins" cuts in the wrong place.
- **Documents written from primitives.** PDFs are drawn with CoreText/CoreGraphics; `.docx` files are hand-authored OOXML packed by a ZIP writer with its own CRC-32, down to an embedded JPEG cropped to a circle by a DrawingML shape preset. No document libraries.
- **Explainable scoring.** Job fit is set arithmetic you can argue with, not a generated number — every percentage traces back to a count of matched and missing terms, and a dimension the posting is silent about is dropped rather than guessed at.
- **Deterministic first, model second.** The on-device language model only ever rephrases, behind a check that rejects any rewrite altering a number. Spelling and grammar never touch it: a rules engine can't autocorrect someone's surname into a different word.

**132 tests · no third-party dependencies · no network calls · ~8k lines of Swift**

## What it does

Rolvexa supports two ways to start:

- **Upload an existing resume** (PDF, Word, or a photo/screenshot) — get an instant score, a breakdown (ATS compatibility, content & impact, grammar & clarity, formatting), and concrete suggestions for improving it. Photos are read with on-device OCR, so a picture of a printed resume becomes fully editable, fixable, and exportable as a real PDF or Word document.
- **Write a resume from scratch** — enter your contact details and profile links, the job you're targeting, each role you've held (title, employer, location, dates, achievement bullets), and your education. Write your own summary or let Rolvexa generate one. Add an optional headshot and it's rendered as a circular photo in the sidebar template.

From there, Rolvexa:

- Picks a professional template (Modern Edge, Minimal Pro, Creative Bold, Executive Suite) — or keeps your uploaded file's original layout untouched if you'd rather not restyle it.
- Scores your resume and flags issues: spelling, weak passive phrasing ("responsible for" → "Led"), repeated words, missing sections, missing quantifiable metrics, and more.
- **Job fit** — paste a job posting and Rolvexa compares it against your resume: which required skills you already cover, which are missing, and how you score on skills, recurring terms, seniority and education. Every figure is traceable to a count, so the number can be argued with. Without a posting it reports a *resume score* and says so, rather than implying a match it hasn't measured.
- **"Fix It For Me"** — applies safe, deterministic fixes automatically, and on Apple Intelligence devices also rewrites bullet points and paragraphs for punchier phrasing (never inventing facts, numbers, or achievements that aren't already there).
- Suggests other job titles you're a good fit for, based on your skills.
- Generates a tailored cover letter and a job-fit analysis alongside your resume.
- Exports everything as PDF or Word, ready to send — matching the on-screen preview section for section, including the contact icons, the photo, and a coloured sidebar that runs the full height of every page.

Work in progress survives closing the app, and builds up into a searchable library — one resume per role you're going after, each openable from **My Resumes**. Records are kept in Application Support rather than Documents, written with complete file protection so iOS keeps them encrypted while the device is locked, and excluded from iCloud and iTunes backups — a resume shouldn't leave the device through a backup when the app promises it won't leave at all. Deleting one removes its file.

Each record carries its last score stamped with a digest of the text that score was measured on. Edit a bullet and the number disappears from the list rather than lingering next to text it no longer describes.

Where a field is missing, Rolvexa leaves the section out rather than filling it with sample text. A resume that's visibly incomplete is recoverable; one that's confidently wrong about who you are is not.

## How it works, technically

Everything runs locally on the device — no cloud AI, no API keys, no network calls:

- **Text extraction** from uploaded files: `PDFKit` for text-based PDFs, a minimal in-house zip reader (with `Compression` for inflate) for DOCX, and `Vision` OCR for photos, screenshots, and scanned image-only PDFs. Photos are normalized upright first — a camera photo stores its rotation in an EXIF tag, and Vision reports text positions in the *stored* pixel space, so without normalizing, a sideways photo's sections come out in reverse order.
- **Reading order** is rebuilt by recursively bisecting the page along the widest text-free band, alternating axis by depth: a column split at the top level, then row splits within each column. A flat "widest gap wins" rule fails on real resumes, because the gutter between an employer and its bullet list is wider than the gap separating two jobs.
- **Scoring and suggestions** via `NaturalLanguage` tokenization, the system spell checker (`UITextChecker`), and deterministic heuristics.
- **Job-fit matching** weights four dimensions — technical skills (50), recurring terms (25), seniority (15), education (10) — and redistributes the weight of any the posting doesn't mention. Matching is whole-token, so "R" doesn't match *Paris*; `+` and `#` count as token continuations so a posting asking for C++ doesn't also register a requirement for C, while "AWS." at a sentence end still matches. A posting with no recognisable requirement returns no analysis at all rather than a confident 0%.
- **"Fix It For Me"** layers Apple Intelligence's on-device system model — via the [Foundation Models](https://developer.apple.com/documentation/foundationmodels) framework, using `@Generable` guided generation so the response is a guaranteed-shape Swift type rather than parsed free text — on top of the deterministic fixes.
- **Export generation** is written from first principles. PDFs are drawn with CoreText/CoreGraphics (US Letter, multi-page, circular photo via an ellipse clip). `.docx` files are hand-written OOXML packed into a hand-rolled ZIP container, with the headshot embedded as a JPEG part and cropped to a circle by a DrawingML `ellipse` preset. Headshots are normalized through all eight EXIF orientations and centre-cropped square before either renderer sees them.
- Built with **SwiftUI**. No third-party package dependencies.

### Graceful degradation

Apple Intelligence requires capable hardware (A17 Pro or newer). The app checks `SystemLanguageModel.availability` and tiers accordingly:

| Tier | Devices | Capability |
|---|---|---|
| Apple Intelligence | iPhone 15 Pro and newer | Full phrasing rewrites + all of the below |
| Deterministic engine | **All supported devices** | Spelling, weak-verb fixes, scoring, structure analysis |

Spelling and grammar deliberately stay on the deterministic path even where the model is available — a rules engine can't "autocorrect" someone's surname into a different word, which is exactly the kind of silent corruption a resume can't tolerate.

A rewrite is only accepted if every digit in the original survives it. In practice:

```
in  → Responsible for managing the deployment pipeline and helped with
      reducing release times by 40%.
out → Led deployment pipeline management and reduced release times by 40%.
```

Weak phrasing replaced, the 40% untouched. Three gates stand between the model and your resume,
and failing any one of them discards the rewrite and keeps your original:

| Gate | Rejects |
|---|---|
| Numbers | Any figure changed, dropped or invented — compared as whole numbers in order, so "3 sites" can't become "30 sites" |
| Ownership | A promotion from user to author: *"Worked with Nvidia GPUs"* → *"**Designed** Nvidia GPU infrastructure"*. Once the original claims ownership, rewording it is free |
| New content | A technology, employer or scope the original never mentioned — *"Built reporting tools"* → *"Built reporting tools **in Python**"* |

The second and third exist because the number check is blind to the most plausible kind of
drift: not one digit changes in any of those examples. In practice the gates reject roughly two
rewrites in five, which is the intended trade — an unchanged bullet costs nothing, an inflated
one is a lie on a job application.


## Architecture

```
                    ┌──────────────── input ────────────────┐
                    │                                       │
            PDF ────┤  PDFKit                               │
            DOCX ───┤  MinimalZipReader (inflate)           │
            photo ──┤  Vision OCR → XY-cut reading order    │
            typed ──┤  structured form                      │
                    └───────────────────┬───────────────────┘
                                        ▼
                              ResumeSectionKit
                        headings · sections · skills · links
                                        ▼
                     ┌──────────── resume model ────────────┐
                     │  ExperienceInput · WorkExperience     │
                     │  EducationEntry · JobTarget           │
                     └───────────────────┬───────────────────┘
                     ┌──────────────────┼──────────────────┐
                     ▼                  ▼                  ▼
            ResumeAnalysisEngine   JobFitAnalyzer     ResumeLibrary
             score · suggestions    weighted match    encrypted at rest
                     │                  │
                     └────────┬─────────┘
                              ▼
                     deterministic fixes
                              ▼
                  ┌───────────────────────┐
                  │  FoundationModels     │  optional · phrasing only
                  │  @Generable rewrite   │
                  └───────────┬───────────┘
                              ▼
                      isSafeRewrite gate
                 numbers preserved, or discarded
                              ▼
                    ┌─────────┴─────────┐
                    ▼                   ▼
            PDFDocumentRenderer   WordDocumentRenderer
            CoreText/CoreGraphics  OOXML + MinimalZipWriter
```

Every arrow above is in-process. Nothing crosses a network boundary at any point.

## Performance

Measured on a two-page, eight-job resume — longer than typical, so these are an upper bound.
Reproduce with:

```
TEST_RUNNER_RUN_BENCHMARKS=1 xcodebuild test -project Rolvexa.xcodeproj -scheme Rolvexa \
  -only-testing:RolvexaTests/PipelineBenchmarks -destination 'id=<your device>'
```

| Stage | iPhone 14 Pro (A16) | Simulator (Apple silicon) |
|---|---:|---:|
| PDF text extraction | 5.9 ms | 5.2 ms |
| DOCX extraction (inflate + parse) | 0.5 ms | 0.5 ms |
| Vision OCR + reading-order rebuild | **181 ms** | 1 079 ms |
| Section, skill and keyword parse | 2.3 ms | 3.4 ms |
| Job-fit matching | 2.3 ms | 1.7 ms |
| PDF rendering | 4.4 ms | 3.3 ms |
| DOCX rendering | 9.7 ms | 6.0 ms |
| Peak memory above baseline | 53 MB | 94 MB |
| On-device model rewrite | not available on A16 | 0.6 s |

Two things worth drawing out. OCR is **six times faster on the phone than in the simulator** —
the Neural Engine does the work the simulator emulates on CPU, so simulator timings understate
this app badly. And everything that isn't OCR or the language model completes in single-digit
milliseconds, which is why the UI never needs a spinner outside those two stages.

The A16 column has no model figure because Apple Intelligence needs A17 Pro or newer; that row
is the deterministic path this device actually takes.

## Threat model

What the privacy claim does and doesn't cover.

**Protected — never leaves the device:** resume contents, contact details, employment history,
uploaded photos, pasted job descriptions, and the saved resume library. There is no networking code in the
project; `URLSession`, API keys and third-party SDKs are all absent, and CI builds the same
source you can read.

**At rest:** each saved resume is written to Application Support — not Documents, so it isn't
exposed through the Files app — with complete file protection, so iOS keeps it encrypted
whenever the device is locked. The folder is excluded from iCloud and iTunes backups, and
deleting a resume removes its file outright. No resume text is written anywhere else; an
earlier debugging dump that wrote OCR output to Documents was removed.

**On request:** "Export my data" under Legal & Privacy writes every stored resume as
pretty-printed JSON to the temporary directory, still file-protected, and hands it to the share
sheet. There is no server to ask for a copy, so the export is simply the files themselves.

**Not protected, by design:** a compromised or jailbroken device; files the user deliberately
exports and then shares; screenshots; and anything typed into another app. The on-device model
runs inside Apple's sandbox under the OS's own privacy guarantees rather than ours.

**Deliberately not claimed:** this is not anonymity, and it is not protection from someone who
has your unlocked phone. It is the narrower, checkable claim that the app itself never transmits
your resume anywhere.

## Tests

```
xcodebuild test -project Rolvexa.xcodeproj -scheme Rolvexa \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

132 tests ([Swift Testing](https://developer.apple.com/documentation/testing)) over the deterministic core — the parts where a silent mistake reaches the user's actual resume:

| Suite | Covers |
|---|---|
| `JobFitAnalyzerTests` | Scoring and weight redistribution, whole-token matching ("R" must not match *Paris*, C++ must not register C), and refusing to score a posting it can't read |
| `ResumeExportTextTests` | Section order and headings, summary precedence, and that a failed upload invents no content |
| `DocumentExporterTests` | Content parity across all four templates × PDF and Word, no contact block repeated across pages, `.docx` package validity and image embedding |
| `ResumePhotoTests` | All eight EXIF orientations, checked against UIKit rather than against hand-reasoned expectations |
| `ResumeSectionKitTests` | Header detection, section synonyms, keyword extraction and skill mining |
| `ResumeLibraryTests` | Record round-trip, two resumes staying independent, newest-first ordering, search, a score going quiet once its text changes, migration from the old single-draft file, refusing to persist an untouched form, backup exclusion, one corrupt file not hiding the rest |
| `AppleIntelligenceRewriterTests` | That a rewrite never alters a number — skipped automatically on hardware without Apple Intelligence rather than failing |

Orientation and content-parity assertions compare against an independent oracle (UIKit, and the rendered PDF's own extracted text) rather than against expected values written by hand, because those are exactly the places where a wrong expectation looks like a passing test.

## Setup

Open `Rolvexa.xcodeproj` in Xcode and build. Nothing else to configure — no model weights to download, no dependencies to resolve.

Minimum deployment target is iOS 18. The Foundation Models code path is gated behind `if #available(iOS 26, *)` and an availability check, so it compiles and runs fine on older systems — it just falls back to the deterministic engine there.
