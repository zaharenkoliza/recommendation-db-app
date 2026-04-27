import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useParams } from 'react-router-dom';
import { ArrowLeft, Loader2, AlertCircle, Layers, BookOpen, GraduationCap } from 'lucide-react';
import { motion } from 'framer-motion';

export const TrackVisualization = () => {
  const { trackId } = useParams<{ trackId: string }>();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);


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
    <div className="min-h-screen pb-12">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-10">
        <div className="flex items-center gap-4">
          <button 
            onClick={() => window.history.back()} 
            className="p-2.5 hover:bg-gray-100 rounded-full transition-all active:scale-95 text-[#5C5C5C]"
          >
            <ArrowLeft size={24} />
          </button>
          <div>
            <div className="flex items-center gap-2 text-[12px] font-bold uppercase tracking-widest text-[#5C5C5C] mb-1">
              <Layers size={14} className="text-[#1846C7]" /> {curriculum.name} • {curriculum.year}
            </div>
            <h1 className="text-3xl font-black text-[#1F1F1F] tracking-tight">
              {track.name} <span className="text-[#1846C7]/30 text-xl">#{track.number}</span>
            </h1>
          </div>
        </div>
        
        <div className="flex items-center gap-3">
          <div className="flex flex-col items-end mr-4 border-r border-gray-200 pr-4">
            <span className="text-[10px] font-bold text-[#5C5C5C] uppercase">Всего дисциплин</span>
            <span className="text-xl font-black text-[#1846C7]">{disciplines_flat.length}</span>
          </div>
          <div className="bg-white shadow-sm border border-gray-100 p-1.5 rounded-xl flex gap-1">
            <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-blue-50 text-[10px] font-bold text-blue-700 uppercase">
              <div className="w-1.5 h-1.5 rounded-full bg-blue-500" /> Профиль
            </div>
            <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-gray-50 text-[10px] font-bold text-gray-500 uppercase">
              <div className="w-1.5 h-1.5 rounded-full bg-gray-400" /> Общие
            </div>
          </div>
        </div>
      </div>

      <div className="relative">
        {/* Background line behind semesters */}
        <div className="absolute top-5 left-0 right-0 h-0.5 bg-gray-100 -z-10" />
        
        <div className="overflow-x-auto pb-10 -mx-8 px-8 scrollbar-hide">
          <div className="flex gap-10" style={{ minWidth: semesterNumbers.length * 320 }}>
            {semesterNumbers.map((semNum) => (
              <div key={semNum} className="flex-shrink-0 w-[300px]">
                {/* Semester Header */}
                <div className="mb-8 relative flex flex-col items-center">
                  <div className="w-12 h-12 rounded-2xl bg-[#1846C7] text-white flex items-center justify-center font-black text-xl shadow-xl shadow-blue-200 z-10 relative group cursor-default">
                    {semNum}
                    <div className="absolute -inset-1 bg-[#1846C7] rounded-2xl opacity-20 group-hover:scale-125 transition-transform" />
                  </div>
                  <div className="mt-3 text-[10px] font-black uppercase tracking-[0.2em] text-[#1846C7]">
                    Семестр
                  </div>
                </div>

                <div className="space-y-6">
                  {/* Major/Core Disciplines */}
                  <div className="space-y-3">
                    {semesters[semNum]
                      .filter(d => d.implementer === 'ФПИ и КТ')
                      .map((disc, i) => (
                        <motion.div
                          key={`${semNum}-${disc.id}-${i}`}
                          initial={{ opacity: 0, x: -20 }}
                          animate={{ opacity: 1, x: 0 }}
                          transition={{ delay: i * 0.05 + semNum * 0.1 }}
                          className="p-4 bg-white border-2 border-blue-100 rounded-2xl shadow-sm hover:shadow-xl hover:border-[#1846C7] transition-all group cursor-pointer relative overflow-hidden active:scale-[0.98]"
                        >
                          <div className="absolute top-0 left-0 w-1 h-full bg-[#1846C7] opacity-50 group-hover:w-2 transition-all" />
                          <p className="text-sm font-bold text-[#333] leading-snug mb-2 group-hover:text-[#1846C7]">{disc.name}</p>
                          <div className="flex items-center justify-between">
                            <span className="flex items-center gap-1 px-1.5 py-0.5 rounded bg-blue-50 text-[9px] text-[#1846C7] font-black uppercase">
                              <GraduationCap size={10} /> {disc.format || 'Очно'}
                            </span>
                            <span className="text-[9px] font-mono text-gray-300 group-hover:text-blue-300 transition-colors">ID:{disc.id}</span>
                          </div>
                        </motion.div>
                      ))}
                  </div>

                  {/* Separator icon */}
                  {semesters[semNum].some(d => d.implementer !== 'ФПИ и КТ') && (
                    <div className="flex justify-center opacity-20">
                      <div className="w-1 h-1 rounded-full bg-gray-400 mx-0.5" />
                      <div className="w-1 h-1 rounded-full bg-gray-400 mx-0.5" />
                      <div className="w-1 h-1 rounded-full bg-gray-400 mx-0.5" />
                    </div>
                  )}

                  {/* Common Disciplines */}
                  <div className="space-y-3">
                    {semesters[semNum]
                      .filter(d => d.implementer !== 'ФПИ и КТ')
                      .map((disc, i) => (
                        <motion.div
                          key={`${semNum}-${disc.id}-common-${i}`}
                          initial={{ opacity: 0, scale: 0.95 }}
                          animate={{ opacity: 1, scale: 1 }}
                          transition={{ delay: i * 0.05 + semNum * 0.1 }}
                          className="p-4 bg-gray-50/50 border border-gray-200 rounded-2xl hover:bg-white hover:border-gray-300 hover:shadow-lg transition-all group cursor-default"
                        >
                          <p className="text-[13px] font-semibold text-[#5C5C5C] leading-snug mb-2 group-hover:text-[#333]">{disc.name}</p>
                          <div className="flex items-center justify-between opacity-60">
                            <div className="flex items-center gap-1.5">
                              <BookOpen size={10} className="text-gray-400" />
                              <span className="text-[9px] text-gray-500 font-bold uppercase truncate max-w-[120px]">
                                {disc.implementer || 'ИТМО'}
                              </span>
                            </div>
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
    </div>
  );
};

