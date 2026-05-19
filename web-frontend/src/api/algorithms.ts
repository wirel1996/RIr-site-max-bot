import { api } from './client'

export type AlgorithmListItem = {
  key: string
  title: string
  steps_count: number
}

export type AlgorithmStep = {
  title: string
  text: string
}

export type AlgorithmDetail = {
  key: string
  title: string
  steps: AlgorithmStep[]
}

export type DeviceNode = {
  title: string
  text?: string
  children?: DeviceNode[]
}

export const algorithmsApi = {
  list: () => api.get<{ items: AlgorithmListItem[] }>('/algorithms'),
  detail: (key: string) => api.get<AlgorithmDetail>(`/algorithms/${encodeURIComponent(key)}`),
  devicesTree: () => api.get<{ tree: DeviceNode }>('/devices'),
}
