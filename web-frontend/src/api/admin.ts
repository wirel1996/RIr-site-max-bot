import { api } from './client'
import type { AuthUser } from './auth'

export type AdminUser = AuthUser

export type UserPayload = {
  login?: string
  name?: string
  email?: string
  position?: string
  password?: string
  role?: 'limited' | 'full' | 'admin' | 'water_payment'
}

export type MaxUser = {
  user_id: string
  chat_id?: number | null
  name: string
  first_seen?: number | null
  has_chat: boolean
}

export type AuditLog = {
  id: number
  created_at: number
  actor_login: string
  actor_name: string
  action: string
  entity_type: string
  entity_id: string
  entity_label: string
  field: string
  old_value: string
  new_value: string
  ip: string
}

export type JournalSubscriber = {
  user_id: string
  subscribed_name: string
  chat_id: number
  binding: string
}

export type JournalPerson = {
  name: string
  count: number
}

export const adminApi = {
  users: () => api.get<{ users: AdminUser[] }>('/admin/users'),
  audit: () => api.get<{ logs: AuditLog[] }>('/admin/audit?limit=5'),
  billingAudit: () => api.get<{ logs: AuditLog[] }>('/admin/audit?limit=5&entity_type=billing'),
  summerWaterAudit: () => api.get<{ logs: AuditLog[] }>('/admin/audit?limit=5&entity_type=summer_water'),
  meteringAudit: () => api.get<{ logs: AuditLog[] }>('/admin/metering-audit?limit=5'),
  journalAudit: () => api.get<{ logs: AuditLog[] }>('/admin/journal-audit?limit=5'),
  auditExportUrl: () => '/api/admin/audit/export',
  billingAuditExportUrl: () => '/api/admin/audit/export?entity_type=billing',
  summerWaterAuditExportUrl: () => '/api/admin/audit/export?entity_type=summer_water',
  meteringAuditExportUrl: () => '/api/admin/metering-audit/export',
  journalAuditExportUrl: () => '/api/admin/journal-audit/export',
  maxUsers: () =>
    api.get<{
      users: MaxUser[]
      water_payment_notify_user_id: string
      water_payment_notify_user_ids: string[]
      journal_notify_user_ids: string[]
      journal_notify_logins: string[]
      site_user_max_bindings: Record<string, string>
      daily_tasks_notify_time: string
      billing_month_creator_logins: string[]
      db_backup_enabled: boolean
      db_backup_email: string
      db_backup_daily_time: string
      db_backup_notify_user_id: string
      metering_act_counter: { category: string; year: number; next_number: number }
    }>('/admin/max-users'),
  updateMeteringActCounter: (payload: { category?: string; year: number; next_number: number }) =>
    api.patch<{ metering_act_counter: { category: string; year: number; next_number: number } }>(
      '/admin/settings/metering-act-counter',
      payload,
    ),
  updateWaterPaymentNotifyUsers: (userIds: string[]) =>
    api.patch<{ water_payment_notify_user_id: string; water_payment_notify_user_ids: string[] }>('/admin/settings/water-payment-notify', { user_ids: userIds }),
  updateJournalNotifyUsers: (userIds: string[]) =>
    api.patch<{ journal_notify_user_ids: string[] }>('/admin/settings/journal-notify', { user_ids: userIds }),
  updateJournalNotifyLogins: (logins: string[]) =>
    api.patch<{ journal_notify_logins: string[] }>('/admin/settings/journal-notify-logins', { logins }),
  updateSiteUserMaxBindings: (bindings: Record<string, string>) =>
    api.patch<{ site_user_max_bindings: Record<string, string> }>('/admin/settings/site-user-max-bindings', { bindings }),
  updateDailyTasksNotifyTime: (time: string) =>
    api.patch<{ daily_tasks_notify_time: string }>('/admin/settings/daily-tasks-notify-time', { time }),
  updateBillingMonthCreators: (logins: string[]) =>
    api.patch<{ billing_month_creator_logins: string[] }>('/admin/settings/billing-month-creators', { logins }),
  updateDbBackupSettings: (payload: { enabled: boolean; email: string; time: string; notify_user_id: string }) =>
    api.patch<{ db_backup_enabled: boolean; db_backup_email: string; db_backup_daily_time: string; db_backup_notify_user_id: string }>('/admin/settings/db-backup', payload),
  journalSubscriptions: () =>
    api.get<{ journal_people: JournalPerson[]; subscribers: JournalSubscriber[]; bindings: Record<string, string> }>('/admin/journal-subscriptions'),
  bindJournalSubscription: (userId: string, journalName: string) =>
    api.patch<{ ok: true; bindings: Record<string, string> }>(`/admin/journal-subscriptions/${encodeURIComponent(userId)}`, { journal_name: journalName }),
  clearMaxUserChatId: (userId: string) =>
    api.delete<{ ok: true }>(`/admin/max-users/${encodeURIComponent(userId)}/chat-id`),
  createUser: (payload: Required<Pick<UserPayload, 'login' | 'password'>> & UserPayload) =>
    api.post<{ user: AdminUser }>('/admin/users', payload),
  updateUser: (login: string, payload: UserPayload) =>
    api.patch<{ user: AdminUser }>(`/admin/users/${encodeURIComponent(login)}`, payload),
  deleteUser: (login: string) =>
    api.delete<{ ok: true }>(`/admin/users/${encodeURIComponent(login)}`),
}
