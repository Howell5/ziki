export class LedgerError extends Error {
  constructor(public readonly code: "invalid_input" | "idempotency_conflict" | "unavailable" | "not_found" | "invalid_state") {
    super(code);
  }
}

export interface Dictation {
  id: string; user_id: string; idempotency_key: string;
  reserved_seconds: number; consumed_seconds: number | null;
  status: "reserved" | "processing" | "completed" | "failed" | "cancelled" | "expired";
  created_at: number; expires_at: number; finished_at: number | null;
}

function integer(value: number, min: number, max = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < min || value > max) throw new LedgerError("invalid_input");
}
function identifier(value: string) {
  if (!value || value.length > 128) throw new LedgerError("invalid_input");
}

/** Server-internal API only. Never expose grants or userId from a request body. */
export class Ledger {
  constructor(private readonly db: D1Database) {}

  async grant(input: { userId: string; source: string; kind: "trial" | "subscription" | "topup"; seconds: number; startsAt: number; expiresAt: number }) {
    identifier(input.userId); identifier(input.source);
    integer(input.seconds, 1); integer(input.startsAt, 0); integer(input.expiresAt, input.startsAt + 1);
    await this.db.prepare(`INSERT INTO credit_grants (id,user_id,source,kind,seconds,starts_at,expires_at)
      VALUES (?,?,?,?,?,?,?) ON CONFLICT(source) DO NOTHING`).bind(
      crypto.randomUUID(), input.userId, input.source, input.kind, input.seconds, input.startsAt, input.expiresAt).run();
    const row = await this.db.prepare("SELECT * FROM credit_grants WHERE source = ?").bind(input.source)
      .first<{ user_id: string; kind: string; seconds: number; starts_at: number; expires_at: number }>();
    if (!row || row.user_id !== input.userId || row.kind !== input.kind || row.seconds !== input.seconds ||
        row.starts_at !== input.startsAt || row.expires_at !== input.expiresAt) throw new LedgerError("idempotency_conflict");
  }

  private expiration(userId: string, now: number) {
    return this.db.prepare(`UPDATE dictations SET status='expired', finished_at=?
      WHERE user_id=? AND status IN ('reserved','processing') AND expires_at<=?`).bind(now, userId, now);
  }

  async expire(userId: string, now: number) {
    identifier(userId); integer(now, 0);
    await this.expiration(userId, now).run();
  }

  async balance(userId: string, now: number): Promise<number> {
    identifier(userId); integer(now, 0);
    const results = await this.db.batch<{ seconds: number }>([
      this.expiration(userId, now),
      this.db.prepare(`SELECT COALESCE(SUM(available),0) AS seconds FROM grant_balances
        WHERE user_id=? AND starts_at<=? AND expires_at>? AND revoked_at IS NULL`).bind(userId, now, now),
    ]);
    return Number(results[1]?.results[0]?.seconds ?? 0);
  }

  /** Reserve + allocate in ONE D1 transaction; earliest expiring eligible grants first.
   * Grants must survive the reservation deadline, so a near-expiry balance cannot fund work past expiry.
   * TTL is server policy, never supplied by clients. One active recording per account in MVP.
   */
  async reserve(userId: string, key: string, seconds: number, now: number): Promise<Dictation> {
    identifier(userId); identifier(key); integer(seconds, 1, 300); integer(now, 0, Number.MAX_SAFE_INTEGER - 600);
    const id = crypto.randomUUID();
    const deadline = now + seconds + 120;
    await this.db.batch([
      this.expiration(userId, now),
      this.db.prepare(`INSERT INTO dictations (id,user_id,idempotency_key,reserved_seconds,status,created_at,expires_at)
        SELECT ?,?,?,?,'reserved',?,?
        WHERE NOT EXISTS (SELECT 1 FROM dictations WHERE user_id=? AND (idempotency_key=? OR status IN ('reserved','processing')))
        AND (SELECT COALESCE(SUM(available),0) FROM grant_balances
          WHERE user_id=? AND starts_at<=? AND expires_at>=? AND revoked_at IS NULL)>=?`)
        .bind(id,userId,key,seconds,now,deadline,userId,key,userId,now,deadline,seconds),
      this.db.prepare(`INSERT INTO allocations (dictation_id,grant_id,user_id,seconds,position)
        WITH eligible AS (
          SELECT id, available, expires_at FROM grant_balances
          WHERE user_id=? AND starts_at<=? AND expires_at>=? AND revoked_at IS NULL AND available>0
        ), ordered AS (
          SELECT *, COALESCE(SUM(available) OVER (ORDER BY expires_at,id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prefix
          FROM eligible
        ) SELECT ?,id,?,MIN(available,?-prefix),prefix FROM ordered
        WHERE prefix<? AND EXISTS (SELECT 1 FROM dictations WHERE id=?)`)
        .bind(userId,now,deadline,id,userId,seconds,seconds,id),
    ]);
    const row = await this.db.prepare("SELECT * FROM dictations WHERE user_id=? AND idempotency_key=?").bind(userId,key).first<Dictation>();
    if (!row) throw new LedgerError("unavailable");
    if (row.reserved_seconds !== seconds) throw new LedgerError("idempotency_conflict");
    return row;
  }

  async get(userId: string, id: string): Promise<Dictation> {
    identifier(userId); identifier(id);
    const row = await this.db.prepare("SELECT * FROM dictations WHERE id=? AND user_id=?").bind(id,userId).first<Dictation>();
    if (!row) throw new LedgerError("not_found");
    return row;
  }

  /** Claim exactly one provider attempt. A repeated request must query state, not run inference again. */
  async start(userId: string, id: string, now: number): Promise<boolean> {
    identifier(userId); identifier(id); integer(now,0);
    const result = await this.db.prepare(`UPDATE dictations SET status='processing'
      WHERE id=? AND user_id=? AND status='reserved' AND expires_at>?`).bind(id,userId,now).run();
    return result.meta.changes === 1;
  }

  /** measuredSeconds comes from validated audio/provider usage, NOT client-reported duration. */
  async settle(userId: string, id: string, measuredSeconds: number, now: number): Promise<Dictation> {
    identifier(userId); identifier(id); integer(measuredSeconds,0,300); integer(now,0);
    await this.db.batch([
      this.db.prepare(`UPDATE dictations SET status='completed', consumed_seconds=?, finished_at=?
        WHERE id=? AND user_id=? AND status='processing' AND expires_at>? AND reserved_seconds>=?`)
        .bind(measuredSeconds,now,id,userId,now,measuredSeconds),
      this.db.prepare(`INSERT INTO usage_ledger (dictation_id,grant_id,user_id,seconds,created_at)
        SELECT a.dictation_id,a.grant_id,a.user_id,MIN(a.seconds,d.consumed_seconds-a.position),d.finished_at
        FROM allocations a JOIN dictations d ON d.id=a.dictation_id
        WHERE d.id=? AND d.user_id=? AND d.status='completed' AND d.consumed_seconds>a.position
        ON CONFLICT(dictation_id,grant_id) DO NOTHING`).bind(id,userId),
    ]);
    const row = await this.get(userId,id);
    if (row.status !== "completed") throw new LedgerError("invalid_state");
    if (row.consumed_seconds !== measuredSeconds) throw new LedgerError("idempotency_conflict");
    return row;
  }

  async release(userId: string, id: string, status: "failed" | "cancelled", now: number): Promise<Dictation> {
    identifier(userId); identifier(id); integer(now,0);
    await this.db.prepare(`UPDATE dictations SET status=?, finished_at=?
      WHERE id=? AND user_id=? AND status IN ('reserved','processing')`).bind(status,now,id,userId).run();
    return this.get(userId,id);
  }
}
