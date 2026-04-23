import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Loader2, AlertCircle, Layers, BookOpen } from 'lucide-react';
import { SectionItem } from '../../components/SectionItem';

export const CurriculumDetail = () => {
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (!id) return;
    api.getCurriculum(Number(id))
      .then(setData)
      .catch(err => {
        setError(err.response?.data?.detail || 'Не удалось загрузить план');
        console.error(err);
      })
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p>Загрузка учебного плана...</p>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div>
        <button onClick={() => navigate('/admin/curricula')} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
          <ArrowLeft size={18} /> Назад к списку
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

  const { info, sections } = data;
  const degreeLabel = info.degree === 'bachelor' ? 'Бакалавриат' : 'Магистратура';

  return (
    <div>
      <button onClick={() => navigate('/admin/curricula')} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
        <ArrowLeft size={18} /> Назад к списку
      </button>

      <div className="mb-6">
        <h1 className="mb-2">{info.name}</h1>
        <div className="flex gap-2">
           <span className={`text-xs px-2 py-1 rounded font-semibold ${
            info.degree === 'bachelor' ? 'bg-blue-100 text-blue-700' : 'bg-purple-100 text-purple-700'
          }`}>{degreeLabel}</span>
          <span className="text-xs px-2 py-1 rounded bg-gray-100 text-[#5C5C5C] font-medium">ИСУ {info.id_isu}</span>
          <span className="text-xs px-2 py-1 rounded bg-gray-100 text-[#5C5C5C] font-medium">{info.year} год</span>
        </div>
      </div>

      {/* Info cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <div className="light-card flex flex-col">
          <p className="text-sm text-[#5C5C5C] mb-1">Руководитель</p>
          <p className="text-lg font-semibold">{info.head}</p>
        </div>
        <div className="light-card flex items-center justify-between">
          <div>
            <p className="text-sm text-[#5C5C5C] mb-1">Действия</p>
            <button
              onClick={() => navigate(`/admin/tracks/${info.id_isu}`)}
              className="px-4 py-2 bg-[#1846C7] text-white rounded-lg hover:bg-[#1338a0] transition-colors flex items-center gap-2 text-sm font-medium"
            >
              <Layers size={16} /> Перейти к трекам
            </button>
          </div>
          <Layers size={40} className="text-[#1846C7] opacity-10" />
        </div>
      </div>

      {/* Sections */}
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-2xl">Структура плана</h2>
        <p className="text-xs text-[#5C5C5C]">Нажмите на модуль, чтобы раскрыть его состав</p>
      </div>

      {sections.length > 0 ? (
        <div className="grid gap-1">
          {sections.map((s: any) => (
            <SectionItem key={s.id} section={s} />
          ))}
        </div>
      ) : (
        <div className="light-card border-dashed py-12 text-center text-[#5C5C5C]">
          <BookOpen size={36} className="mx-auto mb-3 opacity-40" />
          <p>Учебный план пока пуст</p>
        </div>
      )}
    </div>
  );
};

