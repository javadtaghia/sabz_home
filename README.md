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

## Sections
- Hero — logo, headline, app mockup
- How it works — animated GIF + Learn / Play / Level up cards
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
