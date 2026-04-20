import os
import psycopg2
from neo4j import GraphDatabase
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:rootpassword@localhost:5432/itmo_db")
    NEO4J_URI: str = os.getenv("NEO4J_URI", "bolt://localhost:7687")
    NEO4J_USER: str = os.getenv("NEO4J_USER", "neo4j")
    NEO4J_PASSWORD: str = os.getenv("NEO4J_PASSWORD", "password")

settings = Settings()

# Postgres Connection
def get_pg_conn():
    conn = psycopg2.connect(settings.DATABASE_URL)
    return conn

# Neo4j Connection
class Neo4jHandler:
    def __init__(self):
        self.driver = GraphDatabase.driver(
            settings.NEO4J_URI, 
            auth=(settings.NEO4J_USER, settings.NEO4J_PASSWORD)
        )

    def close(self):
        self.driver.close()

    def query(self, cypher, parameters=None):
        with self.driver.session() as session:
            result = session.run(cypher, parameters)
            return [record.data() for record in result]

neo4j_db = Neo4jHandler()
