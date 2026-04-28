# Prerequisite Generation Algorithm (Smart v2)

The current system uses a hybrid approach to build the discipline dependency graph, balancing structural curricula data with semantic meaning.

## 1. Structural Candidate Pool
We first identify all potential pairs `(D1, D2)` from the curriculum database where:
- Both disciplines belong to the **same curriculum**.
- Both belong to **mandatory modules** (`type_choose = 'все'`).
- `D1` belongs to a section that comes **before** `D2` in the same parent branch.

## 2. Semantic Filtering (The "Cool" Logic)
To prevent "noise" (e.g., History depending on Math just because it was in the previous semester), we apply a **Semantic Filter**:
- **Jaccard Similarity**: We tokenize discipline names and calculate the overlap of significant words. If the similarity score is `> 0.25`, the link is kept.
- **Sequence Matching**: We detect patterns like "Part 1" -> "Part 2" or shared prefixes (e.g., "Web..." -> "Web...").
- **Exclusion**: Unrelated subjects in sequential modules are automatically discarded.

## 3. Transitive Reduction
To keep the graph clean and prevent redundant links (e.g., if A -> B and B -> C, then A -> C is redundant), we perform **Transitive Reduction**. This removes "shortcuts" and preserves only the direct logical dependencies.

## 4. Manual Overrides
Admins can manually add or remove prerequisites via the **Discipline Graph Management** UI.
- **Manual links** are always preserved and have higher priority in recommendations.
- **Automatic links** are recalculated whenever the `build_smart_prerequisites.py` script is run.

## 5. Result
This algorithm reduced the auto-generated links from **16,072** (noise) to **28** (high-quality semantic dependencies), making the recommendation graph much more readable and professional.
