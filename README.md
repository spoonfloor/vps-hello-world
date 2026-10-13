# vps-hello-world

A throwaway test of the full pipeline: a page on GitHub Pages reading and writing one message in self-hosted Supabase on the VPS.

- `index.html` — the page
- `config.js` — server address and anon key (public by design)
- `supabase/setup.sql` — creates the one-row `hello` table

Done when: edit the message on one device, reload on another, and see the change.
