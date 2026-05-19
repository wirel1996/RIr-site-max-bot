import { api } from './client'

export type VolumeForm = {
  h: string
  v: string
  q: string
  t_vn: string
  v_podval: string
}

export const calcApi = {
  volume: (form: VolumeForm) =>
    api.post<{ text: string }>('/calc/volume', form),
}
