import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { adminApi } from '../../api/admin'
import { useAuth } from '../../contexts/AuthContext'
import { adminRu as t } from '../../locales/ru/admin'

type Role = 'limited' | 'full' | 'admin' | 'water_payment'
type Tab = 'users' | 'notifications' | 'audit'

function formatTime(value?: number | null) {
  if (!value) return '-'
  return new Date(value * 1000).toLocaleString('ru-RU')
}

function roleLabel(role: Role) {
  if (role === 'admin') return t.users.roles.admin
  if (role === 'full') return t.users.roles.full
  if (role === 'water_payment') return t.users.roles.water_payment
  return t.users.roles.limited
}

function actionLabel(action: string) {
  const labels: Record<string, string> = t.actionLabels
  return labels[action] || action
}

function fieldLabel(field?: string | null) {
  if (!field) return '-'
  const labels: Record<string, string> = {
    application: 'Заявление',
    application_date: 'Дата заявления',
    payment: 'Оплата',
    payment_date: 'Дата оплаты',
    current_date: 'Дата показаний',
    current_value: 'Текущие показания',
    volume_gvs: 'V ГВС',
  }
  return labels[field] || field
}

function AuditText({ value }: { value?: string | null }) {
  if (!value) return <span>-</span>
  return (
    <pre className="max-h-32 max-w-[28rem] overflow-auto whitespace-pre-wrap break-words rounded bg-gray-50 p-2 text-xs leading-relaxed text-gray-700">
      {value}
    </pre>
  )
}

export default function AdminUsers() {
  const queryClient = useQueryClient()
  const { user: currentUser } = useAuth()
  const [activeTab, setActiveTab] = useState<Tab>('users')
  const [message, setMessage] = useState('')
  const [createForm, setCreateForm] = useState({ login: '', name: '', email: '', position: '', password: '', role: 'full' as Role })
  const [editForm, setEditForm] = useState<{ originalLogin: string; login: string; name: string; email: string; position: string; password: string; role: Role } | null>(null)

  const usersQuery = useQuery({ queryKey: ['admin', 'users'], queryFn: () => adminApi.users() })
  const maxUsersQuery = useQuery({ queryKey: ['admin', 'max-users'], queryFn: () => adminApi.maxUsers() })
  const auditQuery = useQuery({ queryKey: ['admin', 'audit'], queryFn: () => adminApi.audit() })
  const billingAuditQuery = useQuery({ queryKey: ['admin', 'billing-audit'], queryFn: () => adminApi.billingAudit() })
  const summerWaterAuditQuery = useQuery({ queryKey: ['admin', 'summer-water-audit'], queryFn: () => adminApi.summerWaterAudit() })
  const meteringAuditQuery = useQuery({ queryKey: ['admin', 'metering-audit'], queryFn: () => adminApi.meteringAudit() })
  const journalAuditQuery = useQuery({ queryKey: ['admin', 'journal-audit'], queryFn: () => adminApi.journalAudit() })
  const journalSubsQuery = useQuery({ queryKey: ['admin', 'journal-subs'], queryFn: () => adminApi.journalSubscriptions() })

  const users = useMemo(() => [...(usersQuery.data?.users ?? [])].sort((a, b) => a.login.localeCompare(b.login, 'ru')), [usersQuery.data])
  const maxUsers = maxUsersQuery.data?.users ?? []
  const selectedWaterNotifyIds = maxUsersQuery.data?.water_payment_notify_user_ids ?? []
  const selectedJournalNotifyLogins = maxUsersQuery.data?.journal_notify_logins ?? []
  const billingMonthCreatorLogins = maxUsersQuery.data?.billing_month_creator_logins ?? []
  const dbBackupEnabled = maxUsersQuery.data?.db_backup_enabled === true
  const dbBackupEmail = maxUsersQuery.data?.db_backup_email ?? ''
  const dbBackupTime = maxUsersQuery.data?.db_backup_daily_time || '02:00'
  const dbBackupNotifyUserId = maxUsersQuery.data?.db_backup_notify_user_id ?? ''
  const [dbBackupNotifyDraft, setDbBackupNotifyDraft] = useState('')
  const dailyNotifyTime = maxUsersQuery.data?.daily_tasks_notify_time || '08:00'
  const canDeleteSelected = editForm && currentUser?.login !== editForm.login

  useEffect(() => {
    setDbBackupNotifyDraft(dbBackupNotifyUserId)
  }, [dbBackupNotifyUserId])

  const createMutation = useMutation({
    mutationFn: () => adminApi.createUser(createForm),
    onSuccess: async ({ user }) => {
      setCreateForm({ login: '', name: '', email: '', position: '', password: '', role: 'full' })
      setMessage(`Создан: ${user.login}`)
      await queryClient.invalidateQueries({ queryKey: ['admin', 'users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || 'Не удалось создать'),
  })
  const updateMutation = useMutation({
    mutationFn: () => {
      if (!editForm) throw new Error('Пользователь не выбран')
      return adminApi.updateUser(editForm.originalLogin, {
        login: editForm.login,
        name: editForm.name,
        email: editForm.email,
        position: editForm.position,
        role: editForm.role,
        password: editForm.password.trim() ? editForm.password : undefined,
      })
    },
    onSuccess: async ({ user }) => {
      setEditForm((prev) => (prev ? { ...prev, originalLogin: user.login, login: user.login, name: user.name, email: user.email || '', position: user.position || '', role: user.role, password: '' } : prev))
      setMessage(`Обновлён: ${user.login}`)
      await queryClient.invalidateQueries({ queryKey: ['admin', 'users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || 'Не удалось обновить'),
  })
  const deleteMutation = useMutation({
    mutationFn: (login: string) => adminApi.deleteUser(login),
    onSuccess: async () => {
      setEditForm(null)
      setMessage('Удалён.')
      await queryClient.invalidateQueries({ queryKey: ['admin', 'users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || 'Не удалось удалить'),
  })
  const waterNotifyMutation = useMutation({
    mutationFn: (ids: string[]) => adminApi.updateWaterPaymentNotifyUsers(ids),
    onSuccess: async () => {
      setMessage(t.messages.waterNotifyUpdated)
      await queryClient.invalidateQueries({ queryKey: ['admin', 'max-users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || 'Update failed'),
  })
  const notifyLoginsMutation = useMutation({
    mutationFn: (logins: string[]) => adminApi.updateJournalNotifyLogins(logins),
    onSuccess: async () => {
      setMessage(t.messages.journalRecipientsUpdated)
      await queryClient.invalidateQueries({ queryKey: ['admin', 'max-users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || t.messages.journalRecipientsUpdateFailed),
  })
  const clearMaxChatMutation = useMutation({
    mutationFn: (userId: string) => adminApi.clearMaxUserChatId(userId),
    onSuccess: async () => {
      setMessage('chat_id удалён.')
      await queryClient.invalidateQueries({ queryKey: ['admin', 'max-users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || 'Не удалось удалить'),
  })
  const bindJournalSubMutation = useMutation({
    mutationFn: ({ userId, journalName }: { userId: string; journalName: string }) => adminApi.bindJournalSubscription(userId, journalName),
    onSuccess: async () => {
      setMessage('Привязка подписки журнала обновлена.')
      await queryClient.invalidateQueries({ queryKey: ['admin', 'journal-subs'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || 'Не удалось обновить привязку'),
  })
  const dailyTimeMutation = useMutation({
    mutationFn: (time: string) => adminApi.updateDailyTasksNotifyTime(time),
    onSuccess: async () => {
      setMessage(t.messages.dailyTimeUpdated)
      await queryClient.invalidateQueries({ queryKey: ['admin', 'max-users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || t.messages.dailyTimeUpdateFailed),
  })
  const billingCreatorsMutation = useMutation({
    mutationFn: (logins: string[]) => adminApi.updateBillingMonthCreators(logins),
    onSuccess: async () => {
      setMessage(t.messages.billingCreatorsUpdated)
      await queryClient.invalidateQueries({ queryKey: ['admin', 'max-users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || t.messages.billingCreatorsUpdateFailed),
  })
  const dbBackupMutation = useMutation({
    mutationFn: (payload: { enabled: boolean; email: string; time: string; notify_user_id: string }) => adminApi.updateDbBackupSettings(payload),
    onSuccess: async () => {
      setMessage(t.messages.backupSettingsUpdated)
      await queryClient.invalidateQueries({ queryKey: ['admin', 'max-users'] })
    },
    onError: (e: { message?: string }) => setMessage(e.message || t.messages.backupSettingsFailed),
  })

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold">{t.title}</h1>
        <p className="text-sm text-gray-600">{t.subtitle}</p>
      </div>
      <div className="flex gap-2">
        <button className={`rounded border px-3 py-1 text-sm ${activeTab === 'users' ? 'bg-blue-600 text-white border-blue-600' : 'bg-white'}`} onClick={() => setActiveTab('users')}>{t.tabs.users}</button>
        <button className={`rounded border px-3 py-1 text-sm ${activeTab === 'notifications' ? 'bg-blue-600 text-white border-blue-600' : 'bg-white'}`} onClick={() => setActiveTab('notifications')}>{t.tabs.notifications}</button>
        <button className={`rounded border px-3 py-1 text-sm ${activeTab === 'audit' ? 'bg-blue-600 text-white border-blue-600' : 'bg-white'}`} onClick={() => setActiveTab('audit')}>{t.tabs.audit}</button>
      </div>
      {message && <div className="rounded border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">{message}</div>}

      {activeTab === 'users' && (
        <>
          <section className="rounded-lg bg-white p-4 shadow">
            <h2 className="mb-3 text-lg font-semibold">{t.users.createTitle}</h2>
            <form className="grid gap-3 md:grid-cols-7" onSubmit={(e) => { e.preventDefault(); createMutation.mutate() }}>
              <input value={createForm.login} onChange={(e) => setCreateForm((p) => ({ ...p, login: e.target.value }))} placeholder={t.users.login} className="rounded border px-3 py-2 text-sm" required />
              <input value={createForm.name} onChange={(e) => setCreateForm((p) => ({ ...p, name: e.target.value }))} placeholder={t.users.name} className="rounded border px-3 py-2 text-sm" />
              <input value={createForm.email} onChange={(e) => setCreateForm((p) => ({ ...p, email: e.target.value }))} placeholder="Email" className="rounded border px-3 py-2 text-sm" />
              <input value={createForm.position} onChange={(e) => setCreateForm((p) => ({ ...p, position: e.target.value }))} placeholder={t.users.position} className="rounded border px-3 py-2 text-sm" />
              <input value={createForm.password} onChange={(e) => setCreateForm((p) => ({ ...p, password: e.target.value }))} placeholder={t.users.password} type="password" minLength={8} className="rounded border px-3 py-2 text-sm" required />
              <select value={createForm.role} onChange={(e) => setCreateForm((p) => ({ ...p, role: e.target.value as Role }))} className="rounded border px-3 py-2 text-sm">
                <option value="full">{t.users.roles.full}</option><option value="limited">{t.users.roles.limited}</option><option value="water_payment">{t.users.roles.water_payment}</option><option value="admin">{t.users.roles.admin}</option>
              </select>
              <button type="submit" className="rounded bg-blue-600 px-4 py-2 text-sm font-medium text-white">{t.users.create}</button>
            </form>
          </section>
          <div className="grid gap-5 lg:grid-cols-[1fr_360px]">
            <section className="overflow-hidden rounded-lg bg-white shadow">
              <div className="border-b px-4 py-3"><h2 className="text-lg font-semibold">{t.users.listTitle}</h2></div>
              <div className="overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2">{t.users.login}</th><th className="px-3 py-2">{t.users.name}</th><th className="px-3 py-2">Email</th><th className="px-3 py-2">{t.users.position}</th><th className="px-3 py-2">{t.users.role}</th><th className="px-3 py-2">{t.users.lastActivity}</th><th className="px-3 py-2"></th></tr></thead><tbody>{users.map((u) => <tr key={u.login} className="border-t"><td className="px-3 py-2">{u.login}</td><td className="px-3 py-2">{u.name || '-'}</td><td className="px-3 py-2">{u.email || '-'}</td><td className="px-3 py-2">{u.position || '-'}</td><td className="px-3 py-2">{roleLabel(u.role)}</td><td className="px-3 py-2">{formatTime(u.last_seen_at || u.last_login_at)}</td><td className="px-3 py-2 text-right"><button onClick={() => setEditForm({ originalLogin: u.login, login: u.login, name: u.name || u.login, email: u.email || '', position: u.position || '', password: '', role: u.role })} className="text-blue-700 hover:underline">{t.users.edit}</button></td></tr>)}</tbody></table></div>
            </section>
            <section className="rounded-lg bg-white p-4 shadow">
              <h2 className="mb-3 text-lg font-semibold">{t.users.editTitle}</h2>
              {editForm && <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); updateMutation.mutate() }}>
                <input value={editForm.login} onChange={(e) => setEditForm((p) => p ? { ...p, login: e.target.value } : p)} className="w-full rounded border px-3 py-2 text-sm" />
                <input value={editForm.name} onChange={(e) => setEditForm((p) => p ? { ...p, name: e.target.value } : p)} className="w-full rounded border px-3 py-2 text-sm" />
                <input value={editForm.email} onChange={(e) => setEditForm((p) => p ? { ...p, email: e.target.value } : p)} className="w-full rounded border px-3 py-2 text-sm" placeholder="Email" />
                <input value={editForm.position} onChange={(e) => setEditForm((p) => p ? { ...p, position: e.target.value } : p)} className="w-full rounded border px-3 py-2 text-sm" placeholder={t.users.position} />
                <input value={editForm.password} onChange={(e) => setEditForm((p) => p ? { ...p, password: e.target.value } : p)} type="password" placeholder={t.users.newPassword} className="w-full rounded border px-3 py-2 text-sm" />
                <select value={editForm.role} onChange={(e) => setEditForm((p) => p ? { ...p, role: e.target.value as Role } : p)} className="w-full rounded border px-3 py-2 text-sm"><option value="full">{t.users.roles.full}</option><option value="limited">{t.users.roles.limited}</option><option value="water_payment">{t.users.roles.water_payment}</option><option value="admin">{t.users.roles.admin}</option></select>
                <div className="flex gap-2"><button type="submit" className="rounded bg-blue-600 px-4 py-2 text-sm text-white">{t.users.save}</button><button type="button" disabled={!canDeleteSelected} onClick={() => { if (window.confirm(`${t.messages.deleteConfirm} ${editForm.login}?`)) deleteMutation.mutate(editForm.login) }} className="rounded border border-red-200 px-4 py-2 text-sm text-red-700">{t.users.remove}</button></div>
              </form>}
            </section>
          </div>
        </>
      )}

      {activeTab === 'notifications' && (
        <>
          <section className="rounded-lg bg-white p-4 shadow">
            <h2 className="mb-3 text-lg font-semibold">{t.notifications.waterTitle}</h2>
            <div className="space-y-2">{maxUsers.filter((m) => m.has_chat).map((m) => <label key={`wp-${m.user_id}`} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={selectedWaterNotifyIds.includes(m.user_id)} onChange={(e) => { const next = e.target.checked ? [...selectedWaterNotifyIds, m.user_id] : selectedWaterNotifyIds.filter((id) => id !== m.user_id); waterNotifyMutation.mutate([...new Set(next)]) }} /><span>{m.name || m.user_id}</span></label>)}</div>
          </section>
          <section className="rounded-lg bg-white p-4 shadow">
            <h2 className="mb-3 text-lg font-semibold">{t.notifications.dailyTasksTimeTitle}</h2>
            <div className="flex items-center gap-2">
              <input
                type="time"
                defaultValue={dailyNotifyTime}
                className="rounded border px-3 py-2 text-sm"
                onBlur={(e) => {
                  const next = e.target.value || '08:00'
                  if (next !== dailyNotifyTime) dailyTimeMutation.mutate(next)
                }}
              />
              <span className="text-xs text-gray-600">{t.notifications.tomsk}</span>
            </div>
          </section>
          <section className="rounded-lg bg-white p-4 shadow">
            <h2 className="mb-3 text-lg font-semibold">{t.notifications.billingCreatorsTitle}</h2>
            <p className="mb-3 text-xs text-gray-600">{t.notifications.billingCreatorsHint}</p>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {users.map((u) => {
                const normalized = u.login.toLowerCase()
                return (
                  <label key={`bm-${u.login}`} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={billingMonthCreatorLogins.includes(normalized)}
                      onChange={(e) => {
                        const next = e.target.checked
                          ? [...billingMonthCreatorLogins, normalized]
                          : billingMonthCreatorLogins.filter((x) => x !== normalized)
                        billingCreatorsMutation.mutate([...new Set(next)])
                      }}
                    />
                    <span>{u.login}</span>
                  </label>
                )
              })}
            </div>
          </section>
          <section className="rounded-lg bg-white p-4 shadow">
            <h2 className="mb-3 text-lg font-semibold">{t.notifications.dailyBackupTitle}</h2>
            <div className="grid gap-3 md:grid-cols-3">
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={dbBackupEnabled}
                  onChange={(e) => dbBackupMutation.mutate({ enabled: e.target.checked, email: dbBackupEmail, time: dbBackupTime, notify_user_id: dbBackupNotifyUserId })}
                />
                <span>{t.notifications.sendBackup}</span>
              </label>
              <label className="text-sm">
                <div className="mb-1 text-gray-600">{t.notifications.backupTime}</div>
                <input
                  type="time"
                  defaultValue={dbBackupTime}
                  className="w-full rounded border px-3 py-2 text-sm"
                  onBlur={(e) => {
                    const next = e.target.value || dbBackupTime
                    if (next !== dbBackupTime) dbBackupMutation.mutate({ enabled: dbBackupEnabled, email: dbBackupEmail, time: next, notify_user_id: dbBackupNotifyUserId })
                  }}
                />
              </label>
              <label className="text-sm">
                <div className="mb-1 text-gray-600">{t.notifications.backupEmail}</div>
                <input
                  type="email"
                  defaultValue={dbBackupEmail}
                  className="w-full rounded border px-3 py-2 text-sm"
                  placeholder="example@yandex.ru"
                  onBlur={(e) => {
                    const next = e.target.value.trim()
                    if (next !== dbBackupEmail) dbBackupMutation.mutate({ enabled: dbBackupEnabled, email: next, time: dbBackupTime, notify_user_id: dbBackupNotifyUserId })
                  }}
                />
              </label>
              <label className="text-sm">
                <div className="mb-1 text-gray-600">{t.notifications.backupNotifyUser}</div>
                <select
                  className="w-full rounded border px-3 py-2 text-sm"
                  value={dbBackupNotifyDraft}
                  onChange={(e) => {
                    const next = e.target.value
                    setDbBackupNotifyDraft(next)
                    dbBackupMutation.mutate({ enabled: dbBackupEnabled, email: dbBackupEmail, time: dbBackupTime, notify_user_id: next })
                  }}
                >
                  <option value="">{t.notifications.notSelected}</option>
                  {maxUsers.filter((m) => m.has_chat).map((m) => (
                    <option key={`backup-notify-${m.user_id}`} value={m.user_id}>{m.name || m.user_id}</option>
                  ))}
                </select>
              </label>
            </div>
          </section>
          <section className="rounded-lg bg-white p-4 shadow">
            <h2 className="mb-3 text-lg font-semibold">{t.notifications.maxUsersTitle}</h2>
            <div className="overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2">{t.notifications.person}</th><th className="px-3 py-2">user_id</th><th className="px-3 py-2">chat_id</th><th className="px-3 py-2"></th></tr></thead><tbody>{maxUsers.map((m) => <tr key={m.user_id} className="border-t"><td className="px-3 py-2">{m.name || '-'}</td><td className="px-3 py-2">{m.user_id}</td><td className="px-3 py-2">{m.chat_id || '-'}</td><td className="px-3 py-2">{m.has_chat && <button onClick={() => { if (window.confirm(`${t.messages.deleteConfirm} chat_id ? ${m.name || m.user_id}?`)) clearMaxChatMutation.mutate(m.user_id) }} className="text-red-700 hover:underline">{t.notifications.removeChatId}</button>}</td></tr>)}</tbody></table></div>
          </section>
          <section className="rounded-lg bg-white p-4 shadow">
            <h2 className="mb-3 text-lg font-semibold">{t.notifications.journalSubsTitle}</h2>
            <p className="mb-3 text-xs text-gray-600">{t.notifications.journalSubsHint}</p>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-gray-100 text-left">
                  <tr>
                    <th className="px-3 py-2">user_id</th>
                    <th className="px-3 py-2">{t.notifications.botSubName}</th>
                    <th className="px-3 py-2">{t.notifications.botSubActive}</th>
                    <th className="px-3 py-2">chat_id</th>
                    <th className="px-3 py-2">{t.notifications.journalBinding}</th>
                  </tr>
                </thead>
                <tbody>
                  {(journalSubsQuery.data?.subscribers ?? []).map((s) => (
                    <tr key={`sub-${s.user_id}`} className="border-t">
                      <td className="px-3 py-2">{s.user_id}</td>
                      <td className="px-3 py-2">{s.subscribed_name || '-'}</td>
                      <td className="px-3 py-2">{s.chat_id ? t.notifications.yes : t.notifications.no}</td>
                      <td className="px-3 py-2">{s.chat_id}</td>
                      <td className="px-3 py-2">
                        <select
                          className="rounded border px-2 py-1 text-sm min-w-[280px]"
                          value={s.binding || ''}
                          disabled={bindJournalSubMutation.isPending}
                          onChange={(e) => bindJournalSubMutation.mutate({ userId: s.user_id, journalName: e.target.value })}
                        >
                          <option value="">{t.notifications.autoByName}</option>
                          {(journalSubsQuery.data?.journal_people ?? []).map((p) => (
                            <option key={`jp-${s.user_id}-${p.name}`} value={p.name}>{p.name}</option>
                          ))}
                        </select>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="mt-4 border-t pt-4">
              <h3 className="mb-2 text-sm font-semibold">{t.notifications.journalRecipients}</h3>
              <p className="mb-3 text-xs text-gray-600">{t.notifications.journalRecipientsHint}</p>
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {users.map((u) => (
                  <label key={`jn-${u.login}`} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={selectedJournalNotifyLogins.includes(u.login)}
                      onChange={(e) => {
                        const next = e.target.checked
                          ? [...selectedJournalNotifyLogins, u.login]
                          : selectedJournalNotifyLogins.filter((x) => x !== u.login)
                        notifyLoginsMutation.mutate([...new Set(next)])
                      }}
                    />
                    <span>{u.login}</span>
                  </label>
                ))}
              </div>
            </div>
          </section>
        </>
      )}

      {activeTab === 'audit' && (
        <>
          <section className="overflow-hidden rounded-lg bg-white shadow">
            <div className="flex items-center justify-between gap-3 border-b px-4 py-3"><h2 className="text-lg font-semibold">{t.audit.billingTitle}</h2><a href={adminApi.billingAuditExportUrl()} className="rounded border bg-white px-3 py-1.5 text-sm">{t.audit.export}</a></div>
            <div className="overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2">{t.audit.date}</th><th className="px-3 py-2">{t.audit.user}</th><th className="px-3 py-2">{t.audit.action}</th><th className="px-3 py-2">{t.audit.entity}</th><th className="px-3 py-2">{t.audit.field}</th><th className="px-3 py-2">{t.audit.old}</th><th className="px-3 py-2">{t.audit.now}</th></tr></thead><tbody>{(billingAuditQuery.data?.logs ?? []).map((l) => <tr key={l.id} className="border-t"><td className="px-3 py-2">{formatTime(l.created_at)}</td><td className="px-3 py-2">{l.actor_name || l.actor_login || '-'}</td><td className="px-3 py-2">{actionLabel(l.action)}</td><td className="px-3 py-2">{l.entity_label || l.entity_id || '-'}</td><td className="px-3 py-2">{fieldLabel(l.field)}</td><td className="px-3 py-2"><AuditText value={l.old_value} /></td><td className="px-3 py-2"><AuditText value={l.new_value} /></td></tr>)}</tbody></table></div>
          </section>
          <section className="overflow-hidden rounded-lg bg-white shadow">
            <div className="flex items-center justify-between gap-3 border-b px-4 py-3"><h2 className="text-lg font-semibold">{t.audit.meteringTitle}</h2><a href={adminApi.meteringAuditExportUrl()} className="rounded border bg-white px-3 py-1.5 text-sm">{t.audit.export}</a></div>
            <div className="overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2">{t.audit.date}</th><th className="px-3 py-2">{t.audit.user}</th><th className="px-3 py-2">{t.audit.action}</th><th className="px-3 py-2">{t.audit.entity}</th><th className="px-3 py-2">{t.audit.field}</th><th className="px-3 py-2">{t.audit.old}</th><th className="px-3 py-2">{t.audit.now}</th></tr></thead><tbody>{(meteringAuditQuery.data?.logs ?? []).map((l) => <tr key={l.id} className="border-t"><td className="px-3 py-2">{formatTime(l.created_at)}</td><td className="px-3 py-2">{l.actor_name || l.actor_login || '-'}</td><td className="px-3 py-2">{actionLabel(l.action)}</td><td className="px-3 py-2">{l.entity_label || l.entity_id || '-'}</td><td className="px-3 py-2">{fieldLabel(l.field)}</td><td className="px-3 py-2"><AuditText value={l.old_value} /></td><td className="px-3 py-2"><AuditText value={l.new_value} /></td></tr>)}</tbody></table></div>
          </section>
          <section className="overflow-hidden rounded-lg bg-white shadow">
            <div className="flex items-center justify-between gap-3 border-b px-4 py-3"><h2 className="text-lg font-semibold">{t.audit.summerWaterTitle}</h2><a href={adminApi.summerWaterAuditExportUrl()} className="rounded border bg-white px-3 py-1.5 text-sm">{t.audit.export}</a></div>
            <div className="overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2">{t.audit.date}</th><th className="px-3 py-2">{t.audit.user}</th><th className="px-3 py-2">{t.audit.action}</th><th className="px-3 py-2">{t.audit.entity}</th><th className="px-3 py-2">{t.audit.field}</th><th className="px-3 py-2">{t.audit.old}</th><th className="px-3 py-2">{t.audit.now}</th></tr></thead><tbody>{(summerWaterAuditQuery.data?.logs ?? []).map((l) => <tr key={l.id} className="border-t"><td className="px-3 py-2">{formatTime(l.created_at)}</td><td className="px-3 py-2">{l.actor_name || l.actor_login || '-'}</td><td className="px-3 py-2">{actionLabel(l.action)}</td><td className="px-3 py-2">{l.entity_label || l.entity_id || '-'}</td><td className="px-3 py-2">{fieldLabel(l.field)}</td><td className="px-3 py-2"><AuditText value={l.old_value} /></td><td className="px-3 py-2"><AuditText value={l.new_value} /></td></tr>)}</tbody></table></div>
          </section>
          <section className="overflow-hidden rounded-lg bg-white shadow">
            <div className="flex items-center justify-between gap-3 border-b px-4 py-3"><h2 className="text-lg font-semibold">{t.audit.journalTitle}</h2><a href={adminApi.journalAuditExportUrl()} className="rounded border bg-white px-3 py-1.5 text-sm">{t.audit.export}</a></div>
            <div className="overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2">{t.audit.date}</th><th className="px-3 py-2">{t.audit.user}</th><th className="px-3 py-2">{t.audit.cell}</th><th className="px-3 py-2">{t.audit.old}</th><th className="px-3 py-2">{t.audit.now}</th></tr></thead><tbody>{(journalAuditQuery.data?.logs ?? []).map((l) => <tr key={l.id} className="border-t"><td className="px-3 py-2">{formatTime(l.created_at)}</td><td className="px-3 py-2">{l.actor_name || l.actor_login || '-'}</td><td className="px-3 py-2">{l.entity_label || l.entity_id || '-'}</td><td className="px-3 py-2"><AuditText value={l.old_value} /></td><td className="px-3 py-2"><AuditText value={l.new_value} /></td></tr>)}</tbody></table></div>
          </section>
          <section className="overflow-hidden rounded-lg bg-white shadow">
            <div className="flex items-center justify-between gap-3 border-b px-4 py-3"><h2 className="text-lg font-semibold">{t.audit.actionsTitle}</h2><a href={adminApi.auditExportUrl()} className="rounded border bg-white px-3 py-1.5 text-sm">{t.audit.export}</a></div>
            <div className="overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2">{t.audit.date}</th><th className="px-3 py-2">{t.audit.user}</th><th className="px-3 py-2">{t.audit.action}</th><th className="px-3 py-2">{t.audit.entity}</th><th className="px-3 py-2">{t.audit.field}</th><th className="px-3 py-2">{t.audit.old}</th><th className="px-3 py-2">{t.audit.now}</th></tr></thead><tbody>{(auditQuery.data?.logs ?? []).map((l) => <tr key={l.id} className="border-t"><td className="px-3 py-2">{formatTime(l.created_at)}</td><td className="px-3 py-2">{l.actor_name || l.actor_login || '-'}</td><td className="px-3 py-2">{actionLabel(l.action)}</td><td className="px-3 py-2">{l.entity_label || l.entity_id || '-'}</td><td className="px-3 py-2">{fieldLabel(l.field)}</td><td className="px-3 py-2"><AuditText value={l.old_value} /></td><td className="px-3 py-2"><AuditText value={l.new_value} /></td></tr>)}</tbody></table></div>
          </section>
        </>
      )}
    </div>
  )
}

