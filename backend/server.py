import os
from pathlib import Path
from fastapi import FastAPI, Depends, HTTPException
from fastapi.responses import StreamingResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from fastapi_clerk_auth import ClerkConfig, ClerkHTTPBearer, HTTPAuthorizationCredentials
from openai import OpenAI, APIConnectionError, APIStatusError, RateLimitError

app = FastAPI()

def _cors_origins_from_env() -> list[str]:
    """
    Comma-separated list of allowed origins.
    Example: "http://localhost:3000,https://dxxxx.cloudfront.net"
    """
    raw = (os.getenv("ALLOWED_CORS_ORIGINS") or "").strip()
    defaults = ["http://localhost:3000", "http://127.0.0.1:3000"]
    if not raw:
        return defaults

    # Support comma or whitespace separated values to avoid common env mistakes.
    parts = [p for p in raw.replace(",", " ").split() if p.strip()]
    extra = [o.strip().rstrip("/") for o in parts]
    # Always allow local dev origins even if env is misconfigured.
    return list(dict.fromkeys([*defaults, *extra]))

# Add CORS middleware (allows frontend to call backend)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins_from_env(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Clerk authentication setup
clerk_config = ClerkConfig(jwks_url=os.getenv("CLERK_JWKS_URL"))
clerk_guard = ClerkHTTPBearer(clerk_config)

class Visit(BaseModel):
    patient_name: str
    date_of_visit: str
    notes: str

system_prompt = """
You are provided with notes written by a doctor from a patient's visit.
Your job is to summarize the visit for the doctor and provide an email.
Reply with exactly three sections with the headings:
### Summary of visit for the doctor's records
### Next steps for the doctor
### Draft of email to patient in patient-friendly language
"""

def user_prompt_for(visit: Visit) -> str:
    return f"""Create the summary, next steps and draft email for:
Patient Name: {visit.patient_name}
Date of Visit: {visit.date_of_visit}
Notes:
{visit.notes}"""

@app.post("/api/consultation")
def consultation_summary(
    visit: Visit,
    creds: HTTPAuthorizationCredentials = Depends(clerk_guard),
):
    user_id = creds.decoded["sub"]
    client = OpenAI()
    
    user_prompt = user_prompt_for(visit)
    prompt = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt},
    ]
    
    try:
        stream = client.chat.completions.create(
            model="gpt-5-nano",
            messages=prompt,
            stream=True,
        )
    except RateLimitError as e:
        # Most common local-dev failure: key has no quota/billing enabled.
        raise HTTPException(status_code=429, detail="OpenAI quota exceeded. Check plan/billing for your API key.") from e
    except APIConnectionError as e:
        raise HTTPException(status_code=502, detail="Failed to reach OpenAI API.") from e
    except APIStatusError as e:
        raise HTTPException(status_code=502, detail=f"OpenAI API error ({e.status_code}).") from e
    
    def event_stream():
        for chunk in stream:
            text = chunk.choices[0].delta.content
            if text:
                lines = text.split("\n")
                for line in lines[:-1]:
                    yield f"data: {line}\n\n"
                    yield "data:  \n"
                yield f"data: {lines[-1]}\n\n"
    
    return StreamingResponse(event_stream(), media_type="text/event-stream")

@app.get("/health")
def health_check():
    """Health check endpoint for AWS App Runner"""
    return {"status": "healthy"}
