package com.dynatrace.demo.loan.service;

import com.dynatrace.demo.loan.model.LoanApplication;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Instant;
import java.util.Random;

@Service
@Slf4j
public class CreditAnalysisService {

    private final WebClient webClient;
    private final Random random = new Random();

    @Value("${tier3.url:http://tier3-service:8000}")
    private String tier3Url;

    public CreditAnalysisService(WebClient webClient) {
        this.webClient = webClient;
    }

    public LoanApplication performCreditAnalysis(LoanApplication application, 
                                                  String traceparent, 
                                                  String tracestate) {
        // Generate tier2Score (0-70)
        int tier2Score = random.nextInt(71); // 0 to 70 inclusive
        
        application.setTier2Score(tier2Score);
        application.setUpdatedAt(Instant.now());

        log.info("Tier 2: Generated credit score - applicationId: {}, tier2Score: {}, " +
                "customerId: {}, requestedAmount: {}",
                application.getApplicationId(),
                tier2Score,
                application.getCustomerId(),
                application.getRequestedAmount());

        // Forward to Tier 3 for advanced risk analysis
        try {
            LoanApplication tier3Result = forwardToTier3(application, traceparent, tracestate);
            return tier3Result;
        } catch (Exception e) {
            log.error("Tier 2: Error forwarding to Tier 3 - applicationId: {}, error: {}",
                    application.getApplicationId(),
                    e.getMessage(),
                    e);
            throw new RuntimeException("Failed to forward to Tier 3: " + e.getMessage(), e);
        }
    }

    private LoanApplication forwardToTier3(LoanApplication application, 
                                           String traceparent, 
                                           String tracestate) {
        log.info("Tier 2: Forwarding to Tier 3 - applicationId: {}, tier3Url: {}",
                application.getApplicationId(),
                tier3Url);

        WebClient.RequestHeadersSpec<?> request = webClient.post()
                .uri(tier3Url + "/internal/risk/advanced")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(application);

        // Add tracing headers
        if (traceparent != null && !traceparent.isEmpty()) {
            request = request.header("traceparent", traceparent);
        }
        if (tracestate != null && !tracestate.isEmpty()) {
            request = request.header("tracestate", tracestate);
        }
        if (application.getApplicationId() != null) {
            request = request.header("x-application-id", application.getApplicationId());
        }

        return request
                .retrieve()
                .bodyToMono(LoanApplication.class)
                .block();
    }
}
