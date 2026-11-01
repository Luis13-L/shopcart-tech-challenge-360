import type {
  AuditQueryInput
} from "./audit.schema.js";

import {
  listAuditLogs
} from "./audit.repository.js";

export async function getAuditLogs(
  userId: number,
  filters: AuditQueryInput
) {
  return listAuditLogs(userId, filters);
}
