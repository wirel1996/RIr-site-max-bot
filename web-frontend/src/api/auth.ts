import { api } from './client'

export type AuthUser = {
  login: string
  name: string
  email?: string
  position?: string
  role: 'limited' | 'full' | 'admin' | 'water_payment'
  created_at?: number | null
  updated_at?: number | null
  last_login_at?: number | null
  last_seen_at?: number | null
  last_seen_page?: string
}

export const authApi = {
  me: () => api.get<{ user: AuthUser }>('/auth/me'),
  login: (login: string, password: string) =>
    api.post<{ user: AuthUser }>('/auth/login', { login, password }),
  updateProfile: (payload: { name?: string; email?: string; position?: string; password?: string }) =>
    api.patch<{ user: AuthUser }>('/auth/profile', payload),
  forgot: (loginOrEmail: string) =>
    api.post<{ ok: true }>('/auth/forgot', { login_or_email: loginOrEmail }),
  resetPassword: (token: string, password: string) =>
    api.post<{ ok: true }>('/auth/reset-password', { token, password }),
  ping: (page: string) =>
    api.post<{ ok: true; user?: AuthUser }>('/auth/ping', { page }),
  logoutAll: () => api.post<{ ok: true }>('/auth/logout-all'),
  logout: () => api.post<{ ok: true }>('/auth/logout'),
}
