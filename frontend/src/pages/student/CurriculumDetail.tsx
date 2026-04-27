import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Loader2, AlertCircle, BookOpen, User, GraduationCap } from 'lucide-react';
import { SectionItem } from '../../components/SectionItem';

export const StudentCurriculumDetail = () => {
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
        <button onClick={() => navigate('/curricula')} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
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

  // Collect all disciplines for quick search
  const collectDisciplines = (sectionList: any[]): any[] => {
    const result: any[] = [];
    for (const s of sectionList) {
      if (s.disciplines) result.push(...s.disciplines);
      if (s.children) result.push(...collectDisciplines(s.children));
    }
    return result;
  };
  const allDisciplines = collectDisciplines(sections);

  return (
    <div className="max-w-5xl mx-auto">
      <button onClick={() => navigate('/curricula')} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors font-medium">
        <ArrowLeft size={18} /> Назад к списку
      </button>

      {/* Header */}
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
          <GraduationCap size={120} className="text-[#1846C7] opacity-5 -mb-4 -mr-4" />
        </div>
      </div>

      <div className="h-px w-full bg-gradient-to-r from-gray-200 via-transparent to-transparent mb-12" />

      {/* Sections */}
      <div className="grid gap-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <div className="w-2 h-8 bg-[#1846C7] rounded-full" />
            <h2 className="text-xl font-black text-[#1F1F1F]">Структура плана</h2>
          </div>

          {allDisciplines.length > 0 && (
            <div className="flex items-center gap-3">
              <span className="text-sm font-bold text-[#5C5C5C]">Быстрый поиск:</span>
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
                {allDisciplines.sort((a: any, b: any) => a.name.localeCompare(b.name)).map((d: any) => (
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
            <p className="text-sm">Информация появится после заполнения данных администратором.</p>
          </div>
        )}
      </div>

      {/* Info hint */}
      <div className="mt-12 p-6 bg-blue-50/50 rounded-3xl border border-blue-100 flex items-start gap-4">
        <AlertCircle className="text-[#1846C7] mt-1 flex-shrink-0" size={20} />
        <div>
          <p className="text-sm font-bold text-[#1846C7] mb-1">Режим просмотра</p>
          <p className="text-xs text-[#5C5C5C] leading-relaxed">
            Вы просматриваете структуру учебного плана в режиме «только чтение». Раскройте модули, чтобы увидеть входящие дисциплины и подразделы. Для внесения изменений обратитесь к администратору системы.
          </p>
        </div>
      </div>
    </div>
  );
};
