create table if not exists public.noterr_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  vault_salt text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.noterr_notes (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  encrypted_payload text not null,
  nonce text not null,
  mac text not null,
  payload_version integer not null default 1,
  revision bigint not null default 1,
  device_id text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.noterr_notes replica identity full;

create table if not exists public.noterr_attachments (
  id uuid primary key,
  note_id uuid not null references public.noterr_notes(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  encrypted_metadata text not null,
  nonce text not null,
  mac text not null,
  revision bigint not null default 1,
  device_id text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.noterr_profiles enable row level security;
alter table public.noterr_notes enable row level security;
alter table public.noterr_attachments enable row level security;

create policy "Profiles are owned by the signed in user"
on public.noterr_profiles
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Notes are owned by the signed in user"
on public.noterr_notes
for all
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

create policy "Attachments are owned by the signed in user"
on public.noterr_attachments
for all
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

create or replace function public.noterr_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists noterr_profiles_touch_updated_at on public.noterr_profiles;
create trigger noterr_profiles_touch_updated_at
before update on public.noterr_profiles
for each row execute function public.noterr_touch_updated_at();

drop trigger if exists noterr_notes_touch_updated_at on public.noterr_notes;
create trigger noterr_notes_touch_updated_at
before update on public.noterr_notes
for each row execute function public.noterr_touch_updated_at();

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'noterr_notes'
  ) then
    alter publication supabase_realtime add table public.noterr_notes;
  end if;
end;
$$;

drop trigger if exists noterr_attachments_touch_updated_at on public.noterr_attachments;
create trigger noterr_attachments_touch_updated_at
before update on public.noterr_attachments
for each row execute function public.noterr_touch_updated_at();

insert into storage.buckets (id, name, public)
values ('noterr-attachments', 'noterr-attachments', false)
on conflict (id) do nothing;

create policy "Attachment files are owned by folder prefix"
on storage.objects
for all
using (
  bucket_id = 'noterr-attachments'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'noterr-attachments'
  and auth.uid()::text = (storage.foldername(name))[1]
);
