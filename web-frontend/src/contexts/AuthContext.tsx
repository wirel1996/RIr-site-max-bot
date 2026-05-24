import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { useLocation } from 'react-router-dom'
import { authApi, type AuthUser } from '../api/auth'

type AuthState =
  | { status: 'loading'; user: null }
  | { status: 'anon'; user: null }
  | { status: 'authed'; user: AuthUser }

type AuthContextValue = {
  state: AuthState
  user: AuthUser | null
  canDelete: boolean
  login: (login: string, password: string) => Promise<AuthUser>
  logout: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading', user: null })
  const location = useLocation()

  // На старте узнаём, кто залогинен.
  useEffect(() => {
    let cancelled = false
    authApi
      .me()
      .then(({ user }) => {
        if (!cancelled) setState({ status: 'authed', user })
      })
      .catch(() => {
        if (!cancelled) setState({ status: 'anon', user: null })
      })
    return () => {
      cancelled = true
    }
  }, [])

  // Сессия истекла — сбрасываем пользователя, чтобы App перешёл на /login.
  useEffect(() => {
    const handler = () => setState({ status: 'anon', user: null })
    window.addEventListener('auth:expired', handler)
    return () => window.removeEventListener('auth:expired', handler)
  }, [])

  const login = useCallback(async (login: string, password: string) => {
    const { user } = await authApi.login(login, password)
    setState({ status: 'authed', user })
    return user
  }, [])

  const logout = useCallback(async () => {
    try {
      await authApi.logout()
    } finally {
      setState({ status: 'anon', user: null })
    }
  }, [])

  useEffect(() => {
    if (state.status !== 'authed') return undefined

    const sendPing = () => {
      const page = `${location.pathname}${location.search}${location.hash}`
      authApi.ping(page).catch(() => {})
    }

    sendPing()
    const onVisible = () => {
      if (document.visibilityState === 'visible') sendPing()
    }
    window.addEventListener('focus', sendPing)
    document.addEventListener('visibilitychange', onVisible)

    return () => {
      window.removeEventListener('focus', sendPing)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [state.status, location.pathname, location.search, location.hash])

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      user: state.user,
      canDelete: state.user?.role === 'admin',
      login,
      logout,
    }),
    [state, login, logout],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be inside <AuthProvider>')
  return ctx
}
