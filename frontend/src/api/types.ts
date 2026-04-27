export interface Student {
  id: number;
  name: string;
  group_id?: string;
  track?: string;
  status?: string;
  curriculum?: string;
  course?: number;
}

export interface RecommendedDiscipline {
  id: number;
  name: string;
  prerequisite_count: number;
  prerequisite_names?: string[];
  reason?: string;
  is_debt?: boolean;
}

export interface ElectiveGroup {
  module_name: string;
  disciplines: RecommendedDiscipline[];
}

export interface RecommendationResponse {
  student_id: number;
  next_semester: number;
  mandatory: RecommendedDiscipline[];
  elective_groups: ElectiveGroup[];
}

export interface Discipline {
  id: number;
  name: string;
  discipline_name?: string; // from track-disciplines
}

export interface TrackDisciplinesResponse {
  track: string;
  disciplines: Discipline[];
}

export interface ProgressEntry {
  id: number;
  discipline_name: string;
  grade: number | null;
  status: 'Passed' | 'Failed' | 'Enrolled';
  attempt_number: number;
  updated_at: string | null;
}

export interface ProgressResponse {
  student_id: number;
  summary: {
    total: number;
    passed: number;
    failed: number;
    enrolled: number;
  };
  passed: ProgressEntry[];
  failed: ProgressEntry[];
  enrolled: ProgressEntry[];
}

export interface User {
  id: number;
  login: string;
  role: 'ADMIN' | 'STUDENT';
  student_id: number | null;
}

export interface LoginResponse {
  access_token: string;
  token_type: string;
  user: User;
}
