-- Add admin staff member
-- Grants dashboard access to the admin auth user.
-- Looks the auth user up by email instead of hardcoding a UUID, so this works
-- even if the auth user is recreated (a hardcoded id would hit a FK error).
INSERT INTO public.staff (id, email, name, role)
SELECT u.id, u.email, 'Admin', 'admin'
FROM auth.users u
WHERE lower(u.email) = lower('adminmrpizza@gmail.com')
ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      name = EXCLUDED.name,
      role = EXCLUDED.role;
