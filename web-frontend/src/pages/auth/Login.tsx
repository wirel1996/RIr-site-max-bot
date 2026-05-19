import { useState, type FormEvent } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../../contexts/AuthContext'
import { authApi } from '../../api/auth'
import type { ApiError } from '../../api/client'

type LocationState = { from?: string }

export default function Login() {
  const { login, state } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const from = (location.state as LocationState | null)?.from || '/'
  const resetToken = new URLSearchParams(location.search).get('reset_token') || ''

  const [loginValue, setLoginValue] = useState('')
  const [passwordValue, setPasswordValue] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const [forgotOpen, setForgotOpen] = useState(false)
  const [forgotValue, setForgotValue] = useState('')
  const [forgotMsg, setForgotMsg] = useState<string | null>(null)
  const [forgotOk, setForgotOk] = useState(false)
  const [resetPassword, setResetPassword] = useState('')
  const [resetPasswordConfirm, setResetPasswordConfirm] = useState('')
  const [resetMsg, setResetMsg] = useState<string | null>(null)

  if (state.status === 'authed') {
    navigate(from, { replace: true })
    return null
  }

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!loginValue.trim() || !passwordValue) return
    setSubmitting(true)
    setError(null)
    try {
      await login(loginValue.trim(), passwordValue)
      navigate(from, { replace: true })
    } catch (err) {
      const apiErr = err as ApiError
      setError(apiErr?.message || 'Ошибка авторизации')
    } finally {
      setSubmitting(false)
    }
  }

  async function onForgot(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!forgotValue.trim()) return
    setForgotMsg(null)
    setForgotOk(false)
    try {
      await authApi.forgot(forgotValue.trim())
      setForgotMsg('Письмо с восстановлением пароля отправлено на почту')
      setForgotOk(true)
    } catch (err) {
      const apiErr = err as ApiError
      const raw = (apiErr?.message || '').trim().toLowerCase()
      if (raw === 'not found' || raw === 'user not found') {
        setForgotMsg('Пользователь с такой почтой не найден')
      } else {
        setForgotMsg(apiErr?.message || 'Не удалось отправить письмо.')
      }
    }
  }

  async function onReset(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!resetToken || !resetPassword) return
    if (resetPassword !== resetPasswordConfirm) {
      setResetMsg('Пароли не совпадают.')
      return
    }
    setResetMsg(null)
    try {
      await authApi.resetPassword(resetToken, resetPassword)
      setResetMsg('Пароль обновлен. Теперь войдите с новым паролем.')
      setResetPassword('')
      setResetPasswordConfirm('')
    } catch (err) {
      const apiErr = err as ApiError
      setResetMsg(apiErr?.message || 'Не удалось сменить пароль.')
    }
  }

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center px-4">
      <div className="w-full max-w-sm bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <div className="mb-5">
          <h1 className="text-lg font-semibold">Сервис ОКЭ</h1>
          <p className="text-sm text-gray-500 mt-1">Вход в систему</p>
        </div>

        <form onSubmit={onSubmit} className="space-y-4">
          <div>
            <label className="block text-sm text-gray-700 mb-1">Логин или email</label>
            <input
              type="text"
              value={loginValue}
              onChange={(e) => setLoginValue(e.target.value)}
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              autoFocus
              autoComplete="username"
              spellCheck={false}
            />
          </div>
          <div>
            <label className="block text-sm text-gray-700 mb-1">Пароль</label>
            <input
              type="password"
              value={passwordValue}
              onChange={(e) => setPasswordValue(e.target.value)}
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              autoComplete="current-password"
            />
          </div>
          {error && <div className="text-sm text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
          <button
            type="submit"
            disabled={submitting || !loginValue.trim() || !passwordValue}
            className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 text-white text-sm font-medium rounded px-3 py-2 transition"
          >
            {submitting ? 'Вход...' : 'Войти'}
          </button>
        </form>

        <div className="mt-4 border-t pt-4">
          <button
            type="button"
            onClick={() => setForgotOpen((v) => !v)}
            className="w-full rounded border px-3 py-2 text-sm"
          >
            {forgotOpen ? 'Скрыть восстановление пароля' : 'Забыли пароль?'}
          </button>
          {forgotOpen && (
            <form onSubmit={onForgot} className="mt-3 space-y-2">
              <input
                type="text"
                value={forgotValue}
                onChange={(e) => setForgotValue(e.target.value)}
                placeholder="Логин или email"
                className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
              />
              <button type="submit" className="w-full rounded border px-3 py-2 text-sm">
                Отправить ссылку
              </button>
              {forgotMsg && <div className={`text-xs ${forgotOk ? 'text-green-600' : 'text-red-600'}`}>{forgotMsg}</div>}
            </form>
          )}
        </div>

        {resetToken && (
          <form onSubmit={onReset} className="mt-4 border-t pt-4 space-y-2">
            <div className="text-sm font-medium">Новый пароль</div>
            <input
              type="password"
              value={resetPassword}
              onChange={(e) => setResetPassword(e.target.value)}
              placeholder="Минимум 8 символов, Aa + цифра"
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
            />
            <input
              type="password"
              value={resetPasswordConfirm}
              onChange={(e) => setResetPasswordConfirm(e.target.value)}
              placeholder="Подтвердите пароль"
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
            />
            <button type="submit" className="w-full rounded bg-blue-600 text-white px-3 py-2 text-sm">
              Сменить пароль
            </button>
            {resetMsg && <div className="text-xs text-gray-600">{resetMsg}</div>}
          </form>
        )}
      </div>
    </div>
  )
}
