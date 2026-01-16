import asyncio
import random
from typing import List, Optional
from fastapi import Depends, FastAPI, HTTPException, Header, BackgroundTasks
from pydantic import BaseModel, ValidationError, field_validator

app = FastAPI(title="Smarsh Backend Assessment")

# --- IN-MEMORY DATA STORE (Mocking SQL/Elastic) ---
DB = {}        

# --- MODELS ---
class TranscriptPayload(BaseModel):
    conversation_id: str
    text: str

    @field_validator('text', mode='after')  
    @classmethod
    def text_validation(cls, value: str):
        if not value.strip() or len(value) > 5000:
            raise ValueError(f'Text must be non-empty and less than 5000 characters')
        return value

class AgentResponse(BaseModel):
    conversation_id: str
    sentiment_score: float
    summary: str
    tags: List[str]
    status: str

def get_db(): 
    return DB

def get_tenant_db(x_tenant_id: str = Header(...), db: dict = Depends(get_db)):
    if x_tenant_id not in db:
        db[x_tenant_id] = {}
    return db[x_tenant_id]

def compute_sentiment_score(base: float = 0.8):
    variance = random.uniform(-0.1, 0.1)
    return round(base + variance, 3)


# --- ASYNC PROCESSOR (Simulating your "Pipeline") ---
async def run_data_pipeline(tenant_db, tenant_id: str, data: TranscriptPayload ):
    await    asyncio.sleep(3) # Simulate Queue Latency
    base_sentiment = 0.8
    variance = random.uniform(-0.1, 0.1)
    result = {
        "conversation_id": data.conversation_id,
        "sentiment_score": round(base_sentiment + variance, 3),
        "summary": f"Processed text length {len(data.text)}.",
        "tags": ["finance", "risk"] if "money" in data.text else ["general"],
        "status": "COMPLETED",
        "tenant_id": tenant_id
    }
    tenant_db[data.conversation_id] = result

async def run_rescore_pipeline(tenant_db, conversation_id: str):
    await asyncio.sleep(2)
    item = tenant_db.get(conversation_id)
    if not item:
        return
    
    new_score = compute_sentiment_score(item["sentiment_score"])
    if new_score < 0.5 and "review_required" not in item["tags"]:
        item["tags"].append("review_required")
    item["sentiment_score"] = new_score

    tenant_db[conversation_id] = item

# --- ENDPOINTS ---
@app.post("/ingest", status_code=202)
async def ingest_transcript(
    payload: TranscriptPayload,
    background_tasks: BackgroundTasks,
    x_tenant_id: str = Header(...),
    tenant_db: dict = Depends(get_tenant_db)
):
    if not x_tenant_id:
        raise HTTPException(status_code=400, detail="Missing Tenant ID")
    
    background_tasks.add_task(run_data_pipeline, tenant_db, x_tenant_id, payload)
    return {"message": "Ingest started", "job_id": payload.conversation_id,
            "status": "QUEUED"}

@app.get("/results/{conversation_id}", response_model=AgentResponse)
async def get_result(conversation_id: str, tenant_db: dict = Depends(get_tenant_db)):
    item = tenant_db.get(conversation_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found or processing")
    return item

@app.post("/rescore/{conversation_id}", status_code=202)
async def update_sentiment_score(
    conversation_id: str,
    background_tasks: BackgroundTasks,
    tenant_db: dict = Depends(get_tenant_db)
):
    item = tenant_db.get(conversation_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found or processing")
    
    background_tasks.add_task(run_rescore_pipeline, tenant_db, conversation_id)
    return {"message": "Rescore started", "conversation_id": conversation_id, "status": "QUEUED"}
