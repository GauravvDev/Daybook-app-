# Daybook

**Track your day. Understand yourself. Build a better life.**

Daybook is a personal daily-life tracker designed to feel like a calm command center, not another productivity app fighting for your attention.

## Features

- **Tasks & Habits** — custom tasks with priorities and categories, plus habit tracking with streaks and a weekly grid
- **Focus** — a built-in Pomodoro timer with adjustable durations, and the ability to book dedicated time slots for study or deep work
- **Journal** — a private, free-form space to write about your day, browsable by date
- **Health** — water, sleep, mood, workouts, and medicine/supplement tracking in one place
- **Insights & Calendar** — simple charts to spot trends, and a calendar to look back on any past day
- **Fully customizable** — rearrange or hide dashboard sections, pick your accent color, switch dark/light mode

Everything is saved privately on your own device — no accounts, no ads, no tracking. Installable as an app on any phone or desktop.



## Install as an app

- **Android / Desktop Chrome:** open the link above, then tap the install icon in the address bar (or the browser menu → "Install app" / "Add to Home Screen").
- **iPhone (Safari):** open the link, tap the Share icon, then "Add to Home Screen".

## Run it locally

No build step, no dependencies — it's a single static site.

```bash
git clone https://github.com/<your-username>/daybook-app.git
cd daybook-app
python3 -m http.server 8000
# open http://localhost:8000
```

## Tech

Plain HTML, CSS, and JavaScript — no framework, no build tools. Data is stored locally in the browser via `localStorage`. Ships with a web app manifest and service worker for offline use and installability (PWA).

## Data & privacy

All data stays on your own device. There is no server, no account system, and no data collection. Use **Settings → Data → Export** to back up your data as a JSON file, or **Import** to restore it.

## License

[MIT](LICENSE)
