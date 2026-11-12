-- Staff table migration
-- One row per Supabase Auth user that is allowed into the staff console.
-- The app treats "auth user with no matching staff row" as "not staff",
-- which is why a missing row sends the user back to the home page.

CREATE TABLE IF NOT EXISTS public.staff (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'staff' CHECK (role IN ('admin', 'staff')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;

-- A staff member may read their own row (the app checks this after login).
DROP POLICY IF EXISTS "Staff can read own data" ON public.staff;
CREATE POLICY "Staff can read own data" ON public.staff
  FOR SELECT TO authenticated
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "Staff can update own data" ON public.staff;
CREATE POLICY "Staff can update own data" ON public.staff
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Service role (server-side) has full access, matching the orders table setup.
DROP POLICY IF EXISTS "Service role full access" ON public.staff;
CREATE POLICY "Service role full access" ON public.staff
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);
