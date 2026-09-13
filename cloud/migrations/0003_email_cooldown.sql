-- HMAC recipient identifiers, never raw email addresses or OTPs. Bounded to one
-- row per attempted recipient; production retention must prune expired rows.
CREATE TABLE email_cooldown (
  recipient TEXT PRIMARY KEY NOT NULL,
  next_send_at INTEGER NOT NULL
);
