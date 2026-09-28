# Rolvexa

<img src="screenshots/splash-screen.png" alt="Rolvexa splash screen" width="180" />

**Your AI copilot for landing the job.** Rolvexa is an iOS app that reviews, builds, and tailors resumes and cover letters — entirely on-device, with no cloud AI and no network access at any point.

## What it does

Rolvexa supports two ways to start:

- **Upload an existing resume** (PDF or Word) — get an instant score, a breakdown (ATS compatibility, content & impact, grammar & clarity, formatting), and concrete suggestions for improving it.
- **Write a resume from scratch** — fill in your contact info, education, and professional experience, and Rolvexa assembles a structured resume from it.

From there, Rolvexa:

- Picks a professional template (Modern Edge, Minimal Pro, Creative Bold, Executive Suite) — or keeps your uploaded file's original layout untouched if you'd rather not restyle it.
- Scores your resume and flags issues: spelling, weak passive phrasing ("responsible for" → "Led"), repeated words, missing sections, missing quantifiable metrics, and more.
- **"Fix It For Me"** — applies safe, deterministic fixes automatically, and can call a small bundled on-device language model to rewrite bullet points and paragraphs for punchier phrasing (never inventing facts, numbers, or achievements that aren't already there).
- Suggests other job titles you're a good fit for, based on your skills.
- Generates a tailored cover letter and a job-fit analysis alongside your resume.
- Exports everything as PDF or Word, ready to send.

## How it works, technically

Everything runs locally on the device:

- **Text extraction** from uploaded PDF/DOCX files.
- **Scoring and suggestions** via `NaturalLanguage` tokenization, the system spell checker (`UITextChecker`), and deterministic heuristics — no network calls.
- **"Fix It For Me"** layers a bundled 4-bit-quantized Llama-3.2-1B-Instruct model (via Apple's [MLX](https://github.com/ml-explore/mlx-swift) framework) on top of the deterministic fixes, for phrasing rewrites beyond simple word-swaps.
- Built with **SwiftUI**, targeting iOS.

## Setup

The on-device model weights (~680MB) aren't committed to this repo — GitHub blocks files over 100MB. To run the AI rewrite feature locally, download the model into `Rolvexa/Resources/ResumeRewriteModel/`:

```
mlx-community/Llama-3.2-1B-Instruct-4bit
```
(available on Hugging Face) — grab `config.json`, `model.safetensors`, `model.safetensors.index.json`, `special_tokens_map.json`, `tokenizer.json`, and `tokenizer_config.json`.

Everything else works out of the box by opening `Rolvexa.xcodeproj` in Xcode.
