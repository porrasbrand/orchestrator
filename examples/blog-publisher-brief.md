# Project Brief — Blog Publisher v2

## What
Add 3 features to the working blog-publisher app: publish history with anti-duplicate warnings, category/tag selection UI, and image support (featured + in-post insertion).

## Why
Posts go uncategorized, there's no record of what was published where, duplicate content can be accidentally sent to multiple sites (SEO penalty), and flat text posts without images don't drive readership.

## Where
- Project path: /home/mp/awesome/awesome-blogs/blog-publisher/
- Remote project path: ~/awsc-new/awesome/awesome-blogs/blog-publisher/
- Target worker: >>hetzner
- Live URL: https://www.manuelporras.com/awesome-blogs/publisher/

## Boundaries
- Do NOT touch: services/embeddings.js, services/anchorExtractor.js, config/sites.json
- Do NOT deploy to: nginx config changes (static files served separately)
- Budget constraints: none

## Success Criteria
- [ ] Every publish logged to PostgreSQL with content hash
- [ ] Duplicate content across sites triggers warning with override
- [ ] Categories and tags selectable in publish UI
- [ ] Featured image selectable from WP media library
- [ ] Images can be inserted into post content in preview
- [ ] All existing functionality still works (parse, analyze, links, publish)

## Access & Credentials
- Already configured in backend/.env (PG + OpenAI)
- WordPress credentials in config/sites.json

## Preferences
- Tech stack: match existing (Express.js, vanilla JS, PostgreSQL)
- Code style: match existing
- Testing: smoke tests via curl
- Checkpoint frequency: every 3 phases
