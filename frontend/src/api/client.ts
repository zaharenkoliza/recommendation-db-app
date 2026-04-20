import axios from 'axios';
import type { Student, RecommendationResponse, TrackDisciplinesResponse } from './types';

const API_BASE_URL = 'http://localhost:8000';

const client = axios.create({
  baseURL: API_BASE_URL,
});

export const api = {
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
  }
};
