import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Loader2, AlertCircle, Layers, BookOpen, GraduationCap, Info } from 'lucide-react';
import { motion } from 'framer-motion';

export const TrackVisualization = () => {
  const { trackId } = useParams<{ trackId: string }>();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (!trackId) return;
    api.getTrackDetails(Number(trackId))
      .then(setData)
      .catch(err => {
        setError('Не удалось загрузить визуализацию трека');
        console.error(err);
      })
      .finally(() => setLoading(false));
  }, [trackId]);

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p>Генерация визуализации...</p>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div>
        <button onClick={() => window.history.back()} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
          <ArrowLeft size={18} /> Назад
        </button>
        <div className="light-card border-red-500 bg-red-50 flex items-center gap-4 p-6">
          <AlertCircle className="text-red-500" size={32} />
          <div>
            <h4 className="font-bold text-red-700">Ошибка</h4>
            <p className="text-sm text-red-600">{error}</p>
          </div>
        </div>
      </div>
    );
  }

  const { track, curriculum, disciplines_flat } = data;
  
  // Group disciplines by semester
  const semesters: Record<number, any[]> = {};
  disciplines_flat.forEach((disc: any) => {
    disc.semesters.forEach((sem: number) => {
      if (!semesters[sem]) semesters[sem] = [];
      semesters[sem].push(disc);
    });
  });

  const semesterNumbers = Object.keys(semesters).map(Number).sort((a, b) => a - b);

  return (
    <div className="min-h-screen">
      <div className="flex items-center justify-between mb-8">
        <div className="flex items-center gap-4">
          <button onClick={() => window.history.back()} className="p-2 hover:bg-gray-100 rounded-full transition-colors">
            <ArrowLeft size={24} />
          </button>
          <div>
            <div className="flex items-center gap-2 text-sm text-[#5C5C5C] mb-1">
              <Layers size={14} /> {curriculum.name} ({curriculum.year})
            </div>
            <h1 className="text-2xl font-bold text-[#1F1F1F]">
              Трек #{track.number}: {track.name}
            </h1>
          </div>
        </div>
        <div className="bg-blue-50 text-[#1846C7] px-4 py-2 rounded-lg flex items-center gap-2 border border-blue-100">
          <Info size={18} />
          <span className="text-sm font-medium">Визуализация специализации</span>
        </div>
      </div>

      <div className="overflow-x-auto pb-8 -mx-8 px-8">
        <div className="flex gap-8" style={{ minWidth: semesterNumbers.length * 300 }}>
          {semesterNumbers.map((semNum) => (
            <div key={semNum} className="flex-shrink-0 w-[300px]">
              <div className="mb-6 flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-[#1846C7] text-white flex items-center justify-center font-bold text-lg shadow-lg shadow-blue-200">
                  {semNum}
                </div>
                <div className="h-px flex-1 bg-gray-200" />
                <span className="text-xs uppercase tracking-widest font-bold text-[#5C5C5C]">семестр</span>
              </div>

              <div className="space-y-4">
                {/* Major/Core Disciplines */}
                <div className="space-y-2">
                  <h4 className="text-[10px] uppercase font-bold text-blue-600 mb-2 px-1">Профильные дисциплины</h4>
                  {semesters[semNum]
                    .filter(d => d.implementer === 'ФПИ и КТ')
                    .map((disc, i) => (
                      <motion.div
                        key={`${semNum}-${disc.id}-${i}`}
                        initial={{ opacity: 0, y: 10 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ delay: i * 0.05 }}
                        className="p-3 bg-white border border-blue-100 rounded-xl shadow-sm hover:shadow-md hover:border-blue-300 transition-all group cursor-default"
                      >
                        <p className="text-sm font-medium text-[#333] leading-tight mb-1 group-hover:text-[#1846C7]">{disc.name}</p>
                        <div className="flex items-center justify-between">
                          <span className="text-[9px] text-blue-500 font-bold uppercase">{disc.format || 'Очно'}</span>
                          <span className="text-[9px] text-gray-400">ID: {disc.id}</span>
                        </div>
                      </motion.div>
                    ))}
                </div>

                {/* Common Disciplines */}
                <div className="pt-4 border-t border-dashed border-gray-200 space-y-2">
                  <h4 className="text-[10px] uppercase font-bold text-gray-400 mb-2 px-1">Общие дисциплины</h4>
                  {semesters[semNum]
                    .filter(d => d.implementer !== 'ФПИ и КТ')
                    .map((disc, i) => (
                      <motion.div
                        key={`${semNum}-${disc.id}-common-${i}`}
                        initial={{ opacity: 0, y: 10 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ delay: i * 0.05 }}
                        className="p-3 bg-gray-50 border border-gray-200 rounded-xl hover:bg-white transition-all group"
                      >
                        <p className="text-sm font-medium text-[#5C5C5C] leading-tight mb-1 group-hover:text-[#333]">{disc.name}</p>
                        <div className="flex items-center justify-between opacity-60">
                          <span className="text-[9px] text-gray-500">{disc.implementer || 'ИТМО'}</span>
                          <span className="text-[9px] text-gray-400">#{disc.id}</span>
                        </div>
                      </motion.div>
                    ))}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
