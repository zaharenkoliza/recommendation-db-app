import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Loader2, AlertCircle, Layers, ChevronRight, TrendingUp } from 'lucide-react';
import { motion } from 'framer-motion';

export const TracksList = () => {
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (!id) return;
    api.getTracks(Number(id))
      .then(setData)
      .catch(err => {
        setError('Не удалось загрузить треки');
        console.error(err);
      })
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p>Загрузка треков...</p>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div>
        <button onClick={() => navigate(`/admin/curricula/${id}`)} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
          <ArrowLeft size={18} /> Назад к плану
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

  const { info, tracks } = data;

  return (
    <div>
      <button onClick={() => navigate(`/admin/curricula/${id}`)} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
        <ArrowLeft size={18} /> Назад к плану
      </button>

      <div className="flex items-center gap-3 mb-2">
        <Layers className="text-[#1846C7]" size={28} />
        <h1>Треки обучения</h1>
      </div>
      <p className="text-[#5C5C5C] mb-8">
        Выбор специализаций для учебного плана: <span className="text-[#333] font-semibold">{info?.name} ({info?.year})</span>
      </p>

      {tracks.length > 0 ? (
        <div className="grid gap-4">
          {tracks.map((t: any, i: number) => (
            <motion.div
              key={t.id}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.1 }}
              className="light-card flex items-center justify-between hover:border-[#1846C7] transition-colors group cursor-default"
            >
              <div className="flex items-center gap-4">
                <div className="w-10 h-10 rounded-full bg-blue-50 flex items-center justify-center text-[#1846C7] font-bold">
                  {t.number}
                </div>
                <div>
                  <h3 className="font-bold text-[#333] group-hover:text-[#1846C7] transition-colors">{t.name}</h3>
                  <p className="text-xs text-[#5C5C5C]">ID: {t.id} • Лимит выбора: {t.count_limit || 'Без ограничений'}</p>
                </div>
              </div>
              <div className="flex items-center gap-6">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    navigate(`/admin/tracks/${t.id}/visualize`);
                  }}
                  className="flex items-center gap-2 px-3 py-1.5 bg-blue-50 text-[#1846C7] rounded-lg hover:bg-blue-100 transition-colors text-xs font-bold"
                >
                  <TrendingUp size={14} /> Визуализация
                </button>
                <ChevronRight size={20} className="text-gray-300 group-hover:text-[#1846C7] transition-colors" />
              </div>
            </motion.div>
          ))}
        </div>
      ) : (
        <div className="light-card border-dashed py-20 text-center text-[#5C5C5C]">
          <Layers size={48} className="mx-auto mb-4 opacity-30" />
          <h2 className="text-xl mb-2 text-[#333]">Треки не найдены</h2>
          <p>В данном учебном плане еще не создано ни одного трека специализации.</p>
        </div>
      )}
    </div>
  );
};
