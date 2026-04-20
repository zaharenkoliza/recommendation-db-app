export interface Student {
  id: number;
  name: string;
  group_id?: number;
}

export interface RecommendedDiscipline {
  id: number;
  name: string;
  prerequisite_count: number;
}

export interface RecommendationResponse {
  student_id: number;
  recommended_disciplines: RecommendedDiscipline[];
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
