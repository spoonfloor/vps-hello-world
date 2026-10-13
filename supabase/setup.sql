-- Run once in Supabase Studio → SQL Editor on the VPS.

create table if not exists hello (
  id integer primary key default 1 check (id = 1),  -- exactly one row
  message text not null,
  updated_at timestamptz not null default now()
);

insert into hello (id, message)
values (1, 'Hello from the VPS!')
on conflict (id) do nothing;

alter table hello enable row level security;

-- Anyone can read the message.
drop policy if exists "read hello" on hello;
create policy "read hello" on hello
  for select to anon, authenticated using (true);

-- Anyone can change the message (fine for a throwaway test; no insert/delete).
drop policy if exists "update hello" on hello;
create policy "update hello" on hello
  for update to anon, authenticated using (true) with check (true);
