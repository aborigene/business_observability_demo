from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from typing import Optional
import httpx
import os
import logging
from datetime import datetime
import json
import asyncio

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Loan Decision Service (Tier 4 - SaaS Simulator)")

# Configuration from environment
TIER5_URL = os.getenv("TIER5_URL", "http://tier5-service:5000")
DT_ENV_URL = os.getenv("DT_ENV_URL", "")
DT_API_TOKEN = os.getenv("DT_API_TOKEN", "")
APPROVAL_THRESHOLD = int(os.getenv("APPROVAL_THRESHOLD", "60"))
REJECTION_THRESHOLD = int(os.getenv("REJECTION_THRESHOLD", "40"))
ENVIRONMENT = os.getenv("ENVIRONMENT", "demo")

# Validate Dynatrace configuration
if not DT_ENV_URL or not DT_API_TOKEN:
    logger.warning("⚠️  DT_ENV_URL or DT_API_TOKEN not configured. Business Events will not be sent.")

class LoanApplication(BaseModel):
    applicationId: str
    customerId: str
    requestedAmount: float
    termMonths: int
    product: str
    channel: str
    region: str
    segment: str
    costCenter: str
    team: str
    environment: str
    createdAt: str
    updatedAt: str
    tier2Score: Optional[int] = None
    tier3Score: Optional[int] = None
    finalScore: Optional[int] = None
    decisionStatus: Optional[str] = None
    approvedAmount: Optional[float] = None
    totalDue: Optional[float] = None
    decisionReason: Optional[str] = None


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "tier4-decision-service",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.post("/internal/decision/evaluate")
async def evaluate_decision(
    application: LoanApplication,
    traceparent: Optional[str] = Header(None),
    tracestate: Optional[str] = Header(None),
    x_application_id: Optional[str] = Header(None, alias="x-application-id")
):
    start_time = datetime.now()
    
    logger.info(
        f"Tier 4: Received decision evaluation request - "
        f"applicationId: {application.applicationId}, "
        f"customerId: {application.customerId}, "
        f"requestedAmount: {application.requestedAmount}, "
        f"tier2Score: {application.tier2Score}, "
        f"tier3Score: {application.tier3Score}, "
        f"costCenter: {application.costCenter}, "
        f"team: {application.team}, "
        f"traceparent: {traceparent}"
    )
    
    # Calculate final score
    tier2_score = application.tier2Score or 0
    tier3_score = application.tier3Score or 0
    final_score = tier2_score + tier3_score
    
    application.finalScore = final_score
    
    # Determine decision status based on thresholds
    if final_score >= APPROVAL_THRESHOLD:
        application.decisionStatus = "APPROVED"
        application.decisionReason = f"Final score {final_score} meets approval threshold of {APPROVAL_THRESHOLD}"
    elif final_score <= REJECTION_THRESHOLD:
        application.decisionStatus = "REJECTED"
        application.decisionReason = f"Final score {final_score} below rejection threshold of {REJECTION_THRESHOLD}"
    else:
        application.decisionStatus = "PARTIALLY_APPROVED"
        application.decisionReason = f"Final score {final_score} qualifies for partial approval (between {REJECTION_THRESHOLD} and {APPROVAL_THRESHOLD})"
    
    application.updatedAt = datetime.utcnow().isoformat()
    
    logger.info(
        f"Tier 4: Decision calculated - "
        f"applicationId: {application.applicationId}, "
        f"finalScore: {final_score}, "
        f"decisionStatus: {application.decisionStatus}, "
        f"approvalThreshold: {APPROVAL_THRESHOLD}, "
        f"rejectionThreshold: {REJECTION_THRESHOLD}"
    )
    
    # Send Business Event to Dynatrace (async, non-blocking)
    asyncio.create_task(send_business_event(application, traceparent))
    
    # Forward to Tier 5 for final calculation and persistence
    try:
        tier5_response = await forward_to_tier5(application, traceparent, tracestate)
        
        latency_ms = (datetime.now() - start_time).total_seconds() * 1000
        
        logger.info(
            f"Tier 4: Decision complete and forwarded to Tier 5 - "
            f"applicationId: {application.applicationId}, "
            f"decisionStatus: {application.decisionStatus}, "
            f"latencyMs: {latency_ms:.2f}"
        )
        
        return tier5_response
        
    except Exception as e:
        latency_ms = (datetime.now() - start_time).total_seconds() * 1000
        logger.error(
            f"Tier 4: Error forwarding to Tier 5 - "
            f"applicationId: {application.applicationId}, "
            f"error: {str(e)}, "
            f"latencyMs: {latency_ms:.2f}"
        )
        raise HTTPException(status_code=502, detail=f"Failed to forward to Tier 5: {str(e)}")


async def send_business_event(application: LoanApplication, traceparent: Optional[str]):
    """
    Send Business Event to Dynatrace via Ingest API
    This simulates a SaaS service publishing domain events
    """
    if not DT_ENV_URL or not DT_API_TOKEN:
        logger.warning(f"Skipping Business Event - DT configuration missing for applicationId: {application.applicationId}")
        return
    
    try:
        event_payload = {
            "eventType": "bizevents",
            "events": [
                {
                    "event.type": "com.loan.decision.made",
                    "event.provider": "loan-decision-service",
                    "timestamp": datetime.utcnow().isoformat() + "Z",
                    
                    # Business identifiers
                    "loan.applicationId": application.applicationId,
                    "loan.customerId": application.customerId,
                    "loan.requestedAmount": application.requestedAmount,
                    "loan.approvedAmount": application.approvedAmount or 0,
                    "loan.termMonths": application.termMonths,
                    
                    # Scores
                    "loan.tier2Score": application.tier2Score or 0,
                    "loan.tier3Score": application.tier3Score or 0,
                    "loan.finalScore": application.finalScore or 0,
                    
                    # Decision
                    "loan.decisionStatus": application.decisionStatus,
                    "loan.decisionReason": application.decisionReason,
                    
                    # Business dimensions for Cost Allocation
                    "loan.product": application.product,
                    "loan.segment": application.segment,
                    "loan.channel": application.channel,
                    "loan.region": application.region,
                    "loan.costCenter": application.costCenter,
                    "loan.team": application.team,
                    "loan.environment": application.environment,
                    
                    # Trace correlation (if available)
                    "dt.trace_id": extract_trace_id(traceparent) if traceparent else None
                }
            ]
        }
        
        # Remove None values
        event_payload["events"][0] = {k: v for k, v in event_payload["events"][0].items() if v is not None}
        
        # Send to Dynatrace Business Events API
        ingest_url = f"{DT_ENV_URL}/api/v2/bizevents/ingest"
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                ingest_url,
                json=event_payload,
                headers={
                    "Authorization": f"Api-Token {DT_API_TOKEN}",
                    "Content-Type": "application/json"
                },
                timeout=10.0
            )
            
            if response.status_code == 202:
                logger.info(
                    f"✅ Business Event sent successfully - "
                    f"applicationId: {application.applicationId}, "
                    f"decisionStatus: {application.decisionStatus}, "
                    f"costCenter: {application.costCenter}, "
                    f"team: {application.team}"
                )
            else:
                logger.error(
                    f"❌ Failed to send Business Event - "
                    f"applicationId: {application.applicationId}, "
                    f"status: {response.status_code}, "
                    f"response: {response.text}"
                )
                
    except Exception as e:
        logger.error(
            f"❌ Error sending Business Event - "
            f"applicationId: {application.applicationId}, "
            f"error: {str(e)}"
        )


async def forward_to_tier5(
    application: LoanApplication,
    traceparent: Optional[str],
    tracestate: Optional[str]
):
    """Forward request to Tier 5 for final calculation and persistence"""
    
    headers = {
        "Content-Type": "application/json"
    }
    
    if traceparent:
        headers["traceparent"] = traceparent
    if tracestate:
        headers["tracestate"] = tracestate
    if application.applicationId:
        headers["x-application-id"] = application.applicationId
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{TIER5_URL}/internal/loan/finalize",
            json=application.dict(),
            headers=headers,
            timeout=30.0
        )
        response.raise_for_status()
        return response.json()


def extract_trace_id(traceparent: str) -> Optional[str]:
    """Extract trace ID from W3C traceparent header"""
    try:
        parts = traceparent.split('-')
        if len(parts) >= 2:
            return parts[1]  # Return the trace-id part
    except Exception:
        pass
    return None


if __name__ == "__main__":
    import uvicorn
    
    logger.info("=" * 60)
    logger.info("Tier 4 - Loan Decision Service (SaaS Simulator) Starting")
    logger.info("=" * 60)
    logger.info(f"Tier 5 URL: {TIER5_URL}")
    logger.info(f"Approval Threshold: {APPROVAL_THRESHOLD}")
    logger.info(f"Rejection Threshold: {REJECTION_THRESHOLD}")
    logger.info(f"Dynatrace Configured: {bool(DT_ENV_URL and DT_API_TOKEN)}")
    logger.info(f"Environment: {ENVIRONMENT}")
    logger.info("=" * 60)
    
    uvicorn.run(app, host="0.0.0.0", port=8001)
