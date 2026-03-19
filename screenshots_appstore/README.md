# App Store screenshots (Fal Nano Banana 2)

This folder contains a small Node script that:

1. Takes **your real in-app PNG screenshots** from `raw/`.
2. Sends each image to **[fal-ai/nano-banana-2/edit](https://fal.ai/models/fal-ai/nano-banana-2/edit)** with a marketing prompt (dark “carousel card” look, headline + accent gradient, device frame).
3. Downloads the result and **resizes to App Store Connect’s iPhone 6.7″ portrait size** (**1290 × 2796**).

## Security

- Set **`FAL_KEY`** in your environment. **Do not commit API keys.** If a key was pasted into chat or committed anywhere, **rotate it** in Fal.ai.
- Copy `.env.example` to `.env` locally (optional); `.env` is gitignored.

## Setup

```bash
cd screenshots_appstore
npm install
```

Copy your source screenshots into `raw/` (PNG or JPEG). Optionally copy `manifest.example.json` to `manifest.json` and edit headlines to match each screen.

## Run

```bash
export FAL_KEY="your_fal_key_here"
npm run generate
```

Or with flags:

```bash
node generate.mjs --input ./raw --output ./output --manifest ./manifest.json
```

Outputs land in `output/` as `01-slug.png`, `02-slug.png`, … sorted by manifest order (or filename order if no manifest).

## Manifest

Each `items[]` entry can include:

| Field | Purpose |
| --- | --- |
| `input` | Filename inside `raw/` |
| `headlineWhite` | Left/top headline segment (white) |
| `headlineAccent` | Accent segment (gradient) |
| `accentGradient` | Short description of the gradient (passed to the model) |
| `featureSummary` | One-line caption under the headline |
| `extraInstructions` | Optional free-form prompt additions |
| `carousel.index` / `carousel.total` | Hints for “infinite scroll” grid continuity across shots |

If `manifest.json` is missing, every image in `raw/` is processed with generic OpenClaw-oriented copy.

## App Store Connect

Upload the **1290 × 2796** portrait set for the **6.7″ display**; Apple can derive smaller sizes from that set. Verify current requirements in [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications).
