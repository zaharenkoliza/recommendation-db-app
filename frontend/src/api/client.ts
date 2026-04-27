import axios from 'axios';
import type { Student, RecommendationResponse, TrackDisciplinesResponse, ProgressResponse, LoginResponse } from './types';

const API_BASE_URL = 'http://localhost:8000';

console.log('[API] client.ts loading...');


const client = axios.create({
  baseURL: API_BASE_URL,
});

// Use a simpler interceptor registration
client.interceptors.response.use(
  (res) => res,
  (err) => {
    console.log('[API Interceptor] Error caught:', err.response?.status);
    if (err.response?.status === 401) {
      console.log('[API Interceptor] 401 Detected! Clearing session and redirecting...');
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      window.dispatchEvent(new Event('auth-change'));
      if (!window.location.pathname.includes('/login')) {
        window.location.href = '/login';
      }
    }
    return Promise.reject(err);
  }
);

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

  getMyCurriculum: async (): Promise<any> => {
    const { data } = await client.get('/student/curriculum');
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

  // ── CRUD: Curricula ────────────────────────
  createCurriculum: async (body: { id_isu: number; name: string; year: number; degree: string; head?: string }): Promise<any> => {
    const { data } = await client.post('/admin/curricula', body);
    return data;
  },

  updateCurriculum: async (idIsu: number, body: { name?: string; year?: number; degree?: string; head?: string }): Promise<any> => {
    const { data } = await client.put(`/admin/curricula/${idIsu}`, body);
    return data;
  },

  deleteCurriculum: async (idIsu: number): Promise<any> => {
    const { data } = await client.delete(`/admin/curricula/${idIsu}`);
    return data;
  },

  // ── CRUD: Tracks ───────────────────────────
  createTrack: async (body: { name: string; number: number; id_section: number; count_limit?: number }): Promise<any> => {
    const { data } = await client.post('/admin/tracks', body);
    return data;
  },

  updateTrack: async (trackId: number, body: { name?: string; number?: number; count_limit?: number }): Promise<any> => {
    const { data } = await client.put(`/admin/tracks/${trackId}/edit`, body);
    return data;
  },

  deleteTrack: async (trackId: number): Promise<any> => {
    const { data } = await client.delete(`/admin/tracks/${trackId}`);
    return data;
  },

  // ── CRUD: Disciplines ──────────────────────
  updateDiscipline: async (discId: number, body: { name?: string; comment?: string }): Promise<any> => {
    const { data } = await client.put(`/admin/disciplines/${discId}`, body);
    return data;
  },

  getDisciplineGraph: async (discId: number): Promise<{ nodes: any[]; edges: any[] }> => {
    const { data } = await client.get(`/admin/disciplines/${discId}/graph`);
    return data;
  },

  addPrerequisite: async (discipline_id: number, prerequisite_id: number): Promise<any> => {
    const { data } = await client.post('/admin/prerequisites', { discipline_id, prerequisite_id });
    return data;
  },

  deletePrerequisite: async (discipline_id: number, prerequisite_id: number): Promise<any> => {
    const { data } = await client.delete('/admin/prerequisites', { params: { discipline_id, prerequisite_id } });
    return data;
  },

  importCurriculum: async (body: any): Promise<any> => {
    const { data } = await client.post('/admin/import-curriculum', body);
    return data;
  },
};
