import { useState, useEffect } from 'react';
import { Routes, Route, Navigate, useNavigate, useLocation } from 'react-router-dom';
import { api } from './api/client';
import type { Student, RecommendationResponse } from './api/types';
import { useAuth } from './context/AuthContext';
import { Login } from './pages/Login';
import { StudentSelector } from './components/StudentSelector';
import { RecommendationCard } from './components/RecommendationCard';
import { ProgressPage } from './components/ProgressPage';
import { LayoutDashboard, TrendingUp, AlertCircle, Loader2, LogOut, BookOpen, Library, GraduationCap } from 'lucide-react';

import { CurriculaList } from './pages/admin/CurriculaList';
import { CurriculumDetail } from './pages/admin/CurriculumDetail';
import { DisciplinesList } from './pages/admin/DisciplinesList';
import { TracksList } from './pages/admin/TracksList';
import { TrackVisualization } from './pages/admin/TrackVisualization';
import { DisciplineGraph } from './pages/admin/DisciplineGraph';
import { StudentCurriculaList } from './pages/student/CurriculaList';
import { StudentCurriculumDetail } from './pages/student/CurriculumDetail';

import React from 'react';

class ErrorBoundary extends React.Component<{children: React.ReactNode}, {hasError: boolean, error: any}> {
  constructor(props: any) {
    super(props);
    this.state = { hasError: false, error: null };
  }
  static getDerivedStateFromError(error: any) { return { hasError: true, error }; }
  render() {
    if (this.state.hasError) {
      return (
        <div className="p-10 bg-red-50 text-red-700 rounded-3xl border border-red-100 m-10">
          <h2 className="text-xl font-bold mb-2">Что-то пошло не так в интерфейсе</h2>
          <pre className="text-xs bg-red-100 p-4 rounded-lg overflow-auto max-h-[400px]">
            {this.state.error?.toString()}
            {"\n\nStack:\n"}
            {this.state.error?.stack}
          </pre>
          <button 
            onClick={() => window.location.reload()}
            className="mt-4 px-4 py-2 bg-red-600 text-white rounded-lg font-bold"
          >
            Перезагрузить страницу
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

/* ─── Sidebar Navigation Items ───────────────── */
const getSidebarItems = (isAdmin: boolean) => {
  if (isAdmin) {
    return [
      { path: '/', label: 'Рекомендации', icon: <LayoutDashboard size={20} /> },
      { path: '/progress', label: 'Мой прогресс', icon: <TrendingUp size={20} /> },
      { path: '/admin/curricula', label: 'Учебные планы', icon: <BookOpen size={20} /> },
      { path: '/admin/disciplines', label: 'Дисциплины', icon: <Library size={20} /> },
    ];
  }
  return [
    { path: '/progress', label: 'Мой прогресс', icon: <TrendingUp size={20} /> },
    { path: '/', label: 'Рекомендации', icon: <LayoutDashboard size={20} /> },
    { path: '/curricula', label: 'Учебные планы', icon: <GraduationCap size={20} /> },
  ];
};

function App() {
  const { isAuthenticated, isAdmin, user, logout, isInitializing } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [selectedStudent, setSelectedStudent] = useState<Student | null>(null);
  const [recommendationData, setRecommendationData] = useState<RecommendationResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (isAuthenticated && !isAdmin && user?.student_id) {
      api.getStudentDetails(user.student_id)
        .then(setSelectedStudent)
        .catch(console.error);
    }
  }, [isAuthenticated, isAdmin, user]);

  useEffect(() => {
    if (selectedStudent) {
      setLoading(true);
      setError(null);
      api.getRecommendations(selectedStudent.id)
        .then(res => {
          setRecommendationData(res);
          setLoading(false);
        })
        .catch(err => {
          console.error(err);
          setError('Не удалось загрузить рекомендации.');
          setLoading(false);
        });
    }
  }, [selectedStudent]);

  if (isInitializing) {
    return (
      <div className="h-screen w-screen flex flex-col items-center justify-center gap-4 bg-gray-50">
        <Loader2 className="animate-spin text-[#1846C7]" size={48} />
        <p className="text-sm font-bold text-[#5C5C5C] uppercase tracking-widest">Инициализация системы...</p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    );
  }

  const sidebarItems = getSidebarItems(!!isAdmin);

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  return (
    <ErrorBoundary>
      <div className="flex min-h-screen">
        <aside className="fixed w-[280px] h-full p-6 border-r border-[#E7E7E7] bg-white z-20 flex flex-col">
          <div className="mb-10 px-2 mt-2">
            <div className="font-bold text-2xl text-[#1846C7] tracking-tight">ITMO Constructor</div>
            <div className="text-[10px] text-gray-400 font-medium">Build 2026.04.27.4</div>
          </div>

          <div className="mb-6 px-2">
            <span className={`text-[11px] uppercase tracking-wider font-black px-2.5 py-1.5 rounded-lg ${
              isAdmin ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
            }`}>
              {isAdmin ? 'Администратор' : 'Студент'}
            </span>
          </div>

          <nav className="flex-1">
            <ul className="grid gap-2">
              {sidebarItems.map(item => (
                <li key={item.path}>
                  <button
                    onClick={() => navigate(item.path)}
                    className={`w-full flex gap-3 items-center px-4 py-3 rounded-xl text-[15px] leading-none transition-all ${
                      location.pathname === item.path || (item.path !== '/' && location.pathname.startsWith(item.path))
                        ? 'text-[#1846C7] font-bold bg-blue-50 shadow-sm shadow-blue-100/50'
                        : 'text-[#5C5C5C] font-medium hover:bg-gray-50'
                    }`}
                  >
                    <div className={(location.pathname === item.path || (item.path !== '/' && location.pathname.startsWith(item.path))) ? 'text-[#1846C7]' : 'text-gray-400'}>
                      {item.icon}
                    </div>
                    {item.label}
                  </button>
                </li>
              ))}
            </ul>
          </nav>

          <div className="mt-4 pt-6 border-t border-[#E7E7E7]">
            <div className="px-4 py-3 rounded-xl bg-gray-50 border border-gray-100 mb-4">
              <p className="text-sm font-bold text-[#1F1F1F] truncate">{user?.login}</p>
              <p className="text-xs text-[#5C5C5C] uppercase font-bold tracking-tighter opacity-70">{user?.role}</p>
            </div>
            <button
              onClick={handleLogout}
              className="w-full flex gap-3 items-center px-4 py-3 rounded-xl text-[14px] font-bold text-red-500 hover:bg-red-50 transition-all active:scale-95"
            >
              <LogOut size={18} />
              Выйти
            </button>
          </div>
        </aside>

        <main className="flex-1 ml-[280px] p-10 max-w-[1400px]">
          {isAdmin && (location.pathname === '/' || location.pathname === '/progress') && (
            <div className="mb-12">
              <h2 className="text-sm font-black uppercase tracking-widest text-[#5C5C5C] mb-4">Контроль успеваемости</h2>
              <StudentSelector onSelect={setSelectedStudent} />
            </div>
          )}

          <Routes>
            <Route path="/" element={
              <div className="space-y-8">
                {!selectedStudent ? (
                  <div className="py-24 text-center text-[#5C5C5C] bg-gray-50 rounded-3xl border-2 border-dashed border-gray-100">
                    <LayoutDashboard size={64} className="mx-auto mb-6 opacity-20 text-[#1846C7]" />
                    <h2 className="text-2xl font-bold mb-2 text-[#333]">
                      {isAdmin ? 'Выберите студента' : 'Загрузка профиля...'}
                    </h2>
                    <p className="max-w-xs mx-auto">
                      {isAdmin ? 'Для формирования персональных рекомендаций необходимо выбрать студента из базы.' : 'Мы загружаем ваши данные из системы ИСУ.'}
                    </p>
                  </div>
                ) : (
                  <>
                    <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 mb-10">
                      <div>
                        <div className="text-[11px] font-black uppercase tracking-[0.2em] text-[#1846C7] mb-2">Интеллектуальный помощник</div>
                        <h1 className="text-4xl font-black text-[#1F1F1F] tracking-tight">{selectedStudent.name}</h1>
                        <div className="flex items-center gap-2 mt-3">
                          <span className="px-3 py-1.5 bg-gray-100 text-[#5C5C5C] text-[11px] font-bold rounded-lg uppercase tracking-wider border border-gray-200">Группа {selectedStudent.group_id || '—'}</span>
                          <span className={`px-3 py-1.5 text-[11px] font-bold rounded-lg uppercase tracking-wider border ${
                            selectedStudent.status === 'Кандидат на отчисление' 
                              ? 'bg-red-50 text-red-600 border-red-100' 
                              : 'bg-green-50 text-green-600 border-green-100'
                          }`}>
                            {selectedStudent.status || 'Активен'}
                          </span>
                        </div>
                      </div>
                      <div className="flex items-center gap-3 px-5 py-4 bg-white shadow-xl shadow-blue-900/5 rounded-2xl border border-blue-50">
                        <div className="w-12 h-12 rounded-xl bg-[#1846C7] flex items-center justify-center text-white font-black text-lg shadow-lg shadow-blue-200">
                          {selectedStudent.name.charAt(0)}
                        </div>
                        <div>
                          <div className="text-[10px] font-bold text-gray-400 uppercase leading-none mb-1">ID ИСУ</div>
                          <div className="text-base font-black text-[#1F1F1F]">{selectedStudent.id}</div>
                        </div>
                      </div>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-6 mb-12">
                      <div className="light-card border-l-4 border-l-[#1846C7] bg-white">
                        <p className="text-[10px] font-bold text-[#5C5C5C] uppercase mb-1 opacity-60">Специализация</p>
                        <p className="text-[15px] font-black text-[#1F1F1F] leading-tight">{selectedStudent.track || 'Общий профиль'}</p>
                      </div>
                      <div className="light-card bg-white">
                        <p className="text-[10px] font-bold text-[#5C5C5C] uppercase mb-1 opacity-60">Учебный план</p>
                        <p className="text-[15px] font-black text-[#1F1F1F] leading-tight">{selectedStudent.curriculum || '—'}</p>
                      </div>
                      <div className="light-card bg-white">
                        <p className="text-[10px] font-bold text-[#5C5C5C] uppercase mb-1 opacity-60">Курс</p>
                        <p className="text-3xl font-black text-[#1846C7]">{selectedStudent.course || '—'}</p>
                      </div>
                      <div className="light-card bg-white">
                        <p className="text-[10px] font-bold text-[#5C5C5C] uppercase mb-1 opacity-60">Рекомендаций</p>
                        <p className="text-3xl font-black text-[#1846C7]">
                          {(recommendationData?.mandatory?.length ?? 0) + (recommendationData?.elective_groups?.reduce((acc, g) => acc + (g?.disciplines?.length ?? 0), 0) ?? 0)}
                        </p>
                      </div>
                      <div className="light-card bg-white">
                        <p className="text-[10px] font-bold text-[#5C5C5C] uppercase mb-1 opacity-60">Кредиты</p>
                        <p className="text-3xl font-black text-[#1F1F1F]">124</p>
                      </div>
                    </div>

                    <div className="flex items-center gap-3 mb-8">
                      <div className="h-px flex-1 bg-gray-100" />
                      <h2 className="text-[12px] font-black uppercase tracking-[0.3em] text-gray-300">Ваша траектория</h2>
                      <div className="h-px flex-1 bg-gray-100" />
                    </div>
                    
                    {loading ? (
                      <div className="py-24 text-center">
                        <Loader2 className="animate-spin mx-auto text-[#1846C7] mb-4" size={48} />
                        <p className="text-sm font-bold text-gray-400 uppercase tracking-widest">Анализ траектории...</p>
                      </div>
                    ) : error ? (
                      <div className="p-8 bg-red-50 rounded-3xl border border-red-100 flex gap-6 items-center">
                        <div className="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center text-red-600 flex-shrink-0">
                          <AlertCircle size={24} />
                        </div>
                        <div>
                          <h4 className="font-black text-red-900">Ошибка системы</h4>
                          <p className="text-red-700">{error}</p>
                        </div>
                      </div>
                    ) : (
                      <div className="space-y-12">
                        {/* Mandatory Section */}
                        {(recommendationData?.mandatory?.length ?? 0) > 0 && (
                          <div>
                            <h3 className="text-lg font-black text-[#1F1F1F] mb-6 flex items-center gap-3">
                              <span className="w-2 h-6 bg-[#1846C7] rounded-full" />
                              Обязательные дисциплины
                            </h3>
                            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                              {recommendationData?.mandatory?.map((rec, i) => (
                                rec && <RecommendationCard key={`mand-${rec.id || i}`} discipline={rec} index={i} />
                              ))}
                            </div>
                          </div>
                        )}

                        {/* Elective Groups Section */}
                        {recommendationData?.elective_groups?.map((group, idx) => (
                          <div key={`group-${idx}`} className="p-8 bg-blue-50/30 rounded-[32px] border border-blue-100/50">
                            <div className="flex items-center justify-between mb-8">
                              <div>
                                <h3 className="text-lg font-black text-[#1F1F1F]">{group?.module_name || 'Группа по выбору'}</h3>
                                <p className="text-sm text-blue-600 font-bold tracking-tight">Выберите одну или несколько дисциплин из этого блока</p>
                              </div>
                              <div className="px-4 py-2 bg-white rounded-xl border border-blue-100 text-xs font-black text-[#1846C7] uppercase tracking-widest shadow-sm">
                                Выборный блок
                              </div>
                            </div>
                            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                              {group?.disciplines?.map((rec, i) => (
                                rec && <RecommendationCard key={`elec-${rec.id || i}`} discipline={rec} index={i} />
                              ))}
                            </div>
                          </div>
                        ))}

                        {((recommendationData?.mandatory?.length ?? 0) === 0 && (recommendationData?.elective_groups?.length ?? 0) === 0) && recommendationData && (
                          <div className="py-24 text-center bg-gray-50 rounded-3xl border-2 border-dashed border-gray-100">
                            <p className="text-gray-400 font-bold">Нет доступных рекомендаций для текущей траектории.</p>
                          </div>
                        )}
                      </div>
                    )}
                  </>
                )}
              </div>
            } />
            
            <Route path="/progress" element={
              selectedStudent ? (
                <ProgressPage student={selectedStudent} />
              ) : (
                <div className="py-24 text-center text-[#5C5C5C] bg-gray-50 rounded-3xl border-2 border-dashed border-gray-100">
                  <TrendingUp size={64} className="mx-auto mb-6 opacity-20 text-[#1846C7]" />
                  <h2 className="text-2xl font-bold mb-2 text-[#333]">Прогресс обучения</h2>
                  <p>Выберите студента для просмотра детальной успеваемости.</p>
                </div>
              )
            } />

            <Route path="/curricula" element={<StudentCurriculaList />} />
            <Route path="/curricula/:id" element={<StudentCurriculumDetail />} />
            <Route path="/admin/disciplines/:id/graph" element={<DisciplineGraph />} />

            {isAdmin && (
              <>
                <Route path="/admin/curricula" element={<CurriculaList />} />
                <Route path="/admin/curricula/:id" element={<CurriculumDetail />} />
                <Route path="/admin/disciplines" element={<DisciplinesList />} />
                <Route path="/admin/tracks/:id" element={<TracksList />} />
                <Route path="/admin/tracks/:trackId/visualize" element={<TrackVisualization />} />
              </>
            )}
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>
      </div>
    </ErrorBoundary>
  );
}

export default App;
