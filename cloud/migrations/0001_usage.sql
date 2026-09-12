-- Immutable grants and usage events; reservations hold per-grant allocations.
-- Auth owns identity lifecycle. user_id is the opaque auth subject, never client input.
CREATE TABLE credit_grants (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('trial', 'subscription', 'topup')),
  seconds INTEGER NOT NULL CHECK (seconds > 0),
  starts_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL CHECK (expires_at > starts_at),
  revoked_at INTEGER,
  UNIQUE (id, user_id)
);
CREATE INDEX grants_user_expiry ON credit_grants(user_id, expires_at);

CREATE TABLE dictations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  reserved_seconds INTEGER NOT NULL CHECK (reserved_seconds BETWEEN 1 AND 300),
  consumed_seconds INTEGER CHECK (consumed_seconds BETWEEN 0 AND reserved_seconds),
  status TEXT NOT NULL CHECK (status IN ('reserved','processing','completed','failed','cancelled','expired')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
  finished_at INTEGER,
  UNIQUE(user_id, idempotency_key),
  UNIQUE(id, user_id)
);
CREATE UNIQUE INDEX one_active_dictation ON dictations(user_id) WHERE status IN ('reserved','processing');
CREATE INDEX dictation_expiry ON dictations(status, expires_at);

CREATE TABLE allocations (
  dictation_id TEXT NOT NULL,
  grant_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  seconds INTEGER NOT NULL CHECK (seconds > 0),
  position INTEGER NOT NULL CHECK (position >= 0),
  PRIMARY KEY(dictation_id, grant_id),
  FOREIGN KEY(dictation_id, user_id) REFERENCES dictations(id, user_id),
  FOREIGN KEY(grant_id, user_id) REFERENCES credit_grants(id, user_id)
);
CREATE INDEX allocations_grant ON allocations(grant_id);

CREATE TABLE usage_ledger (
  dictation_id TEXT NOT NULL,
  grant_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  seconds INTEGER NOT NULL CHECK (seconds > 0),
  created_at INTEGER NOT NULL,
  PRIMARY KEY(dictation_id, grant_id),
  FOREIGN KEY(dictation_id, grant_id) REFERENCES allocations(dictation_id, grant_id),
  FOREIGN KEY(grant_id, user_id) REFERENCES credit_grants(id, user_id)
);
CREATE INDEX ledger_grant ON usage_ledger(grant_id);

CREATE VIEW grant_balances AS
SELECT g.*,
  g.seconds
  - COALESCE((SELECT SUM(l.seconds) FROM usage_ledger l WHERE l.grant_id = g.id), 0)
  - COALESCE((SELECT SUM(a.seconds) FROM allocations a JOIN dictations d ON d.id = a.dictation_id
      WHERE a.grant_id = g.id AND d.status IN ('reserved','processing')), 0) AS available
FROM credit_grants g;
