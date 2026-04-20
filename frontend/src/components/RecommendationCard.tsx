import React from 'react';
import type { RecommendedDiscipline } from '../api/types';
import { BookOpen, CheckCircle2, Lock } from 'lucide-react';

interface Props {
  discipline: RecommendedDiscipline;
  index: number;
}

export const RecommendationCard: React.FC<Props> = ({ discipline }) => {
  return (
    <div className="light-card flex flex-col h-full gap-4 relative overflow-hidden group">
      <div className="flex items-start justify-between">
        <div className="p-2 bg-[#f0f4ff] rounded text-[#1846C7]">
          <BookOpen size={20} />
        </div>
        <div className="flex items-center gap-1.5 bg-[#E8F5E9] text-[#2E7D32] px-2 py-1 rounded text-[10px] font-bold uppercase tracking-wider">
          <CheckCircle2 size={12} strokeWidth={2} />
          Target
        </div>
      </div>

      <div className="mt-2">
        <p className="text-[10px] text-[#5C5C5C] uppercase tracking-wider font-bold mb-1">
          Дисциплина &middot; ID {discipline.id}
        </p>
        <h3 className="text-lg font-semibold leading-snug text-[#333] group-hover:text-[#1846C7] transition-colors">
          {discipline.name}
        </h3>
      </div>

      <div className="mt-auto pt-4 border-t border-[#E7E7E7] flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="flex -space-x-1">
             {[...Array(Math.min(3, discipline.prerequisite_count + 1))].map((_, i) => (
               <div 
                key={i} 
                className={`w-6 h-6 rounded-full border-2 border-white flex items-center justify-center text-[8px] font-bold ${
                  i === 0 ? 'bg-[#1846C7] text-white' : 'bg-[#E7E7E7] text-[#5C5C5C]'
                }`}
               >
                 {i === 0 ? '✓' : ''}
               </div>
             ))}
          </div>
          <div className="flex flex-col">
            <span className="text-xs text-[#5C5C5C] font-medium">
              Пререквизитов: {discipline.prerequisite_count}
            </span>
          </div>
        </div>
        
        <button className="p-2 rounded bg-[#f5f5f5] hover:bg-[#e0e0e0] text-[#5C5C5C] transition-colors" title="Заблокировано / Требует выполнения условий">
           <Lock size={16} />
        </button>
      </div>
    </div>
  );
};
