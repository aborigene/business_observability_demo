const express = require('express');
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const logger = require('./utils/logger');
const tracing = require('./utils/tracing');

const app = express();
app.use(express.json());

// Configuration from environment variables
const PORT = process.env.PORT || 3000;
const TIER2_URL = process.env.TIER2_URL || 'http://tier2-service:8080';
const UNAUTHORIZED_REGIONS = (process.env.UNAUTHORIZED_REGIONS || '').split(',').filter(r => r);
const UNAUTHORIZED_CHANNELS = (process.env.UNAUTHORIZED_CHANNELS || '').split(',').filter(c => c);
const ENVIRONMENT = process.env.ENVIRONMENT || 'demo';

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'tier1-authorization', timestamp: new Date().toISOString() });
});

// Main loan application endpoint
app.post('/loan/applications', async (req, res) => {
  const startTime = Date.now();
  const traceparent = req.headers['traceparent'] || tracing.generateTraceparent();
  const tracestate = req.headers['tracestate'] || '';
  
  try {
    // Step 1: Validate required fields
    const validation = validateRequest(req.body);
    if (!validation.valid) {
      logger.warn('Validation failed', {
        errors: validation.errors,
        traceparent,
        latencyMs: Date.now() - startTime
      });
      return res.status(400).json({
        error: 'Validation failed',
        details: validation.errors
      });
    }

    // Generate application ID
    const applicationId = uuidv4();
    
    // Enrich request data
    const applicationData = {
      ...req.body,
      applicationId,
      environment: ENVIRONMENT,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    // Step 2: Authorization checks
    const authCheck = checkAuthorization(applicationData);
    if (!authCheck.authorized) {
      logger.warn('Authorization failed', {
        applicationId,
        customerId: applicationData.customerId,
        region: applicationData.region,
        channel: applicationData.channel,
        reason: authCheck.reason,
        traceparent,
        latencyMs: Date.now() - startTime
      });
      return res.status(200).json({
        status: 'unauthorized',
        message: 'Loan application not authorized',
        reason: authCheck.reason,
        applicationId,
        details: {
          customerId: applicationData.customerId,
          region: applicationData.region,
          channel: applicationData.channel,
          requestedAmount: applicationData.requestedAmount
        }
      });
    }

    // Step 3: Log authorized request with business attributes
    logger.info('Loan application authorized', {
      applicationId,
      customerId: applicationData.customerId,
      requestedAmount: applicationData.requestedAmount,
      product: applicationData.product,
      channel: applicationData.channel,
      region: applicationData.region,
      segment: applicationData.segment,
      costCenter: applicationData.costCenter,
      team: applicationData.team,
      environment: ENVIRONMENT,
      traceparent,
      latencyMs: Date.now() - startTime
    });

    // Step 4: Forward to Tier 2 (Credit Analysis)
    const tier2Response = await axios.post(
      `${TIER2_URL}/internal/credit/analyze`,
      applicationData,
      {
        headers: {
          'Content-Type': 'application/json',
          'traceparent': traceparent,
          'tracestate': tracestate,
          'x-application-id': applicationId
        },
        timeout: 30000
      }
    );

    // Return response
    const totalLatency = Date.now() - startTime;
    logger.info('Loan application processed successfully', {
      applicationId,
      customerId: applicationData.customerId,
      costCenter: applicationData.costCenter,
      team: applicationData.team,
      traceparent,
      latencyMs: totalLatency
    });

    res.status(201).json({
      applicationId,
      status: 'processing',
      data: tier2Response.data,
      processingTimeMs: totalLatency
    });

  } catch (error) {
    const errorLatency = Date.now() - startTime;
    logger.error('Error processing loan application', {
      error: error.message,
      stack: error.stack,
      traceparent,
      latencyMs: errorLatency
    });

    if (error.response) {
      return res.status(error.response.status).json({
        error: 'Downstream service error',
        message: error.message,
        details: error.response.data
      });
    }

    res.status(500).json({
      error: 'Internal server error',
      message: error.message
    });
  }
});

// GET endpoint to retrieve application (mock implementation)
app.get('/loan/applications/:id', async (req, res) => {
  const { id } = req.params;
  const traceparent = req.headers['traceparent'] || tracing.generateTraceparent();

  logger.info('Retrieving loan application', {
    applicationId: id,
    traceparent
  });

  // In a real scenario, this would query Tier 5 or a database
  // For now, return a placeholder response
  res.json({
    applicationId: id,
    status: 'completed',
    message: 'This endpoint would query the final tier or database for application details'
  });
});

// Validation function
function validateRequest(body) {
  const errors = [];
  const requiredFields = [
    'customerId',
    'requestedAmount',
    'termMonths',
    'product',
    'channel',
    'region',
    'segment',
    'costCenter',
    'team'
  ];

  requiredFields.forEach(field => {
    if (!body[field]) {
      errors.push(`Missing required field: ${field}`);
    }
  });

  // Type validations
  if (body.requestedAmount && typeof body.requestedAmount !== 'number') {
    errors.push('requestedAmount must be a number');
  }
  if (body.termMonths && typeof body.termMonths !== 'number') {
    errors.push('termMonths must be a number');
  }

  // Range validations
  if (body.requestedAmount && body.requestedAmount <= 0) {
    errors.push('requestedAmount must be greater than 0');
  }
  if (body.termMonths && (body.termMonths <= 0 || body.termMonths > 360)) {
    errors.push('termMonths must be between 1 and 360');
  }

  return {
    valid: errors.length === 0,
    errors
  };
}

// Authorization check function
function checkAuthorization(data) {
  // Check unauthorized regions
  if (UNAUTHORIZED_REGIONS.includes(data.region)) {
    return {
      authorized: false,
      reason: `Region '${data.region}' is not authorized for loan applications`
    };
  }

  // Check unauthorized channels
  if (UNAUTHORIZED_CHANNELS.includes(data.channel)) {
    return {
      authorized: false,
      reason: `Channel '${data.channel}' is not authorized for loan applications`
    };
  }

  return { authorized: true };
}

// Start server
app.listen(PORT, () => {
  logger.info('Tier 1 Authorization Service started', {
    port: PORT,
    tier2Url: TIER2_URL,
    unauthorizedRegions: UNAUTHORIZED_REGIONS,
    unauthorizedChannels: UNAUTHORIZED_CHANNELS,
    environment: ENVIRONMENT
  });
  console.log(`Tier 1 - Authorization Service running on port ${PORT}`);
});

module.exports = app;
