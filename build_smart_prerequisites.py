import json
import subprocess
import re
from collections import defaultdict

def run_psql(query):
    # Using a local scratch file
    query_file = "scratch_query.sql"
    with open(query_file, 'w', encoding='utf-8') as f:
        f.write(query)
    
    cmd = f'docker exec -i itmo_db psql -U postgres -d itmo_db -t -f -'
    # Pipe the file content into the command
    result = subprocess.run(cmd, input=query, shell=True, capture_output=True, text=True, encoding='utf-8')
    
    if result.returncode != 0:
        print(f"PSQL Error: {result.stderr}")
        return []
    return [line.strip() for line in result.stdout.split('\n') if line.strip()]

def get_disciplines():
    lines = run_psql("SELECT id, name FROM s335141.disciplines")
    discs = {}
    for line in lines:
        parts = line.split('|')
        if len(parts) == 2:
            try:
                id_ = int(parts[0].strip())
                name = parts[1].strip()
                discs[id_] = name
            except: continue
    return discs

def get_word_set(text):
    text = text.lower()
    text = re.sub(r'[^\w\s]', ' ', text)
    # Stop words (simple list for Russian)
    stop_words = {'как', 'для', 'это', 'был', 'была', 'оно', 'они', 'и', 'в', 'на', 'с', 'по', 'об', 'от'}
    words = set(w for w in text.split() if len(w) > 2 and w not in stop_words)
    return words

def jaccard_similarity(s1, s2):
    if not s1 or not s2: return 0
    intersection = s1.intersection(s2)
    union = s1.union(s2)
    return len(intersection) / len(union)

def main():
    print("Starting Smart Prerequisite Analysis...")
    
    disciplines = get_disciplines()
    if not disciplines:
        print("No disciplines found. Check DB connection.")
        return
        
    fingerprints = {id_: get_word_set(name) for id_, name in disciplines.items()}
    
    print("Step 1: Fetching structural candidates from DB...")
    query = """
    SELECT DISTINCT r1.id_discipline, r2.id_discipline
    FROM s335141.sections s1
    JOIN s335141.sections s2 ON s1.id_curricula = s2.id_curricula 
      AND s1.id_parent_section IS NOT DISTINCT FROM s2.id_parent_section
      AND s2.position > s1.position
    JOIN s335141.modules m1 ON s1.id_module = m1.id_isu
    JOIN s335141.modules m2 ON s2.id_module = m2.id_isu
    JOIN s335141.disciplines_in_modules dim1 ON dim1.id_module = m1.id_isu
    JOIN s335141.rpd r1 ON dim1.id_rpd = r1.id_isu
    JOIN s335141.disciplines_in_modules dim2 ON dim2.id_module = m2.id_isu
    JOIN s335141.rpd r2 ON dim2.id_rpd = r2.id_isu
    WHERE m1.type_choose = 'все'
      AND r1.id_discipline IS NOT NULL AND r2.id_discipline IS NOT NULL
      AND r1.id_discipline <> r2.id_discipline;
    """
    
    candidate_lines = run_psql(query)
    candidates = []
    for line in candidate_lines:
        if '|' not in line: continue
        parts = line.split('|')
        try:
            candidates.append((int(parts[0].strip()), int(parts[1].strip())))
        except: continue

    print(f"Found {len(candidates)} structural candidates.")

    print("Step 2: Filtering by semantic similarity and subject matching...")
    final_links = []
    
    for d1, d2 in candidates:
        if d1 not in fingerprints or d2 not in fingerprints: continue
        
        sim = jaccard_similarity(fingerprints[d1], fingerprints[d2])
        name1, name2 = disciplines[d1], disciplines[d2]
        
        is_sequence = False
        # Match "Part 1" -> "Part 2" or shared prefix
        if name1[:8].lower() == name2[:8].lower():
            is_sequence = True
        elif any(token in name2.lower() for token in ["часть 2", "часть 3", "продвинутый", "углубленный"]):
             if name1[:6].lower() == name2[:6].lower():
                 is_sequence = True

        # COOL LOGIC: 
        # Only link if there's semantic overlap OR they are within the SAME module branch and VERY close
        if sim > 0.25 or is_sequence:
            final_links.append((d2, d1)) 

    print(f"Filtered down to {len(final_links)} semantic links.")

    print("Step 3: Applying Transitive Reduction...")
    adj = defaultdict(set)
    for d, p in final_links:
        adj[d].add(p)

    def has_path(start, end, target_to_skip, visited, d_global):
        if start == end: return True
        visited.add(start)
        for neighbor in adj[start]:
            if neighbor == target_to_skip and start == d_global: # skip the direct link only at the first level
                continue
            if neighbor not in visited:
                if has_path(neighbor, end, target_to_skip, visited, d_global):
                    return True
        return False

    reduced_links = []
    for d, p in final_links:
        if not has_path(d, p, p, set(), d):
            reduced_links.append((d, p))

    print(f"Final reduced links: {len(reduced_links)}")

    print("Step 4: Updating Database...")
    run_psql("DELETE FROM s335141.discipline_prerequisites WHERE source = 'auto';")
    
    if reduced_links:
        values = [f"({d}, {p}, 'auto')" for d, p in reduced_links]
        for i in range(0, len(values), 500):
            chunk = values[i:i+500]
            run_psql(f"INSERT INTO s335141.discipline_prerequisites (discipline_id, prerequisite_id, source) VALUES {', '.join(chunk)} ON CONFLICT DO NOTHING;")

    print("Step 5: Syncing to Neo4j...")
    subprocess.run("py migrate.py", shell=True)
    
    print("\nSmart Analysis Complete!")

if __name__ == "__main__":
    main()
