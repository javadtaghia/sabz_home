# Sabz Landing Page

## Setup

1. Install dependencies (if not already):
   ```
   npm install lucide-react
   ```

2. Place these files in your Next.js / Vite project:
   - `src/components/SabzLandingPage.jsx` → your components folder
   - `public/sabzlogo.png` → your public folder
   - `public/sabz_video.mp4` → your public folder

3. Import and use the component:
   ```jsx
   import SabzLandingPage from './components/SabzLandingPage'
   export default function Page() {
     return <SabzLandingPage />
   }
   ```

## Dependencies
- React 18+
- lucide-react
- Google Fonts: DM Sans + Fraunces (loaded via CSS @import)

## AWS Amplify Deployment

This repo includes an [amplify.yml](./amplify.yml) build spec for Amplify Hosting.

### 1) Connect repository
- In AWS Amplify Console, choose **New app** → **Host web app**
- Connect GitHub and select `javadtaghia/sabz_home`
- Choose branch: `main`

### 2) Build settings
- Amplify should detect and use `amplify.yml` automatically.
- Build output is `dist`.

### 3) SPA rewrite rule (important)
For client-side routing fallback, add this rewrite in Amplify Console:
- Source address: `/<*>`
- Target address: `/index.html`
- Type: `200 (Rewrite)`

### 4) Forms API wiring (AWS CLI)
- Run:
  - `chmod +x scripts/deploy_forms_api.sh`
  - `./scripts/deploy_forms_api.sh`
- This creates/updates:
  - DynamoDB tables `wishlist` and `emails` (PK: `email`) in `ap-southeast-2`
  - Lambda functions `sabz-waitlist-handler` and `sabz-contact-handler`
  - API Gateway HTTP API routes:
    - `POST /waitlist`
    - `POST /contact`
- Set Amplify environment variable:
  - `VITE_API_BASE_URL=https://que5tzjtpa.execute-api.ap-southeast-2.amazonaws.com`

## Sections
- Hero — logo, headline, app mockup
- How it works — MP4 walkthrough + Learn / Play / Level up cards
- Levels — Beginner / Intermediate / Advanced
- Features — Why Sabz grid
- CTA — email waitlist form
- Footer

## Links
All navigation and in-page links are wired to section IDs:
- #hero → top / logo
- #how-it-works → How it works section
- #levels → Levels section
- #features → Features section
- #waitlist → email signup form
