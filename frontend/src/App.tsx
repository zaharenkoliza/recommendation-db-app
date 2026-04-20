import { useState, useEffect } from 'react';
import { api } from './api/client';
import type { Student, RecommendedDiscipline } from './api/types';
import { StudentSelector } from './components/StudentSelector';
import { RecommendationCard } from './components/RecommendationCard';
import { LayoutDashboard, Sparkles, AlertCircle, Loader2 } from 'lucide-react';
import { AnimatePresence, motion } from 'framer-motion';

function App() {
  const [selectedStudent, setSelectedStudent] = useState<Student | null>(null);
  const [recommendations, setRecommendations] = useState<RecommendedDiscipline[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (selectedStudent) {
      setLoading(true);
      setError(null);
      api.getRecommendations(selectedStudent.id)
        .then(res => {
          setRecommendations(res.recommended_disciplines);
          setLoading(false);
        })
        .catch(err => {
          console.error(err);
          setError('Failed to fetch recommendations. Is the backend running?');
          setLoading(false);
        });
    }
  }, [selectedStudent]);

  return (
    <div className="flex min-h-screen">
      {/* Sidebar matching parent application layout */}
      <aside className="fixed w-[250px] h-full p-4 border-r border-[#E7E7E7] bg-white z-20">
        <div className="mb-8 font-bold text-2xl text-[#333] px-2 mt-4">
          SMART REC
        </div>
        <ul className="grid gap-2">
          <li className="p-2">
            <a href="#" className="flex gap-2 text-[#1846C7] font-medium text-[16px] leading-[24px]">
              <LayoutDashboard size={20} />
              Recommendations
            </a>
          </li>
          {/* Other dummy links for visual consistency */}
          <li className="p-2">
            <a href="#" className="flex gap-2 text-[#5C5C5C] font-normal text-[16px] leading-[24px]">
              <Sparkles size={20} />
              Analysis
            </a>
          </li>
        </ul>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 ml-[280px] mt-[40px] mr-[40px] mb-[40px]">
        <h1>Умные Рекомендации</h1>

        <div className="mb-10 max-w-md">
          <StudentSelector onSelect={setSelectedStudent} />
        </div>

        <AnimatePresence mode="wait">
          {!selectedStudent ? (
            <motion.div 
              key="empty"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              className="py-20 text-center text-[#5C5C5C]"
            >
              <LayoutDashboard size={48} className="mx-auto mb-4 opacity-50" />
              <h2 className="text-xl mb-2 text-[#333]">Выберите студента</h2>
              <p>Для отображения персональных рекомендаций необходимо выбрать студента из списка.</p>
            </motion.div>
          ) : (
            <motion.div 
              key="content"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="space-y-8"
            >
              {/* Stats */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                 <div className="light-card flex flex-col">
                    <p className="text-sm text-[#5C5C5C] mb-1">Доступно курсов</p>
                    <p className="text-3xl font-bold text-[#1846C7]">{recommendations.length}</p>
                 </div>
                 <div className="light-card flex flex-col">
                    <p className="text-sm text-[#5C5C5C] mb-1">Группа</p>
                    <p className="text-3xl font-bold">{selectedStudent.group_id || 'Нет данных'}</p>
                 </div>
                 <div className="light-card flex flex-col border-l-4 border-l-[#1846C7]">
                    <p className="text-sm text-[#5C5C5C] mb-1">Трек обучения</p>
                    <p className="text-xl font-bold mt-auto">Программная инженерия</p>
                 </div>
              </div>

              {/* Recommendations List */}
              <div>
                <h2 className="text-2xl mb-6 flex items-center gap-3">
                  Рекомендуемые дисциплины
                </h2>

                {loading ? (
                  <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
                    <Loader2 className="animate-spin text-[#1846C7]" size={40} />
                    <p>Анализ графа...</p>
                  </div>
                ) : error ? (
                  <div className="light-card border-red-500 bg-red-50 flex items-center gap-4 p-6">
                    <AlertCircle className="text-red-500" size={32} />
                    <div>
                       <h4 className="font-bold text-red-700">Ошибка сервера</h4>
                       <p className="text-sm text-red-600">{error}</p>
                    </div>
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    {recommendations.length > 0 ? (
                      recommendations.map((rec, index) => (
                        <RecommendationCard key={rec.id} discipline={rec} index={index} />
                      ))
                    ) : (
                      <div className="col-span-full py-16 text-center light-card border-dashed">
                        <p className="text-[#5C5C5C]">Нет доступных рекомендаций для данного студента.</p>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </main>
    </div>
  );
}

export default App;
