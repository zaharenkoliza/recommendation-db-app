import axios from 'axios';
import type { Student, RecommendationResponse, TrackDisciplinesResponse, ProgressResponse, LoginResponse } from './types';

const API_BASE_URL = 'http://localhost:8000';

const client = axios.create({
  baseURL: API_BASE_URL,
});

client.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token && config.headers) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export const api = {
  login: async (login: string, password: string): Promise<LoginResponse> => {
    const { data } = await client.post<LoginResponse>('/auth/login', { login, password });
    if (data.access_token) {
      localStorage.setItem('token', data.access_token);
    }
    return data;
  },
  
  getStudents: async (): Promise<Student[]> => {
    const { data } = await client.get<Student[]>('/students');
    return data;
  },
  
  getStudentDetails: async (studentId: number): Promise<Student> => {
    const { data } = await client.get<Student>(`/students/${studentId}`);
    return data;
  },
  
  getRecommendations: async (studentId: number): Promise<RecommendationResponse> => {
    const { data } = await client.get<RecommendationResponse>(`/api/recommend/${studentId}`);
    return data;
  },
  
  getTrackDisciplines: async (trackName: string): Promise<TrackDisciplinesResponse> => {
    const { data } = await client.get<TrackDisciplinesResponse>(`/api/track-disciplines/${trackName}`);
    return data;
  },

  getStudentProgress: async (studentId: number): Promise<ProgressResponse> => {
    const { data } = await client.get<ProgressResponse>(`/students/${studentId}/progress`);
    return data;
  },

  // ── Admin API ──────────────────────────
  getCurricula: async (): Promise<any[]> => {
    const { data } = await client.get('/admin/curricula');
    return data;
  },

  getCurriculum: async (idIsu: number): Promise<any> => {
    const { data } = await client.get(`/admin/curricula/${idIsu}`);
    return data;
  },

  getDisciplines: async (): Promise<any[]> => {
    const { data } = await client.get('/admin/disciplines');
    return data;
  },

  getTracks: async (curriculumId: number): Promise<any> => {
    const { data } = await client.get(`/admin/tracks/${curriculumId}`);
    return data;
  },

  getTrackDetails: async (trackId: number): Promise<any> => {
    const { data } = await client.get(`/admin/tracks/${trackId}/details`);
    return data;
  },
};
