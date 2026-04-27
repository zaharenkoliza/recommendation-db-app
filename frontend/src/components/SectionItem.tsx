import React, { useState } from 'react';
import { ChevronDown, ChevronRight, BookOpen, GitBranch } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { useNavigate } from 'react-router-dom';

interface SectionProps {
  section: any;
  depth?: number;
}

export const SectionItem: React.FC<SectionProps> = ({ section, depth = 0 }) => {
  const navigate = useNavigate();
  const [isOpen, setIsOpen] = useState(false);
  const childrenCount = (section.children?.length || 0) + (section.disciplines?.length || 0);
  const hasChildren = childrenCount > 0;

  return (
    <div className="mb-2 relative z-0">
      <div 
        onClick={() => setIsOpen(!isOpen)}
        className={`light-card flex items-center justify-between cursor-pointer transition-all ${
          isOpen ? 'border-[#1846C7] bg-blue-50/30' : 'hover:border-[#1846C7]/50'
        }`}
        style={{ marginLeft: depth * 20 }}
      >
        <div className="flex items-center gap-3 flex-1 min-w-0">
          <div className="flex items-center justify-center w-6 h-6 flex-shrink-0">
            {hasChildren ? (
              isOpen ? <ChevronDown size={18} className="text-[#1846C7]" /> : <ChevronRight size={18} className="text-[#5C5C5C]" />
            ) : (
              <div className="w-1.5 h-1.5 rounded-full bg-gray-300" />
            )}
          </div>
          
          <div className="w-8 h-8 rounded bg-blue-50 flex items-center justify-center text-[#1846C7] font-bold text-xs flex-shrink-0">
            {section.position}
          </div>
          
          <div className="flex-1 min-w-0">
            <p className="font-medium text-[#333] truncate">{section.module_name}</p>
            <p className="text-[10px] text-[#5C5C5C] uppercase tracking-wider mt-0.5">
              ID: {section.module_id} • {section.type_choose}
              {section.choose_count > 0 && ` • Выбор: ${section.choose_count}`}
              {hasChildren && ` • [${childrenCount} вложений]`}
            </p>
          </div>
        </div>
      </div>

      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="overflow-hidden"
          >
            <div className="pt-2">
              {/* Render Sub-sections */}
              {section.children?.map((child: any) => (
                <SectionItem key={child.id} section={child} depth={depth + 1} />
              ))}

              {/* Render Disciplines */}
              {section.disciplines?.map((disc: any) => (
                  <div 
                    key={disc.id} 
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-100 bg-gray-50/50 mb-2 transition-all hover:bg-white hover:border-blue-200 hover:shadow-md group"
                    style={{ marginLeft: (depth + 1) * 20 + 24 }}
                  >
                    <BookOpen size={14} className="text-gray-400 group-hover:text-[#1846C7] transition-colors" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-[#444] truncate group-hover:text-[#1f1f1f]">{disc.name}</p>
                      <p className="text-[10px] text-[#888]">RPD ID: {disc.id}</p>
                    </div>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        navigate(`/admin/disciplines/${disc.id}/graph`);
                      }}
                      className="p-1.5 rounded-lg bg-white border border-gray-100 text-gray-400 opacity-40 group-hover:opacity-100 hover:text-[#1846C7] hover:border-blue-200 transition-all shadow-sm"
                      title="Посмотреть связи"
                    >
                      <GitBranch size={12} />
                    </button>
                  </div>
              ))}
              
              {hasChildren && section.children?.length === 0 && section.disciplines?.length === 0 && (
                <div className="text-center py-4 text-xs text-[#888] italic" style={{ marginLeft: (depth + 1) * 20 }}>
                  Пустой раздел
                </div>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};
