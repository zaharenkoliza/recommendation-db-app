from neo4j import GraphDatabase

def debug_student(student_id):
    driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))
    with driver.session() as session:
        print(f"--- Relationships for Student {student_id} ---")
        res = session.run("MATCH (s:Student {id: $id})-[r]->(d:Discipline) RETURN type(r) as type, d.name as name, d.id as id", {"id": student_id})
        for rec in res:
            print(f"{rec['type']} -> {rec['name']} (ID: {rec['id']})")
            
        print(f"\n--- Prerequisites for key disciplines ---")
        res = session.run("MATCH (d:Discipline)-[:REQUIRES]->(req) WHERE d.id IN [6132, 6230, 6400] RETURN d.name as name, d.id as id, req.name as req_name, req.id as req_id")
        for rec in res:
            print(f"Discipline {rec['name']} ({rec['id']}) REQUIRES {rec['req_name']} ({rec['req_id']})")
    driver.close()

if __name__ == "__main__":
    debug_student(335200)
