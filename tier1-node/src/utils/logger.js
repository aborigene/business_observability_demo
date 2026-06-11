const winston = require('winston');

// Wire up OTel log export if endpoint is configured
const otelTransport = (() => {
  if (!process.env.OTEL_EXPORTER_OTLP_ENDPOINT) return null;
  try {
    const { LoggerProvider, SimpleLogRecordProcessor } = require('@opentelemetry/sdk-logs');
    const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
    const { OpenTelemetryTransportV3 } = require('@opentelemetry/winston-transport');
    const { Resource } = require('@opentelemetry/resources');
    const lp = new LoggerProvider({
      resource: new Resource({ 'service.name': process.env.OTEL_SERVICE_NAME || 'tier1-authorization' })
    });
    lp.addLogRecordProcessor(new SimpleLogRecordProcessor(new OTLPLogExporter()));
    return new OpenTelemetryTransportV3({ loggerProvider: lp });
  } catch (e) {
    console.error('OTel log init failed:', e.message);
    return null;
  }
})();

const transports = [
  new winston.transports.Console({
    format: winston.format.combine(
      winston.format.colorize(),
      winston.format.printf(({ timestamp, level, message, ...meta }) => {
        return `${timestamp} [${level}] ${message} ${Object.keys(meta).length ? JSON.stringify(meta) : ''}`;
      })
    )
  })
];

if (otelTransport) transports.push(otelTransport);

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: {
    service: 'tier1-authorization',
    tier: 'tier1'
  },
  transports
});

module.exports = logger;
