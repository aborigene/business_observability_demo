const crypto = require('crypto');

/**
 * Generate a W3C Trace Context traceparent header
 * Format: version-traceId-spanId-flags
 * Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
 */
function generateTraceparent() {
  const version = '00';
  const traceId = crypto.randomBytes(16).toString('hex');
  const spanId = crypto.randomBytes(8).toString('hex');
  const flags = '01'; // sampled
  
  return `${version}-${traceId}-${spanId}-${flags}`;
}

/**
 * Parse traceparent header
 */
function parseTraceparent(traceparent) {
  if (!traceparent) return null;
  
  const parts = traceparent.split('-');
  if (parts.length !== 4) return null;
  
  return {
    version: parts[0],
    traceId: parts[1],
    spanId: parts[2],
    flags: parts[3]
  };
}

/**
 * Generate a new span ID for child span
 */
function generateSpanId() {
  return crypto.randomBytes(8).toString('hex');
}

module.exports = {
  generateTraceparent,
  parseTraceparent,
  generateSpanId
};
