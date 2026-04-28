from neo4j import GraphDatabase

def test_recommendations(student_id):
    driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))
    with driver.session() as session:
        query = """
        MATCH (s:Student {id: $student_id})
        MATCH (d:Discipline)
        WHERE NOT (s)-[:COMPLETED]->(d)
        
        OPTIONAL MATCH (s)-[debt_rel:HAS_DEBT]->(d)
        WITH s, d, debt_rel IS NOT NULL as is_debt
        
        OPTIONAL MATCH (d)-[:REQUIRES]->(req:Discipline)
        WITH s, d, is_debt, collect(req) as all_reqs
        WHERE is_debt OR all(r IN all_reqs WHERE (s)-[:COMPLETED]->(r))
        
        RETURN d.name as name, 
               d.id as id, 
               is_debt,
               size(all_reqs) as prerequisite_count,
               [r IN all_reqs WHERE r IS NOT NULL | r.name] as prerequisite_names
        ORDER BY is_debt DESC, size(all_reqs) DESC
        LIMIT 10
        """
        results = session.run(query, {"student_id": student_id})
        print(f"Recommendations for student {student_id}:")
        for record in results:
            reason = ""
            if record["is_debt"]:
                reason = "СРОЧНО: Академическая задолженность"
            else:
                req_names = record["prerequisite_names"]
                if req_names:
                    reason = f"Доступно на основе: {', '.join(req_names)}"
                else:
                    reason = "Базовая дисциплина"
            print(f"- {record['name']} (ID: {record['id']}) | {reason}")
    driver.close()

if __name__ == "__main__":
    test_recommendations(335200)
