import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { Loader2, AlertCircle, BookOpen, User } from 'lucide-react';
import { SectionItem } from '../../components/SectionItem';
import { useNavigate } from 'react-router-dom';

export const MyCurriculum = () => {
  const navigate = useNavigate();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.getMyCurriculum()
      .then(setData)
      .catch(err => {
        setError(err.response?.data?.detail || 'Не удалось загрузить ваш учебный план');
        console.error(err);
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p className="font-bold uppercase tracking-widest text-xs">Загрузка вашего учебного плана...</p>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="light-card border-red-500 bg-red-50 flex items-center gap-4 p-6">
        <AlertCircle className="text-red-500" size={32} />
        <div>
          <h4 className="font-bold text-red-700">Упс! Что-то пошло не так</h4>
          <p className="text-sm text-red-600">{error}</p>
        </div>
      </div>
    );
  }

  const { info, sections, disciplines_flat = [] } = data;
  const degreeLabel = info.degree === 'bachelor' ? 'Бакалавриат' : 'Магистратура';

  return (
    <div className="max-w-5xl mx-auto">
      {/* Header Area */}
      <div className="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div>
          <div className="flex items-center gap-2 mb-3">
             <span className={`text-[10px] px-2 py-0.5 rounded-full font-black uppercase tracking-wider ${
              info.degree === 'bachelor' ? 'bg-blue-100 text-blue-700' : 'bg-purple-100 text-purple-700'
            }`}>{degreeLabel}</span>
            <span className="text-[10px] px-2 py-0.5 rounded-full bg-gray-100 text-[#5C5C5C] font-black uppercase tracking-wider">{info.year} год набора</span>
          </div>
          <h1 className="text-4xl font-black text-[#1F1F1F] leading-tight tracking-tight">{info.name}</h1>
          <div className="flex items-center gap-4 mt-4 text-[#5C5C5C]">
            <div className="flex items-center gap-1.5 bg-white px-3 py-1.5 rounded-xl border border-gray-100 shadow-sm">
              <User size={14} className="text-[#1846C7]" />
              <span className="text-sm font-bold">Руководитель: <span className="text-[#1F1F1F]">{info.head}</span></span>
            </div>
            <div className="text-sm font-bold opacity-60">ID ИСУ: {info.id_isu}</div>
          </div>
        </div>
        
        <div className="hidden lg:block">
           <BookOpen size={120} className="text-[#1846C7] opacity-5 -mb-4 -mr-4" />
        </div>
      </div>

      <div className="h-px w-full bg-gradient-to-r from-gray-200 via-transparent to-transparent mb-12" />

      {/* Sections Container */}
      <div className="grid gap-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <div className="w-2 h-8 bg-[#1846C7] rounded-full" />
            <h2 className="text-xl font-black text-[#1F1F1F]">Структура обучения</h2>
          </div>
          
          {/* Quick jump dropdown */}
          {disciplines_flat.length > 0 && (
            <div className="flex items-center gap-3">
              <span className="text-sm font-bold text-[#5C5C5C]">Быстрый поиск дисциплины:</span>
              <select 
                className="px-4 py-2 bg-white border border-gray-200 rounded-xl text-sm font-medium shadow-sm outline-none focus:ring-2 focus:ring-[#1846C7]/20"
                onChange={(e) => {
                  if (e.target.value) {
                    navigate(`/admin/disciplines/${e.target.value}/graph`);
                    e.target.value = "";
                  }
                }}
                defaultValue=""
              >
                <option value="" disabled>Выберите дисциплину...</option>
                {disciplines_flat.sort((a: any, b: any) => a.name.localeCompare(b.name)).map((d: any) => (
                  <option key={d.id} value={d.id}>{d.name}</option>
                ))}
              </select>
            </div>
          )}
        </div>

        {sections.length > 0 ? (
          <div className="grid gap-2">
            {sections.map((s: any) => (
              <SectionItem key={s.id} section={s} />
            ))}
          </div>
        ) : (
          <div className="light-card border-dashed py-20 text-center text-[#5C5C5C] bg-white">
            <BookOpen size={48} className="mx-auto mb-4 opacity-20 text-[#1846C7]" />
            <p className="text-lg font-bold text-[#333]">Учебный план пока не заполнен</p>
            <p className="text-sm">Обратитесь в деканат за подробной информацией.</p>
          </div>
        )}
      </div>

      {/* Footer hint */}
      <div className="mt-12 p-6 bg-blue-50/50 rounded-3xl border border-blue-100 flex items-start gap-4">
        <AlertCircle className="text-[#1846C7] mt-1 flex-shrink-0" size={20} />
        <div>
          <p className="text-sm font-bold text-[#1846C7] mb-1">Обратите внимание</p>
          <p className="text-xs text-[#5C5C5C] leading-relaxed">
            Это официальный учебный план вашей образовательной программы. Список дисциплин может меняться в зависимости от выбранного трека специализации и доступных элективов. Для изменения трека обратитесь к руководителю программы.
          </p>
        </div>
      </div>
    </div>
  );
};
