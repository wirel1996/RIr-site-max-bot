import { useState } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { authApi } from '../../api/auth'

export default function Profile() {
  const { user, logout } = useAuth()
  const [name, setName] = useState(user?.name || '')
  const [email, setEmail] = useState(user?.email || '')
  const [position, setPosition] = useState(user?.position || '')
  const [password, setPassword] = useState('')
  const [passwordConfirm, setPasswordConfirm] = useState('')
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  async function save() {
    const nextPassword = password.trim()
    if (nextPassword && nextPassword !== passwordConfirm.trim()) {
      setMsg('Пароли не совпадают.')
      return
    }

    setBusy(true)
    setMsg('')
    try {
      await authApi.updateProfile({ name, email, position, password: nextPassword || undefined })
      setPassword('')
      setPasswordConfirm('')
      setMsg('Профиль обновлен.')
    } catch (e: any) {
      setMsg(e?.message || 'Не удалось обновить профиль.')
    } finally {
      setBusy(false)
    }
  }

  async function logoutAll() {
    if (!window.confirm('Выйти из всех сессий?')) return
    setBusy(true)
    try {
      await authApi.logoutAll()
      await logout()
      window.location.href = '/login'
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="max-w-xl space-y-4">
      <h1 className="text-2xl font-bold">Мой профиль</h1>
      <div className="rounded-lg bg-white p-4 shadow space-y-3">
        <input className="w-full rounded border px-3 py-2 text-sm" value={name} onChange={(e) => setName(e.target.value)} placeholder="Имя" />
        <input className="w-full rounded border px-3 py-2 text-sm" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Email" />
        <input className="w-full rounded border px-3 py-2 text-sm" value={position} onChange={(e) => setPosition(e.target.value)} placeholder="Должность" />
        <input
          className="w-full rounded border px-3 py-2 text-sm"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Новый пароль (если нужно)"
        />
        <input
          className="w-full rounded border px-3 py-2 text-sm"
          type="password"
          value={passwordConfirm}
          onChange={(e) => setPasswordConfirm(e.target.value)}
          placeholder="Подтвердите новый пароль"
        />
        <div className="flex gap-2">
          <button disabled={busy} onClick={save} className="rounded bg-blue-600 px-4 py-2 text-sm text-white disabled:opacity-50">
            Сохранить
          </button>
          <button disabled={busy} onClick={logoutAll} className="rounded border border-red-300 px-4 py-2 text-sm text-red-700 disabled:opacity-50">
            Выйти из всех сессий
          </button>
        </div>
        {msg && <div className="text-sm text-gray-600">{msg}</div>}
      </div>
    </div>
  )
}
