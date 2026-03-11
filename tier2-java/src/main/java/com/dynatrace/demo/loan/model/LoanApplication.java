package com.dynatrace.demo.loan.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class LoanApplication {
    private String applicationId;
    private String customerId;
    private Double requestedAmount;
    private Integer termMonths;
    private String product;
    private String channel;
    private String region;
    private String segment;
    private String costCenter;
    private String team;
    private String environment;
    private Instant createdAt;
    private Instant updatedAt;
    
    // Credit scores
    private Integer tier2Score;
    private Integer tier3Score;
    private Integer finalScore;
    
    // Decision fields
    private String decisionStatus;
    private Double approvedAmount;
    private Double totalDue;
    private String decisionReason;
}
