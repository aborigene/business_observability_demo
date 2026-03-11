package com.dynatrace.demo.loan.controller;

import com.dynatrace.demo.loan.model.LoanApplication;
import com.dynatrace.demo.loan.service.CreditAnalysisService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/internal/credit")
@Slf4j
public class CreditAnalysisController {

    @Autowired
    private CreditAnalysisService creditAnalysisService;

    @PostMapping("/analyze")
    public ResponseEntity<LoanApplication> analyzeCreditScore(
            @RequestBody LoanApplication application,
            @RequestHeader(value = "traceparent", required = false) String traceparent,
            @RequestHeader(value = "tracestate", required = false) String tracestate,
            @RequestHeader(value = "x-application-id", required = false) String applicationIdHeader) {
        
        long startTime = System.currentTimeMillis();
        
        try {
            log.info("Tier 2: Received credit analysis request - applicationId: {}, customerId: {}, " +
                    "requestedAmount: {}, channel: {}, region: {}, segment: {}, costCenter: {}, team: {}, " +
                    "environment: {}, traceparent: {}",
                    application.getApplicationId(),
                    application.getCustomerId(),
                    application.getRequestedAmount(),
                    application.getChannel(),
                    application.getRegion(),
                    application.getSegment(),
                    application.getCostCenter(),
                    application.getTeam(),
                    application.getEnvironment(),
                    traceparent);

            // Process credit analysis
            LoanApplication result = creditAnalysisService.performCreditAnalysis(
                    application, traceparent, tracestate);

            long latency = System.currentTimeMillis() - startTime;
            
            log.info("Tier 2: Credit analysis completed - applicationId: {}, customerId: {}, " +
                    "tier2Score: {}, costCenter: {}, team: {}, latencyMs: {}, traceparent: {}",
                    result.getApplicationId(),
                    result.getCustomerId(),
                    result.getTier2Score(),
                    result.getCostCenter(),
                    result.getTeam(),
                    latency,
                    traceparent);

            return ResponseEntity.ok(result);
            
        } catch (Exception e) {
            long latency = System.currentTimeMillis() - startTime;
            log.error("Tier 2: Error during credit analysis - applicationId: {}, error: {}, " +
                    "latencyMs: {}, traceparent: {}",
                    application.getApplicationId(),
                    e.getMessage(),
                    latency,
                    traceparent,
                    e);
            throw e;
        }
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of(
                "status", "healthy",
                "service", "tier2-credit-analysis",
                "timestamp", java.time.Instant.now().toString()
        ));
    }
}
